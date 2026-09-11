require "tmpdir"

TEST_STORAGE_ROOT = Dir.mktmpdir("invoice-reimbursement-test")
ENV["INVOICE_AUTOMATION_DATA_DIR"] = File.join(TEST_STORAGE_ROOT, "Application Support", "InvoiceTimer")
ENV["INVOICE_AUTOMATION_LOG_DIR"] = File.join(TEST_STORAGE_ROOT, "Logs", "InvoiceTimer")

require "minitest/autorun"
require_relative "../src/time_log"

class ReimbursementTest < Minitest::Test
  def setup
    FileUtils.rm_rf(TEST_STORAGE_ROOT)
    config_path = File.join(TEST_STORAGE_ROOT, "project", "config.json")
    FileUtils.mkdir_p(File.dirname(config_path))
    config = {
      "rateUsd" => 10,
      "exchRate" => 80,
      "reimbursements" => { "gstTreatment" => "excludedFromTaxableValue" },
      "taxProfile" => { "enabled" => false },
      "outputDir" => File.join(TEST_STORAGE_ROOT, "exports"),
      "invoices" => []
    }
    File.write(config_path, JSON.pretty_generate(config) + "\n")
    TimeLog.addProject("TEST", config_path)
    TimeLog.setDailyHours("August 2026", "2026-08-14", "manual", nil, "1", "")
  end

  def test_registry_retains_selected_config_path
    project = TimeLog.active_project
    assert_equal File.join(TEST_STORAGE_ROOT, "project", "config.json"), project.fetch("configPath")
  end

  def test_add_and_remove_with_attachment
    source = File.join(TEST_STORAGE_ROOT, "receipt.pdf")
    File.write(source, "supporting document")

    entries = TimeLog.addReimbursement("August 2026", "Hosting", "100", source)
    entry = entries.first
    assert_equal "Hosting", entry.fetch("name")
    assert_equal 100.0, entry.fetch("amount")

    config = TimeLog.load_config
    record = TimeLog.find_invoice_record(config, "August 2026")
    assert_equal 900, TimeLog.invoice_data("August 2026").fetch("amount")
    copied = File.join(config.fetch("outputDir"), "#{record.fetch('invoiceNo')} August 2026", entry.fetch("attachment"))
    assert File.file?(copied)

    TimeLog.removeReimbursement("August 2026", entry.fetch("id"))
    refute File.exist?(copied)
    assert_empty TimeLog.reimbursementEntries("August 2026")
  end

  def test_duplicate_attachment_filename_is_rejected
    first = File.join(TEST_STORAGE_ROOT, "one", "receipt.pdf")
    second = File.join(TEST_STORAGE_ROOT, "two", "receipt.pdf")
    FileUtils.mkdir_p(File.dirname(first))
    FileUtils.mkdir_p(File.dirname(second))
    File.write(first, "first")
    File.write(second, "second")
    TimeLog.addReimbursement("August 2026", "First", "10", first)

    error = assert_raises(RuntimeError) do
      TimeLog.addReimbursement("August 2026", "Second", "20", second)
    end
    assert_includes error.message, "already exists"
  end

  def test_time_log_is_stored_in_the_invoice_month_directory
    config = TimeLog.load_config
    record = TimeLog.find_invoice_record(config, "August 2026")
    expected_directory = File.join(config.fetch("outputDir"), "#{record.fetch('invoiceNo')} August 2026")
    paths = TimeLog.resolve_paths("August 2026")

    assert_equal File.join(expected_directory, "timelog.json"), paths.fetch(:logPath)
    assert_equal File.join(expected_directory, "timelog.state.json"), paths.fetch(:statePath)
    assert File.file?(paths.fetch(:logPath))
  end
end
