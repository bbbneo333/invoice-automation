require "minitest/autorun"
require "tmpdir"
require "open3"
require "rbconfig"
require_relative "../src/generate_gstr1"

class Gstr1GenerationTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("gstr1-test-")
    @config = {
      "outputDir" => File.join(@directory, "invoices"),
      "taxProfile" => {
        "type" => "gst",
        "enabled" => true,
        "effectiveFrom" => "2026-01-01",
        "gstSacCode" => "998314",
        "gstSacDescription" => "Information technology consulting services",
        "gstUqc" => "NA",
        "gstRatePercent" => 18,
        "amountsIncludeTax" => false,
        "gstReverseCharge" => false,
        "gstDefaultTreatment" => "interState"
      }
    }
    @snapshot = {
      "version" => 1,
      "invoiceNo" => "001",
      "invoiceDate" => "2026-09-01",
      "supplier" => { "gst" => { "gstin" => "08AAAAA0000A1Z5", "stateCode" => "08" } },
      "customer" => { "gst" => { "gstin" => "29BBBBB0000B1Z4", "stateCode" => "29" } },
      "service" => { "hours" => "158.555", "sacCode" => "998314" },
      "gst" => {
        "enabled" => true,
        "treatment" => "interState",
        "placeOfSupply" => "29",
        "reverseCharge" => false,
        "ratePercent" => "18.0",
        "taxes" => [{ "name" => "IGST", "ratePercent" => "18.0", "amount" => "65141.80" }]
      },
      "reimbursements" => [],
      "totals" => { "taxableValue" => "361898.89", "grandTotal" => "427040.69" }
    }
    @store = InvoiceStore.new(@config)
    record = @store.find_or_create("August 2026")
    InvoiceStore.write_json(
      File.join(@store.directory(record), "invoice.json"),
      record.reject { |key, _| key == "reimbursements" }.merge("snapshot" => @snapshot)
    )
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_builds_current_gstn_b2b_hsn_and_documents_shapes
    payload = Gstr1Generator.build_payload(@config, @snapshot)

    assert_equal %w[gstin fp version hash b2b hsn doc_issue], payload.keys
    assert_equal "08AAAAA0000A1Z5", payload["gstin"]
    assert_equal "092026", payload["fp"]
    assert_equal "GST3.2.4", payload["version"]
    assert_equal "hash", payload["hash"]

    b2b = payload.fetch("b2b").first
    assert_equal "29BBBBB0000B1Z4", b2b["ctin"]
    invoice = b2b.fetch("inv").first
    assert_equal({
      "inum" => "001", "idt" => "01-09-2026", "val" => 427040.69,
      "pos" => "29", "rchrg" => "N", "inv_typ" => "R",
      "itms" => [{ "num" => 1, "itm_det" => { "rt" => 18, "txval" => 361898.89, "iamt" => 65141.8 } }]
    }, invoice)

    assert_equal({
      "num" => 1, "hsn_sc" => "998314", "uqc" => "NA", "qty" => 0,
      "txval" => 361898.89, "rt" => 18, "iamt" => 65141.8
    }, payload.dig("hsn", "hsn_b2b", 0))
    assert_equal({
      "doc_num" => 1,
      "docs" => [{ "num" => 1, "from" => "001", "to" => "001", "totnum" => 1, "cancel" => 0, "net_issue" => 1 }]
    }, payload.dig("doc_issue", "doc_det", 0))
  end

  def test_maps_intra_state_tax_amounts
    snapshot = Marshal.load(Marshal.dump(@snapshot))
    snapshot["gst"].merge!(
      "treatment" => "intraState",
      "placeOfSupply" => "08",
      "taxes" => [
        { "name" => "CGST", "amount" => "32570.90" },
        { "name" => "SGST", "amount" => "32570.90" }
      ]
    )
    details = Gstr1Generator.build_payload(@config, snapshot).dig("b2b", 0, "inv", 0, "itms", 0, "itm_det")
    assert_equal 32570.9, details["camt"]
    assert_equal 32570.9, details["samt"]
    refute details.key?("iamt")
  end

  def test_period_end_invoice_date_uses_service_month_as_filing_period
    snapshot = Marshal.load(Marshal.dump(@snapshot))
    snapshot["invoiceDate"] = "2026-08-31"
    payload = Gstr1Generator.build_payload(@config, snapshot)
    assert_equal "082026", payload["fp"]
    assert_equal "31-08-2026", payload.dig("b2b", 0, "inv", 0, "idt")
  end

  def test_writes_json_beside_the_matching_invoice
    path = Gstr1Generator.generate("September 2026", config: @config)
    assert_equal File.join(@store.directory(@store.find("August 2026")), "001 GSTR-1 - September 2026.json"), path
    payload = JSON.parse(File.read(path))
    assert_equal "092026", payload["fp"]
    assert_equal Gstr1Generator.build_payload(@config, @snapshot), payload
  end

  def test_requires_uqc_and_rejects_unsupported_input
    @config.fetch("taxProfile").delete("gstUqc")
    error = assert_raises(Gstr1Generator::ConfigError) do
      Gstr1Generator.build_payload(@config, @snapshot)
    end
    assert_includes error.message, "taxProfile.gstUqc"

    @config.fetch("taxProfile")["gstUqc"] = "NA"
    @snapshot["reimbursements"] = [{ "name" => "Travel", "amount" => "100" }]
    error = assert_raises(Gstr1Generator::ConfigError) do
      Gstr1Generator.build_payload(@config, @snapshot)
    end
    assert_includes error.message, "reimbursements"
  end

  def test_requires_na_uqc_for_service_sac_codes
    @config.fetch("taxProfile")["gstUqc"] = "OTH"
    error = assert_raises(Gstr1Generator::ConfigError) do
      Gstr1Generator.build_payload(@config, @snapshot)
    end
    assert_includes error.message, 'must be "NA" for service SAC codes'
  end

  def test_requires_a_generated_invoice_dated_in_the_selected_filing_period
    error = assert_raises(Gstr1Generator::ConfigError) do
      Gstr1Generator.generate("October 2026", config: @config)
    end
    assert_includes error.message, "No generated invoice is dated in October 2026"
  end

  def test_time_log_command_returns_status_and_invoice_folder
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
    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, cli, "generate-gst", "September 2026")
    assert status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal "September 2026", result["month"]
    assert_equal @store.directory(@store.find("August 2026")), result["outputDir"]
    assert File.file?(File.join(result["outputDir"], "001 GSTR-1 - September 2026.json"))
  end
