require "bigdecimal"
require "date"
require "digest"
require "json"
require "rexml/document"
require "time"
require_relative "backend_dependencies"
require_relative "gst_input_tracker"
require_relative "invoice_calculation"
require_relative "invoice_store"

module Gstr2bImporter
  ConfigError = InvoiceCalculation::ConfigError
  STATE_VERSION = 1
  INVOICE_NUMBER_KEYS = %w[inum invnum invoice_number invoicenumber document_number documentnumber].freeze
  INVOICE_DATE_KEYS = %w[dt idt invdt invoice_date invoicedate document_date documentdate].freeze
  INVOICE_VALUE_KEYS = %w[val invvalue invoice_value invoicevalue total_invoice_value totalinvoicevalue].freeze
  TAXABLE_VALUE_KEYS = %w[txval taxable_value taxablevalue].freeze
  IGST_KEYS = %w[igst iamt integrated_tax integratedtax].freeze
  CGST_KEYS = %w[cgst camt central_tax centraltax].freeze
  SGST_KEYS = %w[sgst samt state_tax state_ut_tax statetax utgst].freeze
  CESS_KEYS = %w[cess csamt cess_amount cessamount].freeze
  SUPPLIER_GSTIN_KEYS = %w[ctin sgstin supplier_gstin suppliergstin gstin_of_supplier].freeze
  SUPPLIER_NAME_KEYS = %w[trdnm supplier_name suppliername trade_legal_name tradelegalname].freeze
  ELIGIBILITY_KEYS = %w[itcavl itc_available itcavailability itc_availability].freeze

  module_function

  def state_path(config)
    File.join(InvoiceStore.new(config).root, "gst-2b-imports.json")
  end

  def read_state(config)
    path = state_path(config)
    return { "version" => STATE_VERSION, "imports" => {} } unless File.file?(path)

    state = JSON.parse(File.read(path))
    unless state.is_a?(Hash) && state["version"] == STATE_VERSION && state["imports"].is_a?(Hash)
      raise ConfigError, "gst-2b-imports.json has an unsupported format"
    end
    state
  rescue JSON::ParserError => error
    raise ConfigError, "Invalid gst-2b-imports.json: #{error.message}"
  end

  def latest(config, period)
    read_state(config).fetch("imports")[period_key(period)]
  end

  def tracked_periods(config)
    read_state(config).fetch("imports").values.map { |entry| entry["period"] }.compact
  end

  def import(config, period, path, now: Time.now.utc)
    expanded = File.expand_path(path.to_s)
    raise ConfigError, "Select an existing GSTR-2B JSON or XLSX file" unless File.file?(expanded)

    parsed = parse(expanded)
    if parsed["filingPeriod"] && period_key(parsed.fetch("filingPeriod")) != period_key(period)
      raise ConfigError, "The selected GSTR-2B is for #{parsed.fetch('filingPeriod')}, not #{period}"
    end
    invoices = parsed.fetch("invoices")
    raise ConfigError, "No B2B invoices were found in the selected GSTR-2B file" if invoices.empty?

    reconciliation = GstInputTracker.reconcile_gstr2b(config, period, invoices, now: now)
    entry = {
      "period" => InvoiceCalculation.parse_month(period).first.strftime("%B %Y"),
      "importedAt" => now.iso8601,
      "sourceFilename" => File.basename(expanded),
      "sourceSha256" => Digest::SHA256.file(expanded).hexdigest,
      "format" => File.extname(expanded).delete_prefix(".").downcase,
      "summary" => reconciliation.fetch("summary"),
      "invoices" => reconciliation.fetch("invoices")
    }
    update_state(config) do |state|
      state.fetch("imports")[period_key(period)] = entry
    end
    entry
  end

  def parse(path)
    case File.extname(path).downcase
    when ".json"
      parse_json(path)
    when ".xlsx"
      parse_xlsx(path)
    else
      raise ConfigError, "GSTR-2B import supports JSON and XLSX files"
    end
  end

  def parse_json(path)
    root = JSON.parse(File.read(path))
    invoices = []
    walk_json(root, {}, invoices)
    {
      "filingPeriod" => find_filing_period(root),
      "invoices" => deduplicate(invoices)
    }
  rescue JSON::ParserError => error
    raise ConfigError, "Invalid GSTR-2B JSON: #{error.message}"
  end

  def walk_json(value, context, invoices)
    case value
    when Hash
      normalized = value.each_with_object({}) { |(key, child), result| result[normalize_key(key)] = child }
      inherited = context.merge(
        "supplierGstin" => first_value(normalized, SUPPLIER_GSTIN_KEYS) || context["supplierGstin"],
        "supplierName" => first_value(normalized, SUPPLIER_NAME_KEYS) || context["supplierName"],
        "itcAvailable" => eligibility(first_value(normalized, ELIGIBILITY_KEYS), context["itcAvailable"])
      )
      number = first_value(normalized, INVOICE_NUMBER_KEYS)
      date = first_value(normalized, INVOICE_DATE_KEYS)
      value_amount = first_value(normalized, INVOICE_VALUE_KEYS)
      if number && date && value_amount
        invoices << normalized_invoice(
          supplier_gstin: inherited["supplierGstin"], supplier_name: inherited["supplierName"],
          invoice_number: number, invoice_date: date, invoice_value: value_amount,
          taxable_value: nested_amount(value, TAXABLE_VALUE_KEYS), gst_amount: nested_tax(value),
          itc_available: inherited["itcAvailable"]
        )
      else
        value.each_value { |child| walk_json(child, inherited, invoices) }
      end
    when Array
      value.each { |child| walk_json(child, context, invoices) }
    end
  end

  def parse_xlsx(path)
    invoices = []
    Zip::File.open(path) do |archive|
      shared_strings = xlsx_shared_strings(archive)
      archive.glob("xl/worksheets/*.xml").each do |entry|
        rows = xlsx_rows(entry.get_input_stream.read, shared_strings)
        header_index = rows.index { |row| xlsx_header?(row) }
        next unless header_index
        headers = rows.fetch(header_index).each_with_index.to_h { |value, index| [normalize_key(value), index] }
        rows.drop(header_index + 1).each do |row|
          number = xlsx_value(row, headers, INVOICE_NUMBER_KEYS)
          date = xlsx_value(row, headers, INVOICE_DATE_KEYS)
          value_amount = xlsx_value(row, headers, INVOICE_VALUE_KEYS)
          next if number.to_s.strip.empty? || date.to_s.strip.empty? || value_amount.to_s.strip.empty?
          invoices << normalized_invoice(
            supplier_gstin: xlsx_value(row, headers, SUPPLIER_GSTIN_KEYS),
            supplier_name: xlsx_value(row, headers, SUPPLIER_NAME_KEYS),
            invoice_number: number, invoice_date: excel_date(date), invoice_value: value_amount,
            taxable_value: xlsx_value(row, headers, TAXABLE_VALUE_KEYS) || 0,
            gst_amount: xlsx_tax(row, headers),
            itc_available: eligibility(xlsx_value(row, headers, ELIGIBILITY_KEYS), true)
          )
        end
      end
    end
    { "filingPeriod" => nil, "invoices" => deduplicate(invoices) }
  rescue Zip::Error, REXML::ParseException => error
    raise ConfigError, "Invalid GSTR-2B XLSX: #{error.message}"
  end

  def normalized_invoice(supplier_gstin:, supplier_name:, invoice_number:, invoice_date:, invoice_value:, taxable_value:, gst_amount:, itc_available:)
    date = parse_date(invoice_date)
    total = money(invoice_value, "GSTR-2B invoice value")
    gst = money(gst_amount, "GSTR-2B GST amount")
    taxable = money(taxable_value || (total - gst), "GSTR-2B taxable value")
    supplier = supplier_gstin.to_s.strip.upcase
    number = invoice_number.to_s.strip
    identity = [supplier, normalize_invoice_number(number), date.iso8601, format("%.2f", total)].join("|")
    {
      "documentKey" => Digest::SHA256.hexdigest(identity),
      "supplierGstin" => supplier,
      "supplierName" => supplier_name.to_s.strip,
      "invoiceNumber" => number,
      "invoiceDate" => date.iso8601,
      "invoiceValue" => total.round(2).to_f,
      "taxableValue" => taxable.round(2).to_f,
      "gstAmount" => gst.round(2).to_f,
      "itcAvailable" => itc_available != false
    }
  end

  def nested_tax(value)
    tax_keys = IGST_KEYS + CGST_KEYS + SGST_KEYS + CESS_KEYS
    nested_amount(value, tax_keys)
  end

  def nested_amount(value, keys)
    return BigDecimal("0") unless value.is_a?(Hash)
    normalized = value.each_with_object({}) { |(key, child), result| result[normalize_key(key)] = child }
    current = keys.sum { |key| numeric(normalized[key]) }
    nested = value.values.sum do |child|
      if child.is_a?(Hash)
        nested_amount(child, keys)
      elsif child.is_a?(Array)
        child.sum { |item| item.is_a?(Hash) ? nested_amount(item, keys) : BigDecimal("0") }
      else
        BigDecimal("0")
      end
    end
    nested.zero? ? current : nested
  end

  def xlsx_shared_strings(archive)
    entry = archive.find_entry("xl/sharedStrings.xml")
    return [] unless entry
    document = REXML::Document.new(entry.get_input_stream.read)
    REXML::XPath.match(document, "//si").map do |item|
      REXML::XPath.match(item, ".//t").map { |text| text.text.to_s }.join
    end
  end

  def xlsx_rows(xml, shared_strings)
    document = REXML::Document.new(xml)
    REXML::XPath.match(document, "//row").map do |row|
      values = []
      REXML::XPath.match(row, "./c").each do |cell|
        reference = cell.attributes["r"].to_s
        index = column_index(reference[/[A-Z]+/])
        type = cell.attributes["t"]
        raw = if type == "inlineStr"
          REXML::XPath.match(cell, ".//t").map { |text| text.text.to_s }.join
        else
          REXML::XPath.first(cell, "./v")&.text.to_s
        end
        values[index] = type == "s" ? shared_strings[raw.to_i].to_s : raw
      end
      values
    end
  end

  def xlsx_header?(row)
    keys = row.compact.map { |value| normalize_key(value) }
    INVOICE_NUMBER_KEYS.any? { |key| keys.include?(key) } &&
      INVOICE_DATE_KEYS.any? { |key| keys.include?(key) } &&
      INVOICE_VALUE_KEYS.any? { |key| keys.include?(key) }
  end

  def xlsx_value(row, headers, keys)
    key = keys.find { |candidate| headers.key?(candidate) }
    key ? row[headers.fetch(key)] : nil
  end

  def xlsx_tax(row, headers)
    (IGST_KEYS + CGST_KEYS + SGST_KEYS + CESS_KEYS).sum do |key|
      headers.key?(key) ? numeric(row[headers.fetch(key)]) : BigDecimal("0")
    end
  end

  def column_index(letters)
    letters.to_s.chars.reduce(0) { |result, letter| result * 26 + letter.ord - 64 } - 1
  end

  def excel_date(value)
    text = value.to_s.strip
    return (Date.new(1899, 12, 30) + text.to_f.to_i).iso8601 if text.match?(/\A\d+(?:\.\d+)?\z/) && text.to_f > 20_000
    text
  end

  def find_filing_period(value)
    return nil unless value.is_a?(Hash)
    pair = value.find { |key, _| %w[fp filingperiod filing_period].include?(normalize_key(key)) }
    if pair
      text = pair.last.to_s
      if text.match?(/\A(0[1-9]|1[0-2])\d{4}\z/)
        return Date.strptime(text, "%m%Y").strftime("%B %Y")
      end
    end
    value.each_value do |child|
      found = find_filing_period(child)
      return found if found
    end
    nil
  end

  def deduplicate(invoices)
    invoices.each_with_object({}) { |invoice, result| result[invoice.fetch("documentKey")] ||= invoice }.values
  end

  def eligibility(value, fallback)
    return fallback if value.nil?
    text = normalize_key(value)
    return false if %w[n no ineligible not_available notavailable].include?(text)
    return true if %w[y yes eligible available].include?(text)
    fallback.nil? ? true : fallback
  end

  def first_value(hash, keys)
    key = keys.find { |candidate| hash.key?(candidate) && !hash[candidate].to_s.strip.empty? }
    key && hash[key]
  end

  def normalize_key(value)
    value.to_s.downcase.gsub(/[^a-z0-9]+/, "_").gsub(/\A_|_\z/, "")
  end

  def normalize_invoice_number(value)
    value.to_s.upcase.gsub(/[^A-Z0-9]/, "")
  end

  def parse_date(value)
    text = value.to_s.strip
    format = case text
    when /\A\d{4}-\d{2}-\d{2}\z/ then "%Y-%m-%d"
    when /\A\d{2}-\d{2}-\d{4}\z/ then "%d-%m-%Y"
    when /\A\d{2}\/\d{2}\/\d{4}\z/ then "%d/%m/%Y"
    when /\A\d{1,2}-[A-Za-z]{3}-\d{4}\z/ then "%d-%b-%Y"
    end
    return Date.strptime(text, format) if format
    raise ConfigError, "Invalid GSTR-2B invoice date: #{value}"
  rescue ArgumentError
    raise ConfigError, "Invalid GSTR-2B invoice date: #{value}"
  end

  def money(value, label)
    InvoiceCalculation.decimal_value(value || 0, label)
  end

  def numeric(value)
    return BigDecimal("0") if value.nil? || value.to_s.strip.empty?
    BigDecimal(value.to_s.delete(","))
  rescue ArgumentError
    BigDecimal("0")
  end

  def period_key(period)
    InvoiceCalculation.parse_month(period).first.strftime("%m%Y")
  end

  def update_state(config)
    store = InvoiceStore.new(config)
    FileUtils.mkdir_p(store.root)
    File.open(File.join(store.root, ".gst-2b-imports.lock"), File::RDWR | File::CREAT, 0600) do |lock|
      lock.flock(File::LOCK_EX)
      state = read_state(config)
      yield(state)
      InvoiceStore.write_json(state_path(config), state)
      state
    ensure
      lock.flock(File::LOCK_UN) if lock
    end
  end
end
