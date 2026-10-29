require "json"
require "date"
require_relative "invoice_calculation"
require_relative "invoice_store"
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

  def validate(config, snapshot)
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
    sac = required_string(tax, "gstSacCode", "taxProfile.gstSacCode")
    raise ConfigError, "taxProfile.gstSacCode must contain 2 to 8 digits" unless sac.match?(/\A[0-9]{2,8}\z/)
    uqc = required_string(tax, "gstUqc", "taxProfile.gstUqc")
    raise ConfigError, "taxProfile.gstUqc must contain 1 to 30 letters" unless uqc.match?(/\A[A-Za-z]{1,30}\z/)
    if sac.start_with?("99") && uqc.upcase != "NA"
      raise ConfigError, 'taxProfile.gstUqc must be "NA" for service SAC codes'
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

  def build_payload(config, snapshot)
    validate(config, snapshot)

    tax = InvoiceCalculation.tax_profile(config)
    gst = snapshot.fetch("gst")
    service = snapshot.fetch("service")
    totals = snapshot.fetch("totals")
    invoice_no = snapshot.fetch("invoiceNo")
    invoice_date = Date.iso8601(snapshot.fetch("invoiceDate"))
    amounts = tax_amounts(snapshot)
    rate = number(gst.fetch("ratePercent"), "snapshot.gst.ratePercent", scale: 2)
    taxable_value = number(totals.fetch("taxableValue"), "snapshot.totals.taxableValue", scale: 2)

    item_details = { "rt" => rate, "txval" => taxable_value }.merge(amounts)
    hsn = {
      "num" => 1,
      "hsn_sc" => tax.fetch("gstSacCode").strip,
      "uqc" => tax.fetch("gstUqc").strip.upcase,
      "qty" => tax.fetch("gstSacCode").strip.start_with?("99") ? 0 : number(service.fetch("hours"), "snapshot.service.hours", scale: 2),
      "txval" => taxable_value,
      "rt" => rate
    }.merge(amounts)

    {
      "gstin" => snapshot.fetch("supplier").fetch("gst").fetch("gstin").upcase,
      "fp" => invoice_date.strftime("%m%Y"),
      "version" => OFFLINE_TOOL_VERSION,
      "hash" => "hash",
      "b2b" => [{
        "ctin" => snapshot.fetch("customer").fetch("gst").fetch("gstin").upcase,
        "inv" => [{
          "inum" => invoice_no,
          "idt" => invoice_date.strftime("%d-%m-%Y"),
          "val" => number(totals.fetch("grandTotal"), "snapshot.totals.grandTotal", scale: 2),
          "pos" => gst.fetch("placeOfSupply"),
          "rchrg" => gst.fetch("reverseCharge") ? "Y" : "N",
          "inv_typ" => "R",
          "itms" => [{ "num" => 1, "itm_det" => item_details }]
        }]
      }],
      "hsn" => { "hsn_b2b" => [hsn] },
      "doc_issue" => {
        "doc_det" => [{
          "doc_num" => 1,
          "docs" => [{
            "num" => 1,
            "from" => invoice_no,
            "to" => invoice_no,
            "totnum" => 1,
            "cancel" => 0,
            "net_issue" => 1
          }]
        }]
      }
    }
  end

  def generate(filing_period_label, config: TimeLog.load_config)
    store = InvoiceStore.new(config)
    filing_period = InvoiceCalculation.parse_month(filing_period_label).first.strftime("%m%Y")
    record = store.records.find do |candidate|
      snapshot = candidate["snapshot"]
      next false unless snapshot.is_a?(Hash) && snapshot["version"] == 1

      Date.iso8601(snapshot.fetch("invoiceDate")).strftime("%m%Y") == filing_period
    rescue KeyError, TypeError, ArgumentError
      false
    end
    unless record
      raise ConfigError, "No generated invoice is dated in #{filing_period_label}"
    end
    unless record.fetch("reimbursements", []).empty?
      raise ConfigError, "GSTR-1 export does not support invoices with reimbursements"
    end
    snapshot = record["snapshot"]
    unless snapshot["invoiceNo"] == record.fetch("invoiceNo")
      raise ConfigError, "Invoice snapshot number does not match the saved invoice sequence"
    end
    payload = build_payload(config, snapshot)
    output_path = File.join(store.directory(record), "#{record.fetch('invoiceNo')} GSTR-1 - #{filing_period_label}.json")
    InvoiceStore.write_json(output_path, payload)
    output_path
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: ruby src/generate_gstr1.rb "September 2026"') if ARGV.empty?
  period = ARGV.join(" ")
  begin
    puts Gstr1Generator.generate(period)
  rescue StandardError => error
    path = TimeLog.log_error("generate_gstr1.rb", error, "filingPeriod" => period)
    warn "GSTR-1 generation failed: #{error.message}\nDetails: #{path}"
    exit 1
  end
end
