require "minitest/autorun"
require "tmpdir"
require "open3"
require "rbconfig"
require_relative "../src/invoice_store"

class InvoiceStoreTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("invoice-store-test-")
    @config = { "outputDir" => File.join(@directory, "exports"), "rateUsd" => 10, "exchRate" => 80 }
    @store = InvoiceStore.new(@config)
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def legacy_invoice(month = "August 2026", number = "007")
    { "month" => month, "invoiceNo" => number, "hours" => 999, "amount" => 123,
      "targetHours" => 160, "dailyTargetHours" => 8,
      "reimbursements" => [{ "id" => "receipt-1", "name" => "Hosting", "amount" => 100, "attachment" => "reimbursements/receipt.pdf" }] }
  end

  def seed_legacy
    record = legacy_invoice
    @config["invoices"] = [record]
    dir = @store.directory(record)
    FileUtils.mkdir_p(File.join(dir, "reimbursements"))
    File.binwrite(File.join(dir, "reimbursements", "receipt.pdf"), "untouched receipt")
    File.write(File.join(dir, "TimeLog_August_2026.json"), JSON.generate("month" => "August 2026", "days" => []))
    dir
  end

  def test_allocations_are_stable_and_metadata_has_no_calculated_values
    first = @store.find_or_create("September 2026")
    assert_equal "001", first["invoiceNo"]
    assert_equal first, @store.find_or_create("September 2026")
    assert_equal "002", @store.find_or_create("April 2026")["invoiceNo"]
    path = File.join(@store.directory(first), "invoice.json")
    assert_equal({ "month" => "September 2026", "invoiceNo" => "001" }, JSON.parse(File.read(path)))
    assert_equal 3, JSON.parse(File.read(File.join(@store.root, "sequence.json")))["nextInvoiceNo"]
    @store.update_metadata("September 2026", "targetHours" => 150)
    assert_equal 150, @store.find("September 2026")["targetHours"]
  end

  def test_import_preserves_files_numbers_overrides_and_config
    dir = seed_legacy
    original = Marshal.dump(@config)
    log = File.binread(File.join(dir, "TimeLog_August_2026.json"))
    records = @store.records
    assert_equal original, Marshal.dump(@config)
    assert_equal "007", records.first["invoiceNo"]
    assert_equal 160, records.first["targetHours"]
    assert_equal 8, records.first["dailyTargetHours"]
    assert_equal @config["invoices"][0]["reimbursements"], JSON.parse(File.read(File.join(dir, "reimbursements.json")))
    assert_equal log, File.binread(File.join(dir, "timelog.json"))
    refute File.exist?(File.join(dir, "TimeLog_August_2026.json"))
    assert_equal "untouched receipt", File.binread(File.join(dir, "reimbursements", "receipt.pdf"))
    metadata = JSON.parse(File.read(File.join(dir, "invoice.json")))
    refute metadata.key?("hours")
    refute metadata.key?("amount")
    refute metadata.key?("reimbursements")
    assert_equal "008", @store.find_or_create("September 2026")["invoiceNo"]
  end

  def test_stale_legacy_config_never_restores_removed_reimbursements_or_overrides
    seed_legacy
    @store.records
    @store.update_reimbursements("August 2026") { |_, _| [] }
    @store.update_metadata("August 2026", "targetHours" => 100)
    again = InvoiceStore.new(@config).find("August 2026")
    assert_empty again["reimbursements"]
    assert_equal 100, again["targetHours"]
  end

  def test_explicit_cleanup_backs_up_original_config_and_is_idempotent
    seed_legacy
    path = File.join(@directory, "config.json")
    original = JSON.pretty_generate(@config) + "\n"
    File.write(path, original)
    result = InvoiceStore.migrate_config(path)
    assert result["configUpdated"]
    assert_equal original, File.binread(result["backupPath"])
    assert_equal @config.reject { |key, _| key == "invoices" }, JSON.parse(File.read(path))
    after = File.binread(path)
    refute InvoiceStore.migrate_config(path)["configUpdated"]
    assert_equal after, File.binread(path)
    assert_equal "007", InvoiceStore.new(JSON.parse(after)).find("August 2026")["invoiceNo"]
  end

  def test_conflicting_time_logs_are_not_overwritten
    dir = seed_legacy
    current = File.join(dir, "timelog.json")
    File.write(current, "different data")
    error = assert_raises(RuntimeError) { @store.records }
    assert_includes error.message, "Conflicting legacy and current time logs"
    assert_equal "different data", File.read(current)
    assert File.exist?(File.join(dir, "TimeLog_August_2026.json"))
    refute File.exist?(File.join(dir, "invoice.json"))
  end

  def test_duplicate_legacy_numbers_fail_before_migration
    @config["invoices"] = [legacy_invoice, legacy_invoice("September 2026")]
    assert_raises(RuntimeError) { @store.records }
    refute File.exist?(File.join(@store.root, "sequence.json"))
  end

  def test_counter_recovers_from_stale_sequence_and_reserved_directory
    first = @store.find_or_create("August 2026")
    sequence = File.join(@store.root, "sequence.json")
    InvoiceStore.write_json(sequence, "nextInvoiceNo" => 1, "legacyImported" => true)
    FileUtils.mkdir_p(File.join(@store.root, "002 September 2026"))
    assert_equal "002", @store.find_or_create("September 2026")["invoiceNo"]
    assert_equal "003", @store.find_or_create("October 2026")["invoiceNo"]
    assert_equal first, @store.find("August 2026")
  end

  def test_partial_allocation_retries_without_reusing_number
    @store.records
    writer = InvoiceStore.method(:write_json)
    InvoiceStore.stub(:write_json, ->(path, data) { path.end_with?("sequence.json") ? raise(IOError, "disk full") : writer.call(path, data) }) do
      assert_raises(IOError) { @store.find_or_create("August 2026") }
    end
    assert_equal "001", @store.find_or_create("August 2026")["invoiceNo"]
    assert_equal "002", @store.find_or_create("September 2026")["invoiceNo"]
  end

  def test_corrupt_sequence_is_not_reset
    FileUtils.mkdir_p(@store.root)
    path = File.join(@store.root, "sequence.json")
    File.write(path, "broken")
    assert_raises(JSON::ParserError) { @store.find_or_create("August 2026") }
    assert_equal "broken", File.read(path)
  end

  def test_concurrent_allocations_assign_one_number_per_month
    months = %w[April May June July August September].map { |month| "#{month} 2026" }
    children = (months * 2).map do |month|
      fork do
        begin
          InvoiceStore.new(@config).find_or_create(month)
          exit! 0
        rescue StandardError => error
          warn error.message
          exit! 1
        end
      end
    end
    children.each { |pid| assert Process.wait2(pid).last.success? }
    records = @store.records
    assert_equal months.sort, records.map { |item| item["month"] }.sort
    assert_equal (1..6).to_a, records.map { |item| item["invoiceNo"].to_i }.sort
    assert_equal 7, JSON.parse(File.read(File.join(@store.root, "sequence.json")))["nextInvoiceNo"]
  end

  def test_open_session_is_migrated_and_finished_with_read_only_config
    dir = seed_legacy
    state = {
      "month" => "August 2026", "date" => "2026-08-14", "status" => "paused",
      "startedAt" => "2026-08-14T09:00:00+05:30", "currentStartedAt" => nil, "elapsedSeconds" => 3600,
      "segments" => [{ "startedAt" => "2026-08-14T09:00:00+05:30", "endedAt" => "2026-08-14T10:00:00+05:30", "seconds" => 3600 }]
    }
    File.write(File.join(dir, "TimeLog_August_2026.state.json"), JSON.generate(state))
    config_path = File.join(@directory, "config.json")
    original = JSON.generate(@config)
    File.write(config_path, original)
    File.chmod(0444, config_path)
    registry = File.join(@directory, "registry.json")
    File.write(registry, JSON.generate("projects" => [{ "label" => "TEST", "configPath" => config_path, "active" => true }]))
    environment = {
      "INVOICE_AUTOMATION_CONFIG" => registry, "INVOICE_AUTOMATION_DATA_DIR" => @directory,
      "INVOICE_AUTOMATION_CACHE_DIR" => File.join(@directory, "cache"),
      "INVOICE_AUTOMATION_LOG_DIR" => File.join(@directory, "logs"),
      "INVOICE_AUTOMATION_ERROR_LOG" => File.join(@directory, "logs", "error.log")
    }
    cli = File.expand_path("../src/time_log.rb", __dir__)
    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, cli, "status")
    assert status.success?, stderr
    assert_equal "paused", JSON.parse(stdout)["status"]
    assert_equal state, JSON.parse(File.read(File.join(dir, "timelog.state.json")))
    _, stderr, status = Open3.capture3(environment, RbConfig.ruby, cli, "finish")
    assert status.success?, stderr
    refute File.exist?(File.join(dir, "timelog.state.json"))
    assert_equal 1.0, JSON.parse(File.read(File.join(dir, "timelog.json")))["days"][0]["actualHours"]
    assert_equal original, File.binread(config_path)
  end
end
