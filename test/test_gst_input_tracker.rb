require "minitest/autorun"
require "tmpdir"
require "open3"
require "rbconfig"
require_relative "../src/gst_filing"

class GstInputTrackerTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("gst-input-test-")
    @config = {
      "outputDir" => File.join(@directory, "invoices"),
      "gstFiling" => { "scheme" => "qrmp", "iff" => "enabled" }
    }
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_tracks_normal_and_effective_gst_by_month
    month = GstInputTracker.add(
      @config, "October 2026", label: "Hosting", date: "2026-10-04",
      gst_amount: "18.00", total_amount: "118.00"
    )
    assert_equal 1, month.fetch("invoiceCount")
    assert_equal 18.0, month.fetch("normalGst")
    assert_equal 0.0, month.fetch("effectiveGst")
    assert_equal 0, month.fetch("foundCount")
    assert_equal 1, month.fetch("missingCount")

    month = GstInputTracker.add(
      @config, "October 2026", label: "Telephone", date: "2026-10-11",
      gst_amount: "9.00", total_amount: "59.00", status: "found"
    )
    assert_equal 2, month.fetch("invoiceCount")
    assert_equal 27.0, month.fetch("normalGst")
    assert_equal 9.0, month.fetch("effectiveGst")
    assert_equal 1, month.fetch("foundCount")
    assert_equal 1, month.fetch("missingCount")
  end

  def test_updates_status_and_deletes_bill
    month = GstInputTracker.add(
      @config, "October 2026", label: "Software", date: "2026-10-08",
      gst_amount: "180", total_amount: "1180"
    )
    bill = month.fetch("bills").first
    updated = GstInputTracker.update(
      @config, "October 2026", bill.fetch("id"), label: "Software subscription",
      date: "2026-10-08", gst_amount: "180", total_amount: "1180", status: "found"
    )
    assert_equal "found", updated.fetch("bills").first.fetch("status")
    assert_equal 180.0, updated.fetch("effectiveGst")

    deleted = GstInputTracker.delete(@config, "October 2026", bill.fetch("id"))
    assert_empty deleted.fetch("bills")
    assert_equal 0, deleted.fetch("invoiceCount")
  end

  def test_carries_missing_bill_forward_and_applies_credit_only_when_found
    october = GstInputTracker.add(
      @config, "October 2026", label: "Software", date: "2026-10-08",
      gst_amount: "180", total_amount: "1180"
    )
    bill = october.fetch("bills").first

    november = GstInputTracker.month(@config, "November 2026")
    assert_equal 0, november.fetch("invoiceCount")
    assert_equal 1, november.fetch("pendingCount")
    assert_equal 0.0, november.fetch("effectiveGst")
    assert november.fetch("bills").first.fetch("carriedForward")

    january = GstInputTracker.update(
      @config, "January 2027", bill.fetch("id"), label: "Software",
      date: "2026-10-08", gst_amount: "180", total_amount: "1180",
      status: "found", found_month: "January 2027"
    )
    assert_equal 0, january.fetch("invoiceCount")
    assert_equal 1, january.fetch("carriedInCount")
    assert_equal 0, january.fetch("pendingCount")
    assert_equal 180.0, january.fetch("effectiveGst")
    assert_equal "January 2027", january.fetch("bills").first.fetch("foundInMonth")

    october = GstInputTracker.month(@config, "October 2026")
    assert_equal 180.0, october.fetch("normalGst")
    assert_equal 0.0, october.fetch("effectiveGst")
    assert_equal 1, october.fetch("resolvedLaterCount")
    assert_equal 0, october.fetch("missingCount")

    dashboard = GstFiling.dashboard(@config, now: Time.local(2027, 1, 10, 9))
    december = dashboard.fetch("periods").find { |period| period.fetch("month") == "December 2026" }
    old_input = december.fetch("checklist").find { |item| item.fetch("id") == "input" }
    assert_equal 0.0, old_input.fetch("effectiveInputGst")
    assert_equal 1, old_input.fetch("resolvedLaterCount")
    january_period = dashboard.fetch("periods").find { |period| period.fetch("month") == "January 2027" }
    new_input = january_period.fetch("checklist").find { |item| item.fetch("id") == "input" }
    assert_equal 180.0, new_input.fetch("effectiveInputGst")
    assert_equal 1, new_input.fetch("carriedInCount")
  end

  def test_validates_bill_month_and_amounts
    assert_raises(GstInputTracker::ConfigError) do
      GstInputTracker.add(
        @config, "October 2026", label: "Wrong month", date: "2026-11-01",
        gst_amount: "18", total_amount: "118"
      )
    end
    assert_raises(GstInputTracker::ConfigError) do
      GstInputTracker.add(
        @config, "October 2026", label: "Reported too early", date: "2026-10-01",
        gst_amount: "18", total_amount: "118", status: "found", found_month: "September 2026"
      )
    end
    assert_raises(GstInputTracker::ConfigError) do
      GstInputTracker.add(
        @config, "October 2026", label: "Bad GST", date: "2026-10-01",
        gst_amount: "119", total_amount: "118"
      )
    end
  end

  def test_accepts_grouped_and_currency_prefixed_monetary_input
    month = GstInputTracker.add(
      @config, "October 2026", label: "Equipment", date: "2026-10-12",
      gst_amount: "15,990.00", total_amount: "₹ 1,15,990.00"
    )
    bill = month.fetch("bills").first
    assert_equal "15990.00", bill.fetch("gstAmount")
    assert_equal "115990.00", bill.fetch("totalAmount")
    assert_equal 15_990.0, month.fetch("normalGst")
  end

  def test_dashboard_contains_monthly_input_summaries
    GstInputTracker.add(
      @config, "October 2026", label: "Hosting", date: "2026-10-04",
      gst_amount: "18", total_amount: "118", status: "found"
    )
    dashboard = GstFiling.dashboard(@config, now: Time.local(2026, 10, 29, 9))
    october = dashboard.fetch("inputMonths").find { |month| month.fetch("month") == "October 2026" }
    assert_equal 18.0, october.fetch("normalGst")
    assert_equal 18.0, october.fetch("effectiveGst")
    assert_equal 1, october.fetch("foundCount")
  end

  def test_time_log_cli_manages_bills_without_invoice_rendering
    config_path = File.join(@directory, "project.json")
    InvoiceStore.write_json(config_path, @config)
    registry_path = File.join(@directory, "registry.json")
    InvoiceStore.write_json(registry_path, {
      "projects" => [{ "label" => "TEST", "configPath" => config_path, "active" => true }]
    })
    environment = {
      "INVOICE_AUTOMATION_CONFIG" => registry_path,
      "INVOICE_AUTOMATION_DATA_DIR" => File.join(@directory, "app-data"),
      "INVOICE_AUTOMATION_CACHE_DIR" => File.join(@directory, "cache"),
      "INVOICE_AUTOMATION_LOG_DIR" => File.join(@directory, "logs"),
      "INVOICE_AUTOMATION_ERROR_LOG" => File.join(@directory, "logs", "error.log")
    }
    cli = File.expand_path("../src/time_log.rb", __dir__)

    stdout, stderr, status = Open3.capture3(
      environment, RbConfig.ruby, cli, "add-gst-bill", "October 2026",
      "Cloud hosting", "2026-10-04", "18", "118"
    )
    assert status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal 1, result.fetch("missingCount")
    id = result.fetch("bills").first.fetch("id")

    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, cli, "gst-bills", "October 2026")
    assert status.success?, stderr
    assert_equal "Cloud hosting", JSON.parse(stdout).fetch("bills").first.fetch("label")

    stdout, stderr, status = Open3.capture3(
      environment, RbConfig.ruby, cli, "update-gst-bill", "January 2027", id,
      "Cloud hosting", "2026-10-04", "18", "118", "found", "January 2027"
    )
    assert status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal 18.0, result.fetch("effectiveGst")
    assert_equal 1, result.fetch("carriedInCount")
  end
end
