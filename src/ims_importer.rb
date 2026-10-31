require "csv"
require "date"
require "digest"
require "json"
require "time"
require_relative "gstr2b_importer"
require_relative "gst_input_tracker"
require_relative "invoice_calculation"
require_relative "invoice_store"

module ImsImporter
  ConfigError = InvoiceCalculation::ConfigError
  STATE_VERSION = 1
  REQUIRED_HEADERS = %w[gstin_of_supplier invoice_number invoice_date invoice_value status].freeze

  module_function

  def state_path(config)
    File.join(InvoiceStore.new(config).root, "gst-ims-imports.json")
  end

  def read_state(config)
    path = state_path(config)
    return { "version" => STATE_VERSION, "imports" => {} } unless File.file?(path)

    state = JSON.parse(File.read(path))
    unless state.is_a?(Hash) && state["version"] == STATE_VERSION && state["imports"].is_a?(Hash)
      raise ConfigError, "gst-ims-imports.json has an unsupported format"
    end
    state
  rescue JSON::ParserError => error
    raise ConfigError, "Invalid gst-ims-imports.json: #{error.message}"
  end

  def latest(config, period)
    read_state(config).fetch("imports")[period_key(period)]
  end

  def tracked_periods(config)
    read_state(config).fetch("imports").values.map { |entry| entry["period"] }.compact
  end

  def import(config, period, path, now: Time.now.utc)
    expanded = File.expand_path(path.to_s)
    raise ConfigError, "Select an existing GST portal IMS B2B CSV file" unless File.file?(expanded)
    raise ConfigError, "IMS import supports the GST portal IMS B2B CSV file" unless File.extname(expanded).downcase == ".csv"

    parsed = parse_csv(expanded)
    invoices = parsed.fetch("invoices")
    raise ConfigError, "No B2B invoice records were found in the selected IMS CSV" if invoices.empty?
    validate_recipient!(config, parsed["recipientGstin"])

    state = read_state(config)
    previous = state.fetch("imports").values.max_by { |entry| entry.fetch("importedAt", "") }
    reconciliation = GstInputTracker.reconcile_ims(config, period, invoices, now: now)
    summary = reconciliation.fetch("summary").merge(snapshot_changes(previous, reconciliation.fetch("invoices")))
    entry = {
      "period" => InvoiceCalculation.parse_month(period).first.strftime("%B %Y"),
      "importedAt" => now.iso8601,
      "sourceFilename" => File.basename(expanded),
      "sourceSha256" => Digest::SHA256.file(expanded).hexdigest,
      "sourceFormat" => "csv",
      "summary" => summary,
      "invoices" => reconciliation.fetch("invoices")
    }
    update_state(config) { |current| current.fetch("imports")[period_key(period)] = entry }
    entry
  end

  def parse_csv(path)
    rows = CSV.read(path, encoding: "bom|utf-8")
    header_index = rows.index do |row|
      keys = row.map { |value| Gstr2bImporter.normalize_key(value) }
      REQUIRED_HEADERS.all? { |header| keys.include?(header) }
    end
    raise ConfigError, "The selected CSV is not a GST portal IMS B2B export" unless header_index

    headers = rows.fetch(header_index).map { |value| Gstr2bImporter.normalize_key(value) }
    invoices = rows.drop(header_index + 1).each_with_object([]) do |row, parsed|
      values = headers.zip(row).to_h
      number = values["invoice_number"].to_s.strip
      date = values["invoice_date"].to_s.strip
      invoice_value = values["invoice_value"].to_s.strip
      next if number.empty? && date.empty? && invoice_value.empty?
      raise ConfigError, "IMS CSV contains an incomplete invoice record" if number.empty? || date.empty? || invoice_value.empty?

      invoice = Gstr2bImporter.normalized_invoice(
        supplier_gstin: values["gstin_of_supplier"],
        supplier_name: values["trade_legal_name"],
        invoice_number: number,
        invoice_date: date,
        invoice_value: invoice_value,
        taxable_value: values["taxable_value"],
        gst_amount: %w[integrated_tax central_tax state_ut_tax cess].sum { |key| Gstr2bImporter.numeric(values[key]) },
        itc_available: true
      )
      parsed << invoice.reject { |key, _| key == "itcAvailable" }.merge(
        "imsStatus" => ims_status(values["status"]),
        "documentType" => values["invoice_type"].to_s.strip,
        "placeOfSupply" => values["place_of_supply"].to_s.strip,
        "remarks" => values["remarks"].to_s.strip,
        "source" => values["source"].to_s.strip,
        "sourceReturnPeriod" => values["source_return_period"].to_s.strip,
        "sourceFilingStatus" => values["source_filing_status"].to_s.strip,
        "sourceReturnFilingDate" => values["source_return_filing_date"].to_s.strip,
        "supplierFilingFrequency" => values["filing_frequency_of_supplier"].to_s.strip
      )
    end
    {
      "recipientGstin" => recipient_gstin_from_filename(path),
      "invoices" => invoices.each_with_object({}) { |invoice, result| result[invoice.fetch("documentKey")] = invoice }.values
    }
  rescue CSV::MalformedCSVError => error
    raise ConfigError, "Invalid IMS CSV: #{error.message}"
  end

  def ims_status(value)
    text = Gstr2bImporter.normalize_key(value)
    return "accepted" if %w[a accept accepted].include?(text)
    return "rejected" if %w[r reject rejected].include?(text)
    return "pending" if %w[p pending].include?(text)
    return "no_action" if text.empty? || %w[no_action noaction].include?(text)
    raise ConfigError, "Unsupported IMS status: #{value}"
  end

  def recipient_gstin_from_filename(path)
    match = File.basename(path).match(/\AIMS_B2B_([0-9A-Z]{15})_/i)
    match && match[1].upcase
  end

  def validate_recipient!(config, recipient_gstin)
    configured = config.dig("from", "gst", "gstin").to_s.strip.upcase
    return if configured.empty? || recipient_gstin.to_s.empty?
    unless configured == recipient_gstin
      raise ConfigError, "The selected IMS CSV is for a different recipient GSTIN"
    end
  end

  def snapshot_changes(previous, invoices)
    previous_by_key = (previous&.fetch("invoices", []) || []).to_h { |invoice| [invoice.fetch("documentKey"), invoice] }
    current_by_key = invoices.to_h { |invoice| [invoice.fetch("documentKey"), invoice] }
    {
      "newCount" => (current_by_key.keys - previous_by_key.keys).length,
      "changedCount" => (current_by_key.keys & previous_by_key.keys).count do |key|
        current_by_key.fetch(key).fetch("imsStatus") != previous_by_key.fetch(key).fetch("imsStatus")
      end,
      "removedCount" => (previous_by_key.keys - current_by_key.keys).length
    }
  end

  def period_key(period)
    InvoiceCalculation.parse_month(period).first.strftime("%m%Y")
  end

  def update_state(config)
    store = InvoiceStore.new(config)
    FileUtils.mkdir_p(store.root)
    File.open(File.join(store.root, ".gst-ims-imports.lock"), File::RDWR | File::CREAT, 0600) do |lock|
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
