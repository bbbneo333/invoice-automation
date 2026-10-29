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
