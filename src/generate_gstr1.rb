require "json"
require "date"
require_relative "invoice_calculation"
require_relative "invoice_store"
require_relative "gst_filing"
require_relative "time_log"

# Builds the subset of the GST Returns Offline Tool 3.2.4 upload payload
# supported by this app: B2B invoices, HSN/SAC summary for B2B supplies, and
# Documents Issued.
module Gstr1Generator
  ConfigError = InvoiceCalculation::ConfigError
  OFFLINE_TOOL_VERSION = "GST3.2.4"

  module_function

  def number(value, path, scale: nil)
    decimal = InvoiceCalculation.decimal_value(value, path)
    decimal = decimal.round(scale, :half_up) unless scale.nil?
    decimal.frac.zero? ? decimal.to_i : decimal.to_f
  end

  def required_string(mapping, key, path)
    value = mapping[key]
    unless value.is_a?(String) && !value.strip.empty?
      raise ConfigError, "Missing required value: #{path}"
    end
    value.strip
  end

  def tax_amounts(snapshot)
    snapshot.fetch("gst").fetch("taxes", []).each_with_object({}) do |tax, result|
      field = case tax.fetch("name")
              when "IGST" then "iamt"
              when "CGST" then "camt"
              when "SGST" then "samt"
              else
                raise ConfigError, "Unsupported GST tax in invoice snapshot: #{tax['name']}"
              end
      result[field] = number(tax.fetch("amount"), "snapshot.gst.taxes.amount", scale: 2)
    end
  end

  def validate(config, snapshot, require_hsn: true)
    raise ConfigError, "Invalid invoice snapshot" unless snapshot.is_a?(Hash) && snapshot["version"] == 1
    gst = snapshot["gst"]
    raise ConfigError, "The saved invoice is not a GST invoice" unless gst.is_a?(Hash) && gst["enabled"] == true
    unless %w[intraState interState].include?(gst["treatment"])
      raise ConfigError, "GSTR-1 export currently supports only intraState and interState B2B invoices"
    end
    unless snapshot.fetch("reimbursements", []).empty?
      raise ConfigError, "GSTR-1 export does not support invoices with reimbursements"
    end

    tax = InvoiceCalculation.tax_profile(config)
    raise ConfigError, "A GST taxProfile is required for GSTR-1 export" unless tax
    if require_hsn
      sac = required_string(tax, "gstSacCode", "taxProfile.gstSacCode")
      raise ConfigError, "taxProfile.gstSacCode must contain 2 to 8 digits" unless sac.match?(/\A[0-9]{2,8}\z/)
      uqc = required_string(tax, "gstUqc", "taxProfile.gstUqc")
      raise ConfigError, "taxProfile.gstUqc must contain 1 to 30 letters" unless uqc.match?(/\A[A-Za-z]{1,30}\z/)
      if sac.start_with?("99") && uqc.upcase != "NA"
        raise ConfigError, 'taxProfile.gstUqc must be "NA" for service SAC codes'
      end
    end

    invoice_no = required_string(snapshot, "invoiceNo", "snapshot.invoiceNo")
    unless invoice_no.length <= 16 && invoice_no.match?(/\A(?=.{1,16}\z)([\/-0]*[A-Za-z0-9\/-]*[A-Za-z1-9]+[A-Za-z0-9\/-]*)\z/)
      raise ConfigError, "Invoice number is not valid for GSTR-1"
    end
    Date.iso8601(required_string(snapshot, "invoiceDate", "snapshot.invoiceDate"))

    supplier_gst = snapshot.fetch("supplier").fetch("gst")
    customer_gst = snapshot.fetch("customer").fetch("gst")
    required_string(supplier_gst, "gstin", "snapshot.supplier.gst.gstin")
    required_string(customer_gst, "gstin", "snapshot.customer.gst.gstin")
    pos = required_string(gst, "placeOfSupply", "snapshot.gst.placeOfSupply")
    raise ConfigError, "snapshot.gst.placeOfSupply must contain two digits" unless pos.match?(/\A[0-9]{2}\z/)
  rescue KeyError, TypeError, ArgumentError => error
    raise error if error.is_a?(ConfigError)
    raise ConfigError, "Invalid invoice snapshot: #{error.message}"
  end

  def invoice_entry(snapshot)
    gst = snapshot.fetch("gst")
    totals = snapshot.fetch("totals")
    invoice_no = snapshot.fetch("invoiceNo")
    invoice_date = Date.iso8601(snapshot.fetch("invoiceDate"))
    amounts = tax_amounts(snapshot)
    rate = number(gst.fetch("ratePercent"), "snapshot.gst.ratePercent", scale: 2)
    taxable_value = number(totals.fetch("taxableValue"), "snapshot.totals.taxableValue", scale: 2)

    item_details = { "rt" => rate, "txval" => taxable_value }.merge(amounts)
    {
      "inum" => invoice_no,
      "idt" => invoice_date.strftime("%d-%m-%Y"),
      "val" => number(totals.fetch("grandTotal"), "snapshot.totals.grandTotal", scale: 2),
      "pos" => gst.fetch("placeOfSupply"),
      "rchrg" => gst.fetch("reverseCharge") ? "Y" : "N",
      "inv_typ" => "R",
      "itms" => [{ "num" => 1, "itm_det" => item_details }]
    }
  end

  def b2b_rows(snapshots)
    snapshots.group_by { |snapshot| snapshot.fetch("customer").fetch("gst").fetch("gstin").upcase }
      .map do |gstin, grouped|
        { "ctin" => gstin, "inv" => grouped.sort_by { |snapshot| Date.iso8601(snapshot.fetch("invoiceDate")) }.map { |snapshot| invoice_entry(snapshot) } }
      end
  end

  def hsn_entry(config, snapshot)
    tax = InvoiceCalculation.tax_profile(config)
    gst = snapshot.fetch("gst")
    service = snapshot.fetch("service")
    totals = snapshot.fetch("totals")
    amounts = tax_amounts(snapshot)
    rate = number(gst.fetch("ratePercent"), "snapshot.gst.ratePercent", scale: 2)
    taxable_value = number(totals.fetch("taxableValue"), "snapshot.totals.taxableValue", scale: 2)
    {
      "num" => 1,
      "hsn_sc" => tax.fetch("gstSacCode").strip,
      "uqc" => tax.fetch("gstUqc").strip.upcase,
      "qty" => tax.fetch("gstSacCode").strip.start_with?("99") ? 0 : number(service.fetch("hours"), "snapshot.service.hours", scale: 2),
      "txval" => taxable_value,
      "rt" => rate
    }.merge(amounts)
  end

  def hsn_rows(config, snapshots)
    grouped = snapshots.map { |snapshot| hsn_entry(config, snapshot) }.group_by do |entry|
      [entry.fetch("hsn_sc"), entry.fetch("uqc"), entry.fetch("rt")]
    end
    grouped.values.each_with_index.map do |entries, index|
      first = entries.first
      result = { "num" => index + 1, "hsn_sc" => first.fetch("hsn_sc"), "uqc" => first.fetch("uqc") }
      %w[qty txval rt iamt camt samt].each do |key|
        next unless entries.any? { |entry| entry.key?(key) }
        values = entries.select { |entry| entry.key?(key) }.map { |entry| InvoiceCalculation.decimal_value(entry.fetch(key), "hsn.#{key}") }
        result[key] = key == "rt" ? number(first.fetch(key), "hsn.rt", scale: 2) : number(values.sum, "hsn.#{key}", scale: 2)
      end
      result
    end
  end

  def document_rows(snapshots)
    documents = snapshots.sort_by { |snapshot| snapshot.fetch("invoiceNo").to_i }.each_with_index.map do |snapshot, index|
      number = snapshot.fetch("invoiceNo")
      { "num" => index + 1, "from" => number, "to" => number, "totnum" => 1, "cancel" => 0, "net_issue" => 1 }
    end
    { "doc_det" => [{ "doc_num" => 1, "docs" => documents }] }
  end

  def supplier_gstin(snapshots)
    gstins = snapshots.map { |snapshot| snapshot.fetch("supplier").fetch("gst").fetch("gstin").upcase }.uniq
    raise ConfigError, "Invoice snapshots contain multiple supplier GSTINs" unless gstins.length == 1
    gstins.first
  end

  def build_payload(config, snapshot)
    validate(config, snapshot)
    invoice_date = Date.iso8601(snapshot.fetch("invoiceDate"))

    {
      "gstin" => supplier_gstin([snapshot]),
      "fp" => invoice_date.strftime("%m%Y"),
      "version" => OFFLINE_TOOL_VERSION,
      "hash" => "hash",
      "b2b" => b2b_rows([snapshot]),
      "hsn" => { "hsn_b2b" => hsn_rows(config, [snapshot]) },
      "doc_issue" => document_rows([snapshot])
    }
  end

  def build_iff_payload(config, snapshots, filing_period_label)
    raise ConfigError, "No generated invoice is dated in #{filing_period_label}" if snapshots.empty?
    period = InvoiceCalculation.parse_month(filing_period_label).first
    snapshots.each do |snapshot|
      validate(config, snapshot, require_hsn: false)
      date = Date.iso8601(snapshot.fetch("invoiceDate"))
      raise ConfigError, "IFF invoice date is outside #{filing_period_label}" unless date.year == period.year && date.month == period.month
    end
    {
      "gstin" => supplier_gstin(snapshots), "fp" => period.strftime("%m%Y"),
      "version" => OFFLINE_TOOL_VERSION, "hash" => "hash", "b2b" => b2b_rows(snapshots)
    }
  end

  def build_quarterly_payload(config, b2b_snapshots:, summary_snapshots:, quarter_end_month:)
    raise ConfigError, "No generated invoices exist in the selected quarter" if summary_snapshots.empty?
    period = GstFiling.quarter(quarter_end_month)
    summary_snapshots.each do |snapshot|
      validate(config, snapshot)
      date = Date.iso8601(snapshot.fetch("invoiceDate"))
      unless (period.fetch("startDate")..period.fetch("endDate")).cover?(date)
        raise ConfigError, "Invoice date is outside #{period.fetch('label')}"
      end
    end
    {
      "gstin" => supplier_gstin(summary_snapshots),
      "fp" => period.fetch("endDate").strftime("%m%Y"),
      "version" => OFFLINE_TOOL_VERSION,
      "hash" => "hash",
      "b2b" => b2b_rows(b2b_snapshots),
      "hsn" => { "hsn_b2b" => hsn_rows(config, summary_snapshots) },
      "doc_issue" => document_rows(summary_snapshots)
    }
  end

  def snapshot_records(config)
    store = InvoiceStore.new(config)
    store.records.each_with_object([]) do |candidate, result|
      snapshot = candidate["snapshot"]
      next unless snapshot.is_a?(Hash) && snapshot["version"] == 1
      raise ConfigError, "Invoice snapshot number does not match the saved invoice sequence" unless snapshot["invoiceNo"] == candidate.fetch("invoiceNo")
      result << [candidate, snapshot]
    end
  end

  def records_in_range(config, range)
    snapshot_records(config).select { |_, snapshot| range.cover?(Date.iso8601(snapshot.fetch("invoiceDate"))) }
  end

  def generate_monthly(filing_period_label, config: TimeLog.load_config)
    GstFiling.require_monthly!(config, filing_period_label)
    raise ConfigError, "GSTR-1 for #{filing_period_label} is already marked filed" if GstFiling.gstr1_filed?(config, filing_period_label)
    period_start, period_end = InvoiceCalculation.parse_month(filing_period_label)
    matches = records_in_range(config, period_start..period_end)
    raise ConfigError, "No generated invoice is dated in #{filing_period_label}" if matches.empty?
    raise ConfigError, "Multiple generated invoices are dated in #{filing_period_label}; monthly export supports one" if matches.length > 1
    record, snapshot = matches.first
    payload = build_payload(config, snapshot)
    store = InvoiceStore.new(config)
    output_path = File.join(store.directory(record), "#{record.fetch('invoiceNo')} GSTR-1 - #{filing_period_label}.json")
    InvoiceStore.write_json(output_path, payload)
    GstFiling.record_gstr1_generated(config, filing_period_label, [snapshot], output_path, kind: "monthly")
    output_path
  end

  def generate_iff(filing_period_label, config: TimeLog.load_config)
    GstFiling.require_qrmp_iff!(config, filing_period_label)
    raise ConfigError, "IFF is available only for the first two months of a quarter" unless GstFiling.iff_eligible?(filing_period_label)
    raise ConfigError, "IFF for #{filing_period_label} is already marked filed" if GstFiling.iff_filed?(config, filing_period_label)
    period_start, period_end = InvoiceCalculation.parse_month(filing_period_label)
    matches = records_in_range(config, period_start..period_end)
    snapshots = matches.map(&:last)
    payload = build_iff_payload(config, snapshots, filing_period_label)
    output_path = File.join(GstFiling.returns_directory(config, filing_period_label), "#{filing_period_label} IFF.json")
    InvoiceStore.write_json(output_path, payload)
    GstFiling.record_iff_generated(config, filing_period_label, snapshots, output_path)
    output_path
  end

  def generate_quarterly(quarter_end_month, config: TimeLog.load_config)
    GstFiling.require_qrmp!(config, quarter_end_month)
    period = GstFiling.quarter(quarter_end_month)
    filing_period = period.fetch("endMonth")
    raise ConfigError, "GSTR-1 for #{filing_period} is already marked filed" if GstFiling.gstr1_filed?(config, filing_period)
    matches = records_in_range(config, period.fetch("startDate")..period.fetch("endDate"))
    summary_snapshots = matches.map(&:last)
    b2b_snapshots = matches.reject do |_, snapshot|
      month = Date.iso8601(snapshot.fetch("invoiceDate")).strftime("%B %Y")
      GstFiling.iff_filed_snapshot?(config, month, snapshot)
    end.map(&:last)
    payload = build_quarterly_payload(
      config, b2b_snapshots: b2b_snapshots, summary_snapshots: summary_snapshots,
      quarter_end_month: period.fetch("endMonth")
    )
    output_path = File.join(GstFiling.returns_directory(config, period.fetch("endMonth")), "#{period.fetch('label')} GSTR-1.json")
    InvoiceStore.write_json(output_path, payload)
    GstFiling.record_gstr1_generated(config, filing_period, summary_snapshots, output_path, kind: "quarterly")
    output_path
  end

  def generate(filing_period_label, config: TimeLog.load_config)
    GstFiling.settings(config, period: filing_period_label).fetch("scheme") == "qrmp" ? generate_quarterly(filing_period_label, config: config) : generate_monthly(filing_period_label, config: config)
  end
end

if $PROGRAM_NAME == __FILE__
  iff = !!ARGV.delete("--iff")
  abort('Usage: ruby src/generate_gstr1.rb [--iff] "September 2026"') if ARGV.empty?
  period = ARGV.join(" ")
  begin
    puts(iff ? Gstr1Generator.generate_iff(period) : Gstr1Generator.generate(period))
  rescue StandardError => error
    path = TimeLog.log_error("generate_gstr1.rb", error, "filingPeriod" => period)
    warn "GSTR-1 generation failed: #{error.message}\nDetails: #{path}"
    exit 1
  end
end
