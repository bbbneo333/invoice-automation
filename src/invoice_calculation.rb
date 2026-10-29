require "bigdecimal"
require "date"

# Shared by the timer/config sync and the invoice document generator.
module InvoiceCalculation
  class ConfigError < ArgumentError; end

  MONTHS = %w[January February March April May June July August September October November December].freeze
  INVOICE_DATE_TIMINGS = %w[firstOfFollowingMonth lastOfServiceMonth].freeze
  DEFAULT_INVOICE_DATE_TIMING = "firstOfFollowingMonth"
  TREATMENTS = %w[intraState interState exportWithPayment exportWithoutPayment exempt].freeze
  REIMBURSEMENT_TREATMENTS = %w[includedInTaxableValue excludedFromTaxableValue].freeze
  GST_FIELD_ALIASES = {
    "defaultTreatment" => "gstDefaultTreatment",
    "sacCode" => "gstSacCode",
    "sacDescription" => "gstSacDescription",
    "ratePercent" => "gstRatePercent",
    "reverseCharge" => "gstReverseCharge"
  }.freeze

  module_function

  def field(mapping, path, type = nil, allow_empty: false)
    value = path.split(".").inject(mapping) do |current, part|
      raise ConfigError, "Missing required config field: #{path}" unless current.is_a?(Hash) && current.key?(part)
      current[part]
    end
    raise ConfigError, "#{path} must be #{type}" if type && !value.is_a?(type)
    raise ConfigError, "#{path} must not be empty" if !allow_empty && value.is_a?(String) && value.strip.empty?
    value
  end

  def decimal_value(value, path)
    result = BigDecimal(value.to_s)
    raise ConfigError, "#{path} must be finite" unless result.finite?
    result
  rescue ArgumentError => error
    raise error if error.is_a?(ConfigError)
    raise ConfigError, "#{path} must be a number"
  end

  def parse_monetary_input(value, path = "amount")
    return decimal_value(value, path) unless value.is_a?(String)

    text = value.strip
    text = text.sub(/\A([+-]?)\s*(?:₹|INR)\s*/i, '\\1')
    plain = /\A[+-]?\d+(?:\.\d+)?\z/
    international = /\A[+-]?\d{1,3}(?:,\d{3})+(?:\.\d+)?\z/
    indian = /\A[+-]?\d{1,2}(?:,\d{2})*,\d{3}(?:\.\d+)?\z/
    raise ConfigError, "#{path} must be a number" unless [plain, international, indian].any? { |pattern| text.match?(pattern) }

    decimal_value(text.delete(","), path)
  end

  def format_monetary_value(value, path = "amount")
    format("%.2f", parse_monetary_input(value, path).round(2, :half_up))
  end

  def money(value)
    parse_monetary_input(value, "amount").round(2, :half_up)
  end

  def parse_month(month_label)
    name, year, extra = month_label.to_s.split
    month = MONTHS.index(name)
    raise ConfigError, "Invalid invoice month: #{month_label.inspect}" if !month || !year || extra || !year.match?(/\A\d+\z/)
    start = Date.new(Integer(year, 10), month + 1, 1)
    raise ConfigError, "Invalid invoice month: #{month_label.inspect}" unless (1..9999).cover?(start.year)
    next_month = start >> 1
    [start, next_month - 1, next_month]
  rescue ArgumentError
    raise ConfigError, "Invalid invoice month: #{month_label.inspect}"
  end

  def invoice_date(config, period_end)
    timing = config.fetch("invoiceDateTiming", DEFAULT_INVOICE_DATE_TIMING)
    unless timing.is_a?(String) && INVOICE_DATE_TIMINGS.include?(timing)
      raise ConfigError, "invoiceDateTiming must be firstOfFollowingMonth or lastOfServiceMonth"
    end

    timing == "lastOfServiceMonth" ? period_end : period_end + 1
  end

  def tax_profile(config)
    tax = config["taxProfile"]
    return nil if tax.nil?
    raise ConfigError, "taxProfile must be an object" unless tax.is_a?(Hash)
    type = tax.fetch("type", "gst")
    raise ConfigError, "taxProfile.type must be gst; other tax types are not supported" unless type == "gst"
    normalized = tax.merge("type" => type)
    GST_FIELD_ALIASES.each do |legacy, canonical|
      if tax.key?(legacy) && tax.key?(canonical) && tax[legacy] != tax[canonical]
        raise ConfigError, "Conflicting taxProfile.#{legacy} and taxProfile.#{canonical}; use #{canonical}"
      end
      normalized[canonical] = tax[legacy] if tax.key?(legacy) && !tax.key?(canonical)
      normalized.delete(legacy)
    end
    normalized
  end

  def gst_applies(config, period_start)
    tax = tax_profile(config)
    return false if tax.nil?
    return false if tax["enabled"] == false
    raise ConfigError, "taxProfile.enabled must be true or false" unless tax["enabled"] == true
    effective_text = field(tax, "effectiveFrom", String)
    raise ConfigError, "taxProfile.effectiveFrom must use YYYY-MM-DD" unless effective_text.match?(/\A\d{4}-\d{2}-\d{2}\z/)
    period_start >= Date.iso8601(effective_text)
  rescue ArgumentError => error
    raise error if error.is_a?(ConfigError)
    raise ConfigError, "taxProfile.effectiveFrom must use YYYY-MM-DD"
  end

  def validate_party(config, key, gst_required)
    field(config, "#{key}.name", String)
    field(config, "#{key}.address", String)
    field(config, "#{key}.email", String, allow_empty: true)
    field(config, "#{key}.phone", String, allow_empty: true)
    return unless gst_required

    gstin = field(config, "#{key}.gst.gstin", String).upcase
    state_code = field(config, "#{key}.gst.stateCode", String)
    field(config, "#{key}.gst.state", String)
    raise ConfigError, "#{key}.gst.gstin must contain 15 characters" unless gstin.length == 15
    raise ConfigError, "#{key}.gst.stateCode must contain two digits" unless state_code.match?(/\A[0-9]{2}\z/)
    raise ConfigError, "#{key}.gst.gstin prefix must match #{key}.gst.stateCode" unless gstin[0, 2] == state_code
  end

  # Config updates calculate totals before an invoice is ready to render. Party
  # presentation fields and the recorded-total check belong to document validation.
  def calculate(config, record, period_start, validate_document: false, check_amount: false)
    hours = decimal_value(field(record, "hours"), "invoice.hours")
    rate_usd = decimal_value(field(config, "rateUsd"), "rateUsd")
    exchange_rate = decimal_value(field(config, "exchRate"), "exchRate")
    if hours.negative? || rate_usd <= 0 || exchange_rate <= 0
      raise ConfigError, "hours cannot be negative and configured rates must be positive"
    end

    service_amount = money(hours * rate_usd * exchange_rate)
    reimbursements = record.fetch("reimbursements", [])
    raise ConfigError, "invoice.reimbursements must be an array" unless reimbursements.is_a?(Array)
    tax_enabled = gst_applies(config, period_start)
    taxable_reimbursements = BigDecimal("0")
    excluded_reimbursements = BigDecimal("0")
    settings = config.fetch("reimbursements", {})
    raise ConfigError, "reimbursements must be an object" unless settings.is_a?(Hash)
    reimbursement_treatment = settings.fetch("gstTreatment", "excludedFromTaxableValue")
    unless REIMBURSEMENT_TREATMENTS.include?(reimbursement_treatment)
      raise ConfigError, "reimbursements.gstTreatment must be includedInTaxableValue or excludedFromTaxableValue"
    end
    normalized_reimbursements = reimbursements.each_with_index.map do |item, index|
      prefix = "invoice.reimbursements[#{index}]"
      raise ConfigError, "#{prefix} must be an object" unless item.is_a?(Hash)
      label = item.fetch("name", item["tool"])
      raise ConfigError, "#{prefix}.name must not be empty" unless label.is_a?(String) && !label.strip.empty?
      amount = money(field(item, "amount"))
      raise ConfigError, "#{prefix}.amount must be greater than zero" unless amount.positive?
      if reimbursement_treatment == "includedInTaxableValue"
        taxable_reimbursements += amount
      else
        excluded_reimbursements += amount
      end
      { "name" => label.strip, "amount" => amount }
    end

    taxable_value = money(service_amount + taxable_reimbursements)
    taxes = []
    treatment = nil
    if validate_document
      validate_party(config, "from", tax_enabled)
      validate_party(config, "client", tax_enabled)
    end
    if tax_enabled
      tax = tax_profile(config)
      if validate_document
        sac_code = field(tax, "gstSacCode", String)
        description = tax["gstSacDescription"]
        unless description.nil? || description.is_a?(String)
          raise ConfigError, "taxProfile.gstSacDescription must be a string when provided"
        end
        raise ConfigError, "taxProfile.gstSacCode must contain 4 or 6 digits" unless sac_code.match?(/\A(?:[0-9]{4}|[0-9]{6})\z/)
      end
      rate = decimal_value(field(tax, "gstRatePercent"), "taxProfile.gstRatePercent")
      raise ConfigError, "taxProfile.gstRatePercent must be between 0 and 100" unless (0..100).cover?(rate)
      raise ConfigError, "Only taxProfile.amountsIncludeTax=false is currently supported" unless field(tax, "amountsIncludeTax") == false
      reverse_charge = field(tax, "gstReverseCharge")
      raise ConfigError, "taxProfile.gstReverseCharge must be true or false" unless [true, false].include?(reverse_charge)
      treatment = field(tax, "gstDefaultTreatment", String)
      raise ConfigError, "Unsupported taxProfile.gstDefaultTreatment: #{treatment}" unless TREATMENTS.include?(treatment)
      if %w[intraState interState].include?(treatment)
        supplier_state = field(config, "from.gst.stateCode", String)
        client_state = field(config, "client.gst.stateCode", String)
        if treatment == "intraState" && supplier_state != client_state
          raise ConfigError, "intraState treatment requires matching supplier and client state codes"
        end
        if treatment == "interState" && supplier_state == client_state
          raise ConfigError, "interState treatment requires different supplier and client state codes"
        end
      end
      unless reverse_charge
        if treatment == "intraState"
          half_rate = rate / 2
          half_tax = money(taxable_value * half_rate / 100)
          taxes = [["CGST", half_rate, half_tax], ["SGST", half_rate, half_tax]]
        elsif %w[interState exportWithPayment].include?(treatment)
          taxes = [["IGST", rate, money(taxable_value * rate / 100)]]
        end
      end
    end
    tax_total = money(taxes.sum(BigDecimal("0")) { |item| item[2] })
    grand_total = money(taxable_value + tax_total + excluded_reimbursements)
    if check_amount
      configured_amount = money(field(record, "amount"))
      if configured_amount != grand_total
        raise ConfigError, "invoice.amount is #{configured_amount.to_s('F')} but the deterministic total is #{grand_total.to_s('F')}"
      end
    end
    {
      "hours" => hours, "rateInr" => money(rate_usd * exchange_rate),
      "serviceAmount" => service_amount, "reimbursements" => normalized_reimbursements,
      "subtotal" => money(service_amount + taxable_reimbursements + excluded_reimbursements),
      "taxableValue" => taxable_value, "excludedReimbursements" => money(excluded_reimbursements),
      "taxEnabled" => tax_enabled, "treatment" => treatment,
      "taxes" => taxes, "taxTotal" => tax_total, "grandTotal" => grand_total
    }
  end
end
