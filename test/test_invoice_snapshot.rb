require "minitest/autorun"
require "tmpdir"
require_relative "../src/generate_invoice"

class InvoiceSnapshotTest < Minitest::Test
  def setup
    @dir = Dir.mktmpdir("snapshot-test-")
    fixture = JSON.parse(File.read(File.join(__dir__, "fixtures/invoice_cases.json"))).first
    @config, @source = fixture.values_at("config", "record")
    @config.delete("invoices")
    @config["outputDir"] = File.join(@dir, "invoices")
    @config["secret"] = "never snapshot"
    @path = File.join(@dir, "project.json")
    File.write(@path, JSON.generate(@config))
    @store = InvoiceStore.new(@config)
    @month = @source["month"]
    @record = @store.find_or_create(@month)
    @source = @source.merge(@record.reject { |key, _| key == "reimbursements" })
  end

  def teardown
    FileUtils.remove_entry(@dir)
  end

  def generate(**options)
    InvoiceGenerator.stub(:active_config_path, @path) do
      TimeLog.stub(:invoice_data, @source) do
        InvoiceGenerator.stub(:render_invoice, ->(context, path) { File.write(path, "%PDF-#{JSON.generate(context)}") }) do
          InvoiceGenerator.generate(@month, **options)
        end
      end
    end
  end

  def test_snapshot_captures_values_and_reproduction_ignores_changed_inputs
    pdf = generate
    record = @store.find(@month)
    snapshot = record.fetch("snapshot")
    refute record.key?("status")
    refute snapshot.key?("renderContext")
    assert_equal "INR", snapshot["currency"]
    assert_equal @source["invoiceNo"], snapshot["invoiceNo"]
    assert_kind_of String, snapshot["totals"]["grandTotal"]
    assert_kind_of String, snapshot["service"]["rateUsd"]
    refute_includes JSON.generate(snapshot), "never snapshot"
    assert_equal Digest::SHA256.file(pdf).hexdigest, record["pdfSha256"]
    original = File.binread(pdf)
    File.write(@path, JSON.generate({ "outputDir" => @config["outputDir"] }))
    generate(reproduce: true)
    assert_equal original, File.binread(pdf)
    assert_equal snapshot, @store.find(@month)["snapshot"]
  end

  def test_configured_invoice_date_is_snapshotted_and_preserved_on_reproduction
    @config["invoiceDateTiming"] = "lastOfServiceMonth"
    File.write(@path, JSON.generate(@config))
    generate
    assert_equal "2026-08-31", @store.find(@month).fetch("snapshot").fetch("invoiceDate")

    @config["invoiceDateTiming"] = "firstOfFollowingMonth"
    File.write(@path, JSON.generate(@config))
    generate(reproduce: true)
    assert_equal "2026-08-31", @store.find(@month).fetch("snapshot").fetch("invoiceDate")
  end

  def test_regeneration_refreshes_snapshot_and_removes_legacy_lifecycle
    generate
    path = File.join(@store.directory(@record), "invoice.json")
    legacy = JSON.parse(File.read(path))
    legacy["status"] = "issued"
    legacy["snapshot"]["renderContext"] = { "obsolete" => true }
    File.write(path, JSON.generate(legacy))
    @source["hours"] = "1"
    @source["amount"] = TimeLog.calculated_invoice_amount(@config, @source, @month, "1")
    generate
    assert_equal "1.0", @store.find(@month)["snapshot"]["service"]["hours"]
    refute @store.find(@month).key?("status")
    refute @store.find(@month)["snapshot"].key?("renderContext")
  end

  def test_reproduction_of_previous_format_uses_structured_values
    pdf = generate
    original_pdf = File.binread(pdf)
    path = File.join(@store.directory(@record), "invoice.json")
    legacy = JSON.parse(File.read(path))
    legacy["status"] = "issued"
    legacy["snapshot"]["renderContext"] = { "obsolete" => true }
    File.write(path, JSON.generate(legacy))
    generate(reproduce: true)
    assert_equal original_pdf, File.binread(pdf)
    refute @store.find(@month).key?("status")
    refute @store.find(@month)["snapshot"].key?("renderContext")
  end

  def test_structured_snapshots_render_like_all_invoice_baselines
    JSON.parse(File.read(File.join(__dir__, "fixtures/invoice_cases.json"))).each do |fixture|
      config, record = fixture.values_at("config", "record")
      first, last, date = InvoiceCalculation.parse_month(record["month"])
      calc = InvoiceGenerator.calculate_invoice(config, record, first)
      expected = InvoiceGenerator.build_template_context(config, record, first, last, date, calc)
      snapshot = InvoiceGenerator.build_snapshot(config, record, first, last, date, calc, expected)
      assert_equal expected, InvoiceGenerator.snapshot_context(snapshot), fixture["name"]
    end
  end

  def test_older_records_are_not_backfilled_and_cannot_be_reproduced
    older = @store.find_or_create("January 2025")
    path = File.join(@store.directory(older), "invoice.json")
    original = File.binread(path)
    generate
    assert_equal original, File.binread(path)
    @month = "January 2025"
    assert_raises(InvoiceGenerator::ConfigError) { generate(reproduce: true) }
    assert_equal original, File.binread(path)
  end

  def test_render_failure_preserves_existing_pdf_and_snapshot
    pdf = generate
    original_pdf = File.binread(pdf)
    original = @store.find(@month)
    InvoiceGenerator.stub(:active_config_path, @path) do
      TimeLog.stub(:invoice_data, @source) do
        InvoiceGenerator.stub(:render_invoice, ->(_, path) { File.write(path, "partial"); raise "render failed" }) do
          assert_raises(RuntimeError) { InvoiceGenerator.generate(@month) }
        end
      end
    end
    assert_equal original_pdf, File.binread(pdf)
    assert_equal original, @store.find(@month)
  end

  def test_metadata_failure_restores_previous_pdf
    pdf = generate
    original_pdf = File.binread(pdf)
    original = @store.find(@month)
    InvoiceStore.stub(:write_json, ->(*) { raise "disk full" }) do
      assert_raises(RuntimeError) { generate }
    end
    assert_equal original_pdf, File.binread(pdf)
    assert_equal original, @store.find(@month)
  end
end
