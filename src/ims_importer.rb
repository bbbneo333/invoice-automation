require "date"
require "digest"
require "json"
require "rexml/document"
require "time"
require_relative "backend_dependencies"
require_relative "gstr2b_importer"
require_relative "gst_input_tracker"
require_relative "invoice_calculation"
require_relative "invoice_store"

module ImsImporter
  ConfigError = InvoiceCalculation::ConfigError
  STATE_VERSION = 1
  ACTION_KEYS = %w[action action_taken recipient_action recipient_s_action action_taken_by_recipient ims_action status record_status].freeze
  DOCUMENT_TYPE_KEYS = %w[document_type documenttype invoice_type invoicetype].freeze

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
    raise ConfigError, "Select an existing IMS XLSX file" unless File.file?(expanded)
    raise ConfigError, "IMS import supports the GST portal XLSX file" unless File.extname(expanded).downcase == ".xlsx"

    invoices = parse_xlsx(expanded)
    raise ConfigError, "No invoice records were found in the selected IMS file" if invoices.empty?

    state = read_state(config)
    previous = state.fetch("imports").values.max_by { |entry| entry.fetch("importedAt", "") }
    reconciliation = GstInputTracker.reconcile_ims(config, period, invoices, now: now)
    summary = reconciliation.fetch("summary").merge(snapshot_changes(previous, reconciliation.fetch("invoices")))
    entry = {
      "period" => InvoiceCalculation.parse_month(period).first.strftime("%B %Y"),
      "importedAt" => now.iso8601,
      "sourceFilename" => File.basename(expanded),
      "sourceSha256" => Digest::SHA256.file(expanded).hexdigest,
      "summary" => summary,
      "invoices" => reconciliation.fetch("invoices")
    }
    update_state(config) { |current| current.fetch("imports")[period_key(period)] = entry }
    entry
  end

  def parse_xlsx(path)
    invoices = []
    Zip::File.open(path) do |archive|
      shared_strings = Gstr2bImporter.xlsx_shared_strings(archive)
      worksheet_names(archive).each do |entry_path, sheet_name|
        entry = archive.find_entry(entry_path)
        next unless entry
        rows = Gstr2bImporter.xlsx_rows(entry.get_input_stream.read, shared_strings)
        header_index = rows.index { |row| Gstr2bImporter.xlsx_header?(row) }
        next unless header_index
        headers = rows.fetch(header_index).each_with_index.to_h do |value, index|
          [Gstr2bImporter.normalize_key(value), index]
        end
        rows.drop(header_index + 1).each do |row|
          number = Gstr2bImporter.xlsx_value(row, headers, Gstr2bImporter::INVOICE_NUMBER_KEYS)
          date = Gstr2bImporter.xlsx_value(row, headers, Gstr2bImporter::INVOICE_DATE_KEYS)
          value_amount = Gstr2bImporter.xlsx_value(row, headers, Gstr2bImporter::INVOICE_VALUE_KEYS)
          next if number.to_s.strip.empty? || date.to_s.strip.empty? || value_amount.to_s.strip.empty?

          invoice = Gstr2bImporter.normalized_invoice(
            supplier_gstin: Gstr2bImporter.xlsx_value(row, headers, Gstr2bImporter::SUPPLIER_GSTIN_KEYS),
            supplier_name: Gstr2bImporter.xlsx_value(row, headers, Gstr2bImporter::SUPPLIER_NAME_KEYS),
            invoice_number: number,
            invoice_date: Gstr2bImporter.excel_date(date),
            invoice_value: value_amount,
            taxable_value: Gstr2bImporter.xlsx_value(row, headers, Gstr2bImporter::TAXABLE_VALUE_KEYS) || 0,
            gst_amount: Gstr2bImporter.xlsx_tax(row, headers),
            itc_available: true
          )
          action = Gstr2bImporter.xlsx_value(row, headers, ACTION_KEYS)
          document_type = Gstr2bImporter.xlsx_value(row, headers, DOCUMENT_TYPE_KEYS)
          invoices << invoice.reject { |key, _| key == "itcAvailable" }.merge(
            "imsStatus" => ims_status(action || sheet_name),
            "documentType" => document_type.to_s.strip
          )
        end
      end
    end
    invoices.each_with_object({}) { |invoice, result| result[invoice.fetch("documentKey")] = invoice }.values
  rescue Zip::Error, REXML::ParseException => error
    raise ConfigError, "Invalid IMS XLSX: #{error.message}"
  end

  def worksheet_names(archive)
    workbook = archive.find_entry("xl/workbook.xml")
    relationships = archive.find_entry("xl/_rels/workbook.xml.rels")
    return archive.glob("xl/worksheets/*.xml").to_h { |entry| [entry.name, File.basename(entry.name)] } unless workbook && relationships

    relationship_document = REXML::Document.new(relationships.get_input_stream.read)
    targets = {}
    REXML::XPath.match(relationship_document, "//Relationship").each do |relationship|
      targets[relationship.attributes["Id"]] = relationship.attributes["Target"]
    end
    workbook_document = REXML::Document.new(workbook.get_input_stream.read)
    REXML::XPath.match(workbook_document, "//sheet").each_with_object({}) do |sheet, result|
      target = targets[sheet.attributes["r:id"]]
      next unless target
      path = target.start_with?("/") ? target.delete_prefix("/") : File.join("xl", target)
      result[path] = sheet.attributes["name"].to_s
    end
  end

  def ims_status(value)
    text = Gstr2bImporter.normalize_key(value)
    return "rejected" if text == "r"
    return "pending" if text == "p"
    return "accepted" if text == "a"
    return "rejected" if text.include?("reject")
    return "pending" if text.include?("pending")
    return "accepted" if text.include?("accept")
    "no_action"
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