end

class QrmpGenerationTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("qrmp-test-")
    @config = {
      "outputDir" => File.join(@directory, "invoices"),
      "gstFiling" => { "scheme" => "qrmp", "iff" => "enabled" },
      "taxProfile" => {
        "type" => "gst", "enabled" => true, "effectiveFrom" => "2026-01-01",
        "gstSacCode" => "998314", "gstUqc" => "NA", "gstRatePercent" => 18,
        "amountsIncludeTax" => false, "gstReverseCharge" => false,
        "gstDefaultTreatment" => "interState"
      }
    }
    @store = InvoiceStore.new(@config)
    add_invoice("October 2026", "2026-10-31")
    add_invoice("November 2026", "2026-11-30")
    add_invoice("December 2026", "2026-12-31")
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def add_invoice(month, date)
    record = @store.find_or_create(month)
    snapshot = {
      "version" => 1,
      "invoiceNo" => record.fetch("invoiceNo"),
      "invoiceDate" => date,
      "supplier" => { "gst" => { "gstin" => "08AAAAA0000A1Z5", "stateCode" => "08" } },
      "customer" => { "gst" => { "gstin" => "29BBBBB0000B1Z4", "stateCode" => "29" } },
      "service" => { "hours" => "158.555", "sacCode" => "998314" },
      "gst" => {
        "enabled" => true, "treatment" => "interState", "placeOfSupply" => "29",
        "reverseCharge" => false, "ratePercent" => "18.0",
        "taxes" => [{ "name" => "IGST", "ratePercent" => "18.0", "amount" => "65141.80" }]
      },
      "reimbursements" => [],
      "totals" => { "taxableValue" => "361898.89", "grandTotal" => "427040.69" }
    }
    InvoiceStore.write_json(
      File.join(@store.directory(record), "invoice.json"),
      record.reject { |key, _| key == "reimbursements" }.merge("snapshot" => snapshot)
    )
  end

  def invoice_numbers(payload)
    payload.fetch("b2b").flat_map { |customer| customer.fetch("inv") }.map { |invoice| invoice.fetch("inum") }
  end

  def test_qrmp_periods_and_configuration
    assert_equal({ "scheme" => "qrmp", "iff" => "enabled" }, GstFiling.settings(@config))
    period = GstFiling.quarter("November 2026")
    assert_equal "October-December 2026", period.fetch("label")
    assert_equal "December 2026", period.fetch("endMonth")
    assert GstFiling.iff_eligible?("October 2026")
    assert GstFiling.iff_eligible?("November 2026")
    refute GstFiling.iff_eligible?("December 2026")
  end

  def test_quarter_preferences_are_effective_dated_and_inherited
    config = Marshal.load(Marshal.dump(@config))
    config["gstFiling"] = { "scheme" => "monthly", "iff" => "disabled" }

    GstFiling.set_preference(config, "October 2026", "qrmp", "enabled", now: Time.utc(2026, 10, 29, 10))
    assert_equal "monthly", GstFiling.settings(config, period: "September 2026").fetch("scheme")
    assert_equal({ "scheme" => "qrmp", "iff" => "enabled" }, GstFiling.settings(config, period: "October 2026"))
    assert_equal({ "scheme" => "qrmp", "iff" => "enabled" }, GstFiling.settings(config, period: "January 2027"))

    GstFiling.set_preference(config, "January 2027", "monthly", "disabled")
    assert_equal "qrmp", GstFiling.settings(config, period: "December 2026").fetch("scheme")
    assert_equal({ "scheme" => "monthly", "iff" => "disabled" }, GstFiling.settings(config, period: "March 2027"))
  end

  def test_quarter_preference_locks_after_gst_generation
    Gstr1Generator.generate_iff("October 2026", config: @config)
    error = assert_raises(GstFiling::ConfigError) do
      GstFiling.set_preference(@config, "October 2026", "monthly", "disabled")
    end
    assert_includes error.message, "filing preference is locked"

    dashboard = GstFiling.dashboard(@config, now: Time.local(2026, 10, 30, 9))
    preference = dashboard.fetch("preferences").find { |item| item.fetch("quarterLabel") == "October-December 2026" }
    assert preference.fetch("locked")
    assert_includes preference.fetch("lockReason"), "generated"
  end

  def test_generates_iff_and_requires_explicit_filed_transition
    path = Gstr1Generator.generate_iff("October 2026", config: @config)
    payload = JSON.parse(File.read(path))
    assert_equal %w[gstin fp version hash b2b], payload.keys
    assert_equal "102026", payload.fetch("fp")
    assert_equal ["001"], invoice_numbers(payload)
    refute payload.key?("hsn")
    refute payload.key?("doc_issue")
    assert_equal "generated", GstFiling.iff_entry(@config, "October 2026").fetch("status")

    entry = GstFiling.mark_iff_filed(@config, "October 2026", now: Time.utc(2026, 11, 5, 10))
    assert_equal "filed", entry.fetch("status")
    assert_equal "2026-11-05T10:00:00Z", entry.fetch("filedAt")
    assert_raises(Gstr1Generator::ConfigError) do
      Gstr1Generator.generate_iff("October 2026", config: @config)
    end
  end

  def test_quarterly_payload_excludes_only_filed_iff_b2b_and_keeps_quarter_summaries
    Gstr1Generator.generate_iff("October 2026", config: @config)
    GstFiling.mark_iff_filed(@config, "October 2026")
    Gstr1Generator.generate_iff("November 2026", config: @config)

    path = Gstr1Generator.generate_quarterly("December 2026", config: @config)
    payload = JSON.parse(File.read(path))
    assert_equal "122026", payload.fetch("fp")
    assert_equal %w[002 003], invoice_numbers(payload)
    assert_equal "1085696.67", format("%.2f", payload.dig("hsn", "hsn_b2b", 0, "txval"))
    assert_equal %w[001 002 003], payload.dig("doc_issue", "doc_det", 0, "docs").map { |document| document.fetch("from") }

    GstFiling.mark_iff_filed(@config, "November 2026")
    assert_nil GstFiling.gstr1_entry(@config, "December 2026"), "filing another IFF invalidates a generated quarterly return"
    path = Gstr1Generator.generate_quarterly("October 2026", config: @config)
    assert_equal ["003"], invoice_numbers(JSON.parse(File.read(path)))
  end

  def test_rejects_iff_for_third_month_and_invalid_configurations
    assert_raises(Gstr1Generator::ConfigError) do
      Gstr1Generator.generate_iff("December 2026", config: @config)
    end
    assert_raises(GstFiling::ConfigError) do
      GstFiling.settings(@config.merge("gstFiling" => { "scheme" => "monthly", "iff" => "enabled" }))
    end
    assert_raises(GstFiling::ConfigError) do
      GstFiling.mark_iff_filed(@config, "October 2026")
    end
  end

  def test_rejects_invoice_changes_after_iff_is_marked_filed
    Gstr1Generator.generate_iff("October 2026", config: @config)
    GstFiling.mark_iff_filed(@config, "October 2026")
    record = @store.find("October 2026")
    path = File.join(@store.directory(record), "invoice.json")
    metadata = JSON.parse(File.read(path))
    metadata.fetch("snapshot").fetch("totals")["grandTotal"] = "1.00"
    InvoiceStore.write_json(path, metadata)

    error = assert_raises(Gstr1Generator::ConfigError) do
      Gstr1Generator.generate_quarterly("December 2026", config: @config)
    end
    assert_includes error.message, "changed after"
  end

  def test_rejects_marking_generated_json_filed_after_invoice_changes
    Gstr1Generator.generate_iff("October 2026", config: @config)
    record = @store.find("October 2026")
    path = File.join(@store.directory(record), "invoice.json")
    metadata = JSON.parse(File.read(path))
    metadata.fetch("snapshot").fetch("totals")["grandTotal"] = "1.00"
    InvoiceStore.write_json(path, metadata)

    error = assert_raises(GstFiling::ConfigError) do
      GstFiling.mark_iff_filed(@config, "October 2026")
    end
    assert_includes error.message, "regenerate it before marking it filed"
  end

  def test_dashboard_exposes_period_actions_amounts_and_filed_lock
    Gstr1Generator.generate_iff("October 2026", config: @config)
    GstFiling.mark_iff_filed(@config, "October 2026", now: Time.utc(2026, 11, 5, 10))

    dashboard = GstFiling.dashboard(@config, now: Time.local(2026, 11, 6, 9))
    assert_equal "qrmp", dashboard.fetch("scheme")
    assert dashboard.fetch("iffEnabled")
    assert_equal "November 2026", dashboard.fetch("defaultPeriod")

    october = dashboard.fetch("periods").find { |period| period.fetch("month") == "October 2026" }
    assert_equal "iff", october.fetch("kind")
    assert_equal "filed", october.fetch("status")
    assert october.fetch("locked")
    refute october.fetch("canGenerate")
    assert_equal 1, october.dig("amounts", "invoiceCount")
    assert_equal 361_898.89, october.dig("amounts", "taxableValue")
    assert_equal 65_141.8, october.dig("amounts", "igst")
    assert_equal 427_040.69, october.dig("amounts", "invoiceValue")
    assert File.file?(october.fetch("outputPath"))

    december = dashboard.fetch("periods").find { |period| period.fetch("month") == "December 2026" }
    assert_equal "quarterlyGstr1", december.fetch("kind")
    assert_equal 3, december.dig("amounts", "invoiceCount")
    assert_equal 1_085_696.67, december.dig("amounts", "taxableValue")
    refute december.fetch("canGenerate"), "quarterly GSTR-1 stays unavailable before its third month"
  end

  def test_dashboard_checklist_uses_action_titles_dynamic_values_due_dates_and_persisted_tasks
    GstInputTracker.add(
      @config, "October 2026", label: "Software", date: "2026-10-12",
      gst_amount: "1,800.00", total_amount: "11,800.00", status: "found"
    )
    GstInputTracker.add(
      @config, "October 2026", label: "Hosting", date: "2026-10-18",
      gst_amount: "900", total_amount: "5,900", status: "missing"
    )

    dashboard = GstFiling.dashboard(@config, now: Time.local(2026, 10, 29, 9))
    october = dashboard.fetch("periods").find { |period| period.fetch("month") == "October 2026" }
    input = october.fetch("checklist").find { |item| item.fetch("id") == "input" }
    assert_equal "Record and monitor October 2026 purchase bills", input.fetch("title")
    assert_equal "attention", input.fetch("status")
    assert_equal 2, input.fetch("invoiceCount")
    assert_equal 1, input.fetch("foundCount")
    assert_equal 1, input.fetch("missingCount")
    assert_equal 2_700.0, input.fetch("gstAmount")
    assert_equal 1_800.0, input.fetch("effectiveInputGst")

    generate = october.fetch("checklist").find { |item| item.fetch("id") == "generate" }
    assert_equal "Generate October 2026 IFF JSON", generate.fetch("title")
    assert_equal "2026-11-13", generate.fetch("dueDate")
    assert_equal 1, generate.fetch("invoiceCount")
    assert_equal 65_141.8, generate.fetch("gstAmount")

    payment_review = october.fetch("checklist").find { |item| item.fetch("id") == "paymentReview" }
    assert_equal "Review October 2026 GST liability and generate the PMT-06 challan on the GST portal", payment_review.fetch("title")
    assert_equal "ready", payment_review.fetch("status")
    payment = october.fetch("checklist").find { |item| item.fetch("id") == "payment" }
    assert_equal "Pay the October 2026 PMT-06 challan on the GST portal", payment.fetch("title")
    assert_equal "2026-11-25", payment.fetch("dueDate")
    assert_equal 63_341.8, payment.fetch("estimatedBalance")
    assert_equal "blocked", payment.fetch("status")

    GstFiling.mark_task_complete(@config, "October 2026", "pmt06_review", now: Time.utc(2026, 11, 19, 10))
    GstFiling.mark_task_complete(@config, "October 2026", "pmt06", now: Time.utc(2026, 11, 20, 10))
    refreshed = GstFiling.dashboard(@config, now: Time.local(2026, 11, 20, 12))
    october = refreshed.fetch("periods").find { |period| period.fetch("month") == "October 2026" }
    payment = october.fetch("checklist").find { |item| item.fetch("id") == "payment" }
    assert_equal "complete", payment.fetch("status")
    assert_equal "2026-11-20T10:00:00Z", payment.fetch("completedAt")
    preference = refreshed.fetch("preferences").find { |item| item.fetch("quarterLabel") == "October-December 2026" }
    assert preference.fetch("locked")
    assert_includes preference.fetch("lockReason"), "checklist action"

    december = dashboard.fetch("periods").find { |period| period.fetch("month") == "December 2026" }
    assert_equal "Record and monitor October-December 2026 purchase bills", december.fetch("checklist").first.fetch("title")
    gstr2b = december.fetch("checklist").find { |item| item.fetch("id") == "gstr2bImport" }
    assert_equal "Import and reconcile October-December 2026 GSTR-2B", gstr2b.fetch("title")
    assert_equal "2027-01-14", gstr2b.fetch("availableDate")
    assert_equal "blocked", gstr2b.fetch("status")
    gstr3b = december.fetch("checklist").find { |item| item.fetch("id") == "gstr3b" }
    assert_equal "2027-01-24", gstr3b.fetch("dueDate")
    assert_equal "blocked", gstr3b.fetch("status")
    assert_equal 6, december.fetch("checklist").length
  end

  def test_checklist_rejects_tasks_that_do_not_apply_to_the_period
    assert_raises(GstFiling::ConfigError) do
      GstFiling.mark_task_complete(@config, "December 2026", "pmt06")
    end
    assert_raises(GstFiling::ConfigError) do
      GstFiling.mark_task_complete(@config, "October 2026", "gstr3b")
    end
    assert_raises(GstFiling::ConfigError) do
      GstFiling.mark_task_complete(@config, "November 2026", "pmt06")
    end
  end

  def test_standard_gstr3b_due_date_uses_supplier_state_group
    karnataka = { "from" => { "gst" => { "stateCode" => "29" } } }
    rajasthan = { "from" => { "gst" => { "stateCode" => "08" } } }
    assert_equal Date.new(2027, 1, 22), GstFiling.gstr3b_due_date(karnataka, "December 2026", [], quarterly: true)
    assert_equal Date.new(2027, 1, 24), GstFiling.gstr3b_due_date(rajasthan, "December 2026", [], quarterly: true)
    assert_equal Date.new(2026, 11, 20), GstFiling.gstr3b_due_date(karnataka, "October 2026", [], quarterly: false)
  end

  def test_quarterly_gstr1_generated_and_filed_state_locks_regeneration_and_invoice
    path = Gstr1Generator.generate_quarterly("December 2026", config: @config)
    entry = GstFiling.gstr1_entry(@config, "December 2026")
    assert_equal "generated", entry.fetch("status")
    assert_equal "quarterly", entry.fetch("kind")
    assert_equal File.basename(path), File.basename(entry.fetch("outputPath"))

    GstFiling.mark_gstr1_filed(@config, "December 2026", now: Time.utc(2027, 1, 10, 12))
    assert GstFiling.gstr1_filed?(@config, "December 2026")
    assert_raises(Gstr1Generator::ConfigError) do
      Gstr1Generator.generate_quarterly("December 2026", config: @config)
    end
    error = assert_raises(GstFiling::ConfigError) do
      GstFiling.assert_invoice_editable!(@config, @store.find("October 2026").fetch("snapshot"))
    end
    assert_includes error.message, "GSTR-1 is filed"
  end

  def test_time_log_qrmp_commands_generate_mark_and_aggregate_without_rendering
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

    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, cli, "generate-iff", "October 2026")
    assert status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal "generated", result.fetch("gstIffPeriods").first.fetch("status")

    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, cli, "mark-iff-filed", "October 2026")
    assert status.success?, stderr
    result = JSON.parse(stdout)
    assert_equal "filed", result.fetch("gstIffPeriods").first.fetch("status")

    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, cli, "mark-pmt06-reviewed", "October 2026")
    assert status.success?, stderr
    assert GstFiling.task_complete?(GstFiling.read_state(@config), "October 2026", "pmt06_review")

    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, cli, "mark-pmt06-paid", "October 2026")
    assert status.success?, stderr
    assert GstFiling.task_complete?(GstFiling.read_state(@config), "October 2026", "pmt06")

    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, cli, "generate-gst", "December 2026")
    assert status.success?, stderr
    result = JSON.parse(stdout)
    payload = JSON.parse(File.read(result.fetch("generation").fetch("output")))
    assert_equal %w[002 003], invoice_numbers(payload)

    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, cli, "gst-dashboard")
    assert status.success?, stderr
    dashboard = JSON.parse(stdout)
    assert_equal "qrmp", dashboard.fetch("scheme")
    assert_equal "filed", dashboard.fetch("periods").find { |period| period.fetch("month") == "October 2026" }.fetch("status")

    stdout, stderr, status = Open3.capture3(
      environment, RbConfig.ruby, cli, "set-gst-preference", "January 2027", "monthly", "disabled"
    )
    assert status.success?, stderr
    assert_equal "monthly", GstFiling.settings(@config, period: "January 2027").fetch("scheme")

    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, cli, "mark-gstr1-filed", "December 2026")
    assert status.success?, stderr
    assert_equal "filed", GstFiling.gstr1_entry(@config, "December 2026").fetch("status")

    gstr2b_path = File.join(@directory, "gstr2b.json")
    InvoiceStore.write_json(gstr2b_path, {
      "data" => {
        "gstin" => "08AAAAA0000A1Z5", "fp" => "122026",
        "docdata" => {
          "b2b" => [{
            "ctin" => "29SUPPLIER0001Z1", "trdnm" => "Supplier",
            "inv" => [{
              "inum" => "PUR-1", "dt" => "15-12-2026", "val" => 118,
              "itcavl" => "Y", "items" => [{ "txval" => 100, "igst" => 18 }]
            }]
          }]
        }
      }
    })
    stdout, stderr, status = Open3.capture3(
      environment, RbConfig.ruby, cli, "import-gstr2b", "December 2026", gstr2b_path
    )
    assert status.success?, stderr
    assert_equal 1, JSON.parse(stdout).dig("summary", "portalInvoiceCount")

    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, cli, "gstr2b-import", "December 2026")
    assert status.success?, stderr
    assert_equal "December 2026", JSON.parse(stdout).fetch("period")

    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, cli, "mark-gstr3b-reviewed", "December 2026")
    assert status.success?, stderr
    assert GstFiling.task_complete?(GstFiling.read_state(@config), "December 2026", "gstr3b_review")

    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, cli, "mark-gstr3b-filed", "December 2026")
    assert status.success?, stderr
    assert GstFiling.task_complete?(GstFiling.read_state(@config), "December 2026", "gstr3b")
  end
end
