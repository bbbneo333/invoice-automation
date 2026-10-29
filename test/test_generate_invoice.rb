require "minitest/autorun"
require "json"
require_relative "../src/generate_invoice"
require_relative "../src/time_log"

class InvoiceGenerationTest < Minitest::Test
  FIXTURES = File.join(__dir__, "fixtures")

  def cases
    JSON.parse(File.read(File.join(FIXTURES, "invoice_cases.json")))
  end

  def sample
    cases.first
  end

  def normalize(value)
    case value
    when BigDecimal then InvoiceGenerator.quantity_format(value)
    when Hash then value.transform_values { |item| normalize(item) }
    when Array then value.map { |item| normalize(item) }
    else value
    end
  end

  def test_calculations_and_display_context_match_python_baselines
    cases.each do |item|
      config, record = item.values_at("config", "record")
      start, finish, invoice_date = InvoiceCalculation.parse_month(record.fetch("month"))
      calc = InvoiceGenerator.calculate_invoice(config, record, start)
      assert_equal item.fetch("calculation"), normalize(calc), item.fetch("name")
      assert_equal item.fetch("context"), InvoiceGenerator.build_template_context(config, record, start, finish, invoice_date, calc), item.fetch("name")
      # Config sync/reimbursement updates and the PDF must use the same total.
      assert_equal calc.fetch("grandTotal"), TimeLog.calculated_invoice_amount(config, record, record.fetch("month"), record.fetch("hours")), item.fetch("name")
    end
  end

  def test_money_uses_decimal_half_up_rounding
    assert_equal BigDecimal("1.01"), InvoiceCalculation.money("1.005")
    assert_equal BigDecimal("-1.01"), InvoiceCalculation.money("-1.005")
    assert_equal "160", InvoiceGenerator.quantity_format(160)
    assert_equal "158.5", InvoiceGenerator.quantity_format(158.5)
    assert_equal "4,29,520.00", DocumentLocale.money(429520)
    assert_equal "-1,234.57", DocumentLocale.money("-1234.565")
    assert_equal "12,34,56,78,90,12,345.68", DocumentLocale.money("123456789012345.675")
  end

  def test_explicit_gst_schema_matches_all_existing_invoice_cases
    cases.each do |item|
      config, record = item.values_at("config", "record")
      config["taxProfile"] = InvoiceCalculation.tax_profile(config)
      assert_equal "gst", config["taxProfile"]["type"]
      assert config["taxProfile"].key?("gstSacCode")
      refute config["taxProfile"].key?("sacCode")
      start, finish, invoice_date = InvoiceCalculation.parse_month(record["month"])
      calc = InvoiceGenerator.calculate_invoice(config, record, start)
      assert_equal item["calculation"], normalize(calc), item["name"]
      assert_equal item["context"], InvoiceGenerator.build_template_context(config, record, start, finish, invoice_date, calc), item["name"]
      assert_equal calc["grandTotal"], TimeLog.calculated_invoice_amount(config, record, record["month"], record["hours"])
    end
  end

  def test_only_gst_type_is_supported_even_when_disabled
    ["vat", "GST", "", nil, false].each do |type|
      [true, false].each do |enabled|
        error = assert_raises(InvoiceCalculation::ConfigError) do
          InvoiceCalculation.gst_applies({ "taxProfile" => { "type" => type, "enabled" => enabled } }, Date.new(2026, 8, 1))
        end
        assert_includes error.message, "taxProfile.type must be gst"
      end
    end
  end

  def test_legacy_aliases_are_non_mutating_and_conflicts_are_rejected
    config = sample.fetch("config")
    original = Marshal.load(Marshal.dump(config))
    normalized = InvoiceCalculation.tax_profile(config)
    assert_equal original, config
    InvoiceCalculation::GST_FIELD_ALIASES.each do |legacy, canonical|
      assert_equal config["taxProfile"][legacy], normalized[canonical]
      mixed = Marshal.load(Marshal.dump(config))
      mixed["taxProfile"][canonical] = mixed["taxProfile"][legacy]
      assert_equal normalized, InvoiceCalculation.tax_profile(mixed)
      mixed["taxProfile"][canonical] = "conflicting value"
      error = assert_raises(InvoiceCalculation::ConfigError) { InvoiceCalculation.tax_profile(mixed) }
      assert_includes error.message, canonical
    end
  end

  def test_non_numeric_and_non_finite_values_are_rejected
    [true, false, nil, "NaN", "Infinity", "-Infinity", "bad"].each do |value|
      assert_raises(InvoiceCalculation::ConfigError) { InvoiceCalculation.money(value) }
    end
  end

  def test_invalid_rates_and_hours_are_rejected
    [["hours", -1], ["rateUsd", 0], ["exchRate", -1]].each do |key, value|
      config, record = sample.values_at("config", "record")
      (key == "hours" ? record : config)[key] = value
      assert_raises(InvoiceCalculation::ConfigError) { InvoiceGenerator.calculate_invoice(config, record, Date.new(2026, 8, 1)) }
    end
  end

  def test_recorded_amount_mismatch_fails_document_generation
    config, record = sample.values_at("config", "record")
    record["amount"] = 0
    error = assert_raises(InvoiceCalculation::ConfigError) { InvoiceGenerator.calculate_invoice(config, record, Date.new(2026, 8, 1)) }
    assert_includes error.message, "deterministic total"
    assert InvoiceCalculation.calculate(config, record, Date.new(2026, 8, 1))["grandTotal"].positive?
  end

  def test_both_state_treatment_mismatches_are_rejected
    %w[intraState interState].each do |treatment|
      config, record = sample.values_at("config", "record")
      config["taxProfile"]["defaultTreatment"] = treatment
      if treatment == "intraState"
        config["client"]["gst"].merge!("gstin" => "29BBBBB0000B1Z4", "stateCode" => "29")
      end
      assert_raises(InvoiceCalculation::ConfigError) { InvoiceGenerator.calculate_invoice(config, record, Date.new(2026, 8, 1)) }
      assert_raises(InvoiceCalculation::ConfigError) { TimeLog.calculated_invoice_amount(config, record, "August 2026", record["hours"]) }
    end
  end

  def test_document_validation_is_preserved
    changes = [
      ->(config) { config["taxProfile"]["sacCode"] = "bad" },
      ->(config) { config["from"]["gst"]["gstin"] = "short" },
      ->(config) { config["from"].delete("address") },
      ->(config) { config["taxProfile"]["ratePercent"] = 101 },
      ->(config) { config["taxProfile"]["reverseCharge"] = "false" },
      ->(config) { config["taxProfile"]["amountsIncludeTax"] = true },
      ->(config) { config["taxProfile"]["defaultTreatment"] = "unsupported" },
      ->(config) { config["taxProfile"]["effectiveFrom"] = "2026-02-30" }
    ]
    changes.each do |change|
      config, record = sample.values_at("config", "record")
      change.call(config)
      assert_raises(InvoiceCalculation::ConfigError) { InvoiceGenerator.calculate_invoice(config, record, Date.new(2026, 8, 1)) }
    end
  end

  def test_month_boundaries
    assert_equal [Date.new(2024, 2, 1), Date.new(2024, 2, 29), Date.new(2024, 3, 1)], InvoiceCalculation.parse_month("February 2024")
    assert_equal Date.new(2027, 1, 1), InvoiceCalculation.parse_month("December 2026").last
    ["Bad 2026", "August", "August 2026 extra", "August 0"].each do |month|
      assert_raises(InvoiceCalculation::ConfigError) { InvoiceCalculation.parse_month(month) }
    end
  end

  def test_invoice_date_timing_defaults_to_first_of_following_month
    _, period_end = InvoiceCalculation.parse_month("February 2024")
    assert_equal Date.new(2024, 3, 1), InvoiceCalculation.invoice_date({}, period_end)
    assert_equal Date.new(2024, 3, 1), InvoiceCalculation.invoice_date({ "invoiceDateTiming" => "firstOfFollowingMonth" }, period_end)
  end

  def test_invoice_date_can_use_last_day_of_service_month
    _, leap_year_end = InvoiceCalculation.parse_month("February 2024")
    _, year_end = InvoiceCalculation.parse_month("December 2026")
    config = { "invoiceDateTiming" => "lastOfServiceMonth" }
    assert_equal Date.new(2024, 2, 29), InvoiceCalculation.invoice_date(config, leap_year_end)
    assert_equal Date.new(2026, 12, 31), InvoiceCalculation.invoice_date(config, year_end)
  end

  def test_invalid_invoice_date_timing_is_rejected
    _, period_end = InvoiceCalculation.parse_month("August 2026")
    [nil, true, "", "lastDay"].each do |timing|
      error = assert_raises(InvoiceCalculation::ConfigError) do
        InvoiceCalculation.invoice_date({ "invoiceDateTiming" => timing }, period_end)
      end
      assert_includes error.message, "invoiceDateTiming"
    end
  end

  def test_sac_description_is_optional_and_does_not_change_totals
    [:missing, nil, "", "   ", "  Custom service description  "].each do |description|
      config, record = sample.values_at("config", "record")
      tax = config.fetch("taxProfile")
      description == :missing ? tax.delete("sacDescription") : tax["sacDescription"] = description
      start, finish, next_month = InvoiceCalculation.parse_month(record.fetch("month"))
      calc = InvoiceGenerator.calculate_invoice(config, record, start)
      assert_equal BigDecimal(record.fetch("amount")), calc.fetch("grandTotal")
      context = InvoiceGenerator.build_template_context(config, record, start, finish, next_month, calc)
      assert_equal "998314", context.fetch("items").first.fetch("sacCode")
      expected_description = description.is_a?(String) ? description.strip : nil
      actual_description = context.fetch("items").first.fetch("sacDescription")
      expected_description.nil? ? assert_nil(actual_description) : assert_equal(expected_description, actual_description)
    end
  end

  def test_gst_invoice_still_requires_sac_code_and_valid_description_type
    [->(tax) { tax.delete("sacCode") }, ->(tax) { tax["sacCode"] = "" }, ->(tax) { tax["sacDescription"] = 123 }].each do |change|
      config, record = sample.values_at("config", "record")
      change.call(config.fetch("taxProfile"))
      assert_raises(InvoiceCalculation::ConfigError) do
        InvoiceGenerator.calculate_invoice(config, record, Date.new(2026, 8, 1))
      end
    end
  end

  def test_non_gst_invoice_needs_no_sac_or_party_gst_fields
    [nil, { "enabled" => false }, { "enabled" => true, "effectiveFrom" => "2026-09-01" }].each do |profile|
      config, record = sample.values_at("config", "record")
      config["taxProfile"] = profile
      config["from"].delete("gst")
      config["client"].delete("gst")
      start, finish, next_month = InvoiceCalculation.parse_month(record.fetch("month"))
      total = InvoiceCalculation.calculate(config, record, start).fetch("grandTotal")
      record["amount"] = total.to_s("F")
      calc = InvoiceGenerator.calculate_invoice(config, record, start)
      refute calc.fetch("taxEnabled")
      assert_empty calc.fetch("taxes")
      context = InvoiceGenerator.build_template_context(config, record, start, finish, next_month, calc)
      assert_nil context.fetch("items").first.fetch("sacCode")
      assert_nil context.fetch("items").first.fetch("sacDescription")
    end
  end

  def test_invoice_template_renders_optional_sac_description
    contexts = [nil, "", "Design & <support>"].map do |description|
      context = sample.fetch("context")
      context.fetch("items").first["sacDescription"] = description
      context
    end
    script = <<~JS
      const fs = require("node:fs");
      const nunjucks = require("nunjucks");
      const env = nunjucks.configure("templates", { autoescape: true, throwOnUndefined: true });
      const contexts = JSON.parse(fs.readFileSync(0, "utf8"));
      process.stdout.write(JSON.stringify(contexts.map(context => env.render("invoice.html", context))));
    JS
    output, error, status = Open3.capture3(InvoiceGenerator.find_node, "-e", script, stdin_data: JSON.generate(contexts), chdir: File.expand_path("..", __dir__))
    assert status.success?, error
    rendered = JSON.parse(output)
    rendered.first(2).each do |html|
      assert_includes html, "<strong>SAC:</strong> 998314</div>"
      refute_includes html, "998314 -"
    end
    assert_includes rendered.last, "<strong>SAC:</strong> 998314 - Design &amp; &lt;support&gt;</div>"
  end
end
