require "date"
require "fileutils"
require "json"
require "securerandom"
require "time"
require_relative "invoice_calculation"
require_relative "invoice_store"

module GstInputTracker
  ConfigError = InvoiceCalculation::ConfigError
  STATE_VERSION = 1
  STATUSES = %w[found missing].freeze

  module_function

  def state_path(config)
    File.join(InvoiceStore.new(config).root, "gst-input-bills.json")
  end

  def read_state(config)
    path = state_path(config)
    return { "version" => STATE_VERSION, "bills" => [] } unless File.file?(path)

    state = JSON.parse(File.read(path))
    unless state.is_a?(Hash) && state["version"] == STATE_VERSION && state["bills"].is_a?(Array)
      raise ConfigError, "gst-input-bills.json has an unsupported format"
    end
    state
  rescue JSON::ParserError => error
    raise ConfigError, "Invalid gst-input-bills.json: #{error.message}"
  end

  def month(config, month_label)
    start_date, end_date = InvoiceCalculation.parse_month(month_label)
    all_bills = read_state(config).fetch("bills")
    bills = all_bills.select do |bill|
      bill_date = Date.iso8601(bill.fetch("date"))
      original = (start_date..end_date).cover?(bill_date)
      carried_pending = bill_date < start_date && bill.fetch("status") == "missing"
      carried_found = bill_date < start_date && effective_month(bill) == month_label
      original || carried_pending || carried_found
    end.map do |bill|
      bill.merge("carriedForward" => Date.iso8601(bill.fetch("date")) < start_date)
    end.sort_by { |bill| [bill.fetch("carriedForward") ? 0 : 1, bill.fetch("date"), bill.fetch("label")] }
    summary(month_label, all_bills).merge("bills" => bills)
  end

  def month_summaries(config, month_labels)
    bills = read_state(config).fetch("bills")
    month_labels.map { |month_label| summary(month_label, bills) }
  end

  def tracked_months(config)
    read_state(config).fetch("bills").flat_map do |bill|
      months = [Date.iso8601(bill.fetch("date")).strftime("%B %Y")]
      months << effective_month(bill) if bill.fetch("status") == "found"
      months
    end.compact.uniq
  end

  def add(config, month_label, label:, date:, gst_amount:, total_amount:, status: "missing", found_month: nil, now: Time.now.utc)
    attributes = validated_attributes(month_label, label, date, gst_amount, total_amount, status, found_month)
    update_state(config) do |state|
      state.fetch("bills") << attributes.merge(
        "id" => SecureRandom.uuid,
        "createdAt" => now.iso8601,
        "updatedAt" => now.iso8601
      )
    end
    month(config, month_label)
  end

  def update(config, month_label, id, label:, date:, gst_amount:, total_amount:, status:, found_month: nil, now: Time.now.utc)
    update_state(config) do |state|
      bill = state.fetch("bills").find { |candidate| candidate["id"] == id }
      raise ConfigError, "Unknown GST input bill: #{id}" unless bill
      original_month = Date.iso8601(bill.fetch("date")).strftime("%B %Y")
      attributes = validated_attributes(original_month, label, date, gst_amount, total_amount, status, found_month)
      preserved = bill.slice(
        "id", "createdAt", "supplierGstin", "supplierName", "invoiceNumber",
        "gstr2bDocumentKey", "matchSource", "matchMethod", "itcEligibility"
      )
      bill.replace(preserved.merge(attributes).merge("updatedAt" => now.iso8601))
    end
    month(config, month_label)
  end

  def delete(config, month_label, id)
    update_state(config) do |state|
      before = state.fetch("bills").length
      state.fetch("bills").reject! { |bill| bill["id"] == id }
      raise ConfigError, "Unknown GST input bill: #{id}" if state.fetch("bills").length == before
    end
    month(config, month_label)
  end

  def reconcile_gstr2b(config, period, portal_invoices, now: Time.now.utc)
    period_label = InvoiceCalculation.parse_month(period).first.strftime("%B %Y")
    period_start = quarter_start(period_label)
    reconciled = nil
    update_state(config) do |state|
      bills = state.fetch("bills")
      results = []
      matched_existing = 0
      imported_new = 0
      ambiguous = 0
      previous_resolved = 0

      portal_invoices.each do |invoice|
        document_key = invoice.fetch("documentKey")
        existing = bills.find { |bill| bill["gstr2bDocumentKey"] == document_key }
        if existing
          imported = existing["matchMethod"] == "imported"
          apply_gstr2b_match(existing, invoice, period_label, now)
          existing["matchMethod"] = "imported" if imported
          imported ? imported_new += 1 : matched_existing += 1
          results << invoice.merge("reconciliationStatus" => imported ? "imported" : "matched", "localBillId" => existing.fetch("id"))
          next
        end

        candidates = match_candidates(bills, invoice)
        if candidates.length == 1
          bill = candidates.first
          imported = bill["matchMethod"] == "imported"
          previous_resolved += 1 if Date.iso8601(bill.fetch("date")) < period_start
          apply_gstr2b_match(bill, invoice, period_label, now)
          imported ? imported_new += 1 : matched_existing += 1
          results << invoice.merge("reconciliationStatus" => imported ? "imported" : "matched", "localBillId" => bill.fetch("id"))
        elsif candidates.length > 1
          ambiguous += 1
          results << invoice.merge("reconciliationStatus" => "ambiguous", "candidateBillIds" => candidates.map { |bill| bill.fetch("id") })
        else
          bill = build_gstr2b_bill(invoice, period_label, now)
          bills << bill
          imported_new += 1
          results << invoice.merge("reconciliationStatus" => "imported", "localBillId" => bill.fetch("id"))
        end
      end

      missing = bills.select do |bill|
        Date.iso8601(bill.fetch("date")) <= InvoiceCalculation.parse_month(period_label).last && bill.fetch("status") == "missing"
      end
      eligible = portal_invoices.select { |invoice| invoice.fetch("itcAvailable") }
      represented = results.reject { |invoice| invoice.fetch("reconciliationStatus") == "ambiguous" }
      reconciled = {
        "summary" => {
          "portalInvoiceCount" => portal_invoices.length,
          "matchedCount" => matched_existing,
          "importedCount" => imported_new,
          "ambiguousCount" => ambiguous,
          "missingLocalCount" => missing.length,
          "previousBillsResolvedCount" => previous_resolved,
          "portalGst" => eligible.sum { |invoice| decimal(invoice.fetch("gstAmount"), "GSTR-2B GST") }.round(2).to_f,
          "representedGst" => represented.select { |invoice| invoice.fetch("itcAvailable") }.sum { |invoice| decimal(invoice.fetch("gstAmount"), "GSTR-2B GST") }.round(2).to_f
        },
        "invoices" => results
      }
    end
    reconciled
  end

  def match_candidates(bills, invoice)
    available = bills.reject do |bill|
      bill["gstr2bDocumentKey"] && bill["gstr2bDocumentKey"] != invoice.fetch("documentKey")
    end
    supplier = invoice.fetch("supplierGstin").to_s.upcase
    number = normalize_invoice_number(invoice.fetch("invoiceNumber"))
    strong = available.select do |bill|
      !bill["supplierGstin"].to_s.empty? && !bill["invoiceNumber"].to_s.empty? &&
        bill["supplierGstin"].to_s.upcase == supplier && normalize_invoice_number(bill["invoiceNumber"]) == number
    end
    return strong unless strong.empty?

    available.select do |bill|
      bill.fetch("date") == invoice.fetch("invoiceDate") &&
        decimal(bill.fetch("gstAmount"), "gstAmount").round(2) == decimal(invoice.fetch("gstAmount"), "GSTR-2B GST").round(2) &&
        decimal(bill.fetch("totalAmount"), "totalAmount").round(2) == decimal(invoice.fetch("invoiceValue"), "GSTR-2B invoice value").round(2)
    end
  end

  def apply_gstr2b_match(bill, invoice, period_label, now)
    imported = bill["matchMethod"] == "imported"
    if imported
      bill["date"] = invoice.fetch("invoiceDate")
      bill["gstAmount"] = InvoiceCalculation.format_monetary_value(invoice.fetch("gstAmount"), "GSTR-2B GST")
      bill["totalAmount"] = InvoiceCalculation.format_monetary_value(invoice.fetch("invoiceValue"), "GSTR-2B invoice value")
    end
    bill["status"] = "found"
    bill["foundInMonth"] = period_label
    bill["supplierGstin"] = invoice.fetch("supplierGstin")
    bill["supplierName"] = invoice.fetch("supplierName")
    bill["invoiceNumber"] = invoice.fetch("invoiceNumber")
    bill["gstr2bDocumentKey"] = invoice.fetch("documentKey")
    bill["matchSource"] = "gstr2b"
    bill["matchMethod"] = imported ? "imported" : (bill.fetch("date") == invoice.fetch("invoiceDate") ? "exact" : "identity")
    bill["itcEligibility"] = invoice.fetch("itcAvailable") ? "eligible" : "ineligible"
    bill["updatedAt"] = now.iso8601
  end

  def build_gstr2b_bill(invoice, period_label, now)
    supplier = invoice.fetch("supplierName").to_s.strip
    supplier = invoice.fetch("supplierGstin") if supplier.empty?
    {
      "id" => SecureRandom.uuid,
      "label" => [supplier, invoice.fetch("invoiceNumber")].reject(&:empty?).join(" · "),
      "date" => invoice.fetch("invoiceDate"),
      "gstAmount" => InvoiceCalculation.format_monetary_value(invoice.fetch("gstAmount"), "GSTR-2B GST"),
      "totalAmount" => InvoiceCalculation.format_monetary_value(invoice.fetch("invoiceValue"), "GSTR-2B invoice value"),
      "status" => "found",
      "foundInMonth" => period_label,
      "supplierGstin" => invoice.fetch("supplierGstin"),
      "supplierName" => invoice.fetch("supplierName"),
      "invoiceNumber" => invoice.fetch("invoiceNumber"),
      "gstr2bDocumentKey" => invoice.fetch("documentKey"),
      "matchSource" => "gstr2b",
      "matchMethod" => "imported",
      "itcEligibility" => invoice.fetch("itcAvailable") ? "eligible" : "ineligible",
      "createdAt" => now.iso8601,
      "updatedAt" => now.iso8601
    }
  end

  def summary(month_label, all_bills)
    start_date, end_date = InvoiceCalculation.parse_month(month_label)
    original = all_bills.select { |bill| (start_date..end_date).cover?(Date.iso8601(bill.fetch("date"))) }
    available = all_bills.select { |bill| bill.fetch("status") == "found" && bill["itcEligibility"] != "ineligible" && effective_month(bill) == month_label }
    found = original.select { |bill| bill.fetch("status") == "found" }
    resolved_later = found.select { |bill| effective_month(bill) != month_label }
    carried_in = available.select { |bill| Date.iso8601(bill.fetch("date")) < start_date }
    pending = all_bills.select do |bill|
      Date.iso8601(bill.fetch("date")) <= end_date && bill.fetch("status") == "missing"
    end
    {
      "month" => month_label,
      "quarterLabel" => quarter_label(month_label),
      "normalGst" => original.sum { |bill| decimal(bill.fetch("gstAmount"), "gstAmount") }.round(2).to_f,
      "effectiveGst" => available.sum { |bill| decimal(bill.fetch("gstAmount"), "gstAmount") }.round(2).to_f,
      "totalAmount" => original.sum { |bill| decimal(bill.fetch("totalAmount"), "totalAmount") }.round(2).to_f,
      "invoiceCount" => original.length,
      "foundCount" => found.length,
      "missingCount" => original.length - found.length,
      "carriedInCount" => carried_in.length,
      "carriedInGst" => carried_in.sum { |bill| decimal(bill.fetch("gstAmount"), "gstAmount") }.round(2).to_f,
      "resolvedLaterCount" => resolved_later.length,
      "ineligibleCount" => original.count { |bill| bill["itcEligibility"] == "ineligible" },
      "pendingCount" => pending.length,
      "pendingGst" => pending.sum { |bill| decimal(bill.fetch("gstAmount"), "gstAmount") }.round(2).to_f
    }
  end

  def effective_month(bill)
    return nil unless bill.fetch("status") == "found"
    return nil if bill["itcEligibility"] == "ineligible"
    bill["foundInMonth"] || Date.iso8601(bill.fetch("date")).strftime("%B %Y")
  end

  def quarter_start(month_label)
    date = InvoiceCalculation.parse_month(month_label).first
    Date.new(date.year, ((date.month - 1) / 3) * 3 + 1, 1)
  end

  def normalize_invoice_number(value)
    value.to_s.upcase.gsub(/[^A-Z0-9]/, "")
  end

  def quarter_label(month_label)
    date = InvoiceCalculation.parse_month(month_label).first
    start_month = ((date.month - 1) / 3) * 3 + 1
    start_date = Date.new(date.year, start_month, 1)
    end_date = start_date >> 2
    "#{start_date.strftime('%B')}-#{end_date.strftime('%B %Y')}"
  end

  def validated_attributes(month_label, label, date_value, gst_amount, total_amount, status, found_month)
    clean_label = label.to_s.strip
    raise ConfigError, "Bill label must not be empty" if clean_label.empty?
    date = begin
      Date.iso8601(date_value.to_s)
    rescue ArgumentError
      raise ConfigError, "Bill date must use YYYY-MM-DD"
    end
    start_date, end_date = InvoiceCalculation.parse_month(month_label)
    raise ConfigError, "Bill date must be in #{month_label}" unless (start_date..end_date).cover?(date)
    gst = InvoiceCalculation.parse_monetary_input(gst_amount, "GST amount")
    total = InvoiceCalculation.parse_monetary_input(total_amount, "total amount")
    raise ConfigError, "GST amount must not be negative" if gst.negative?
    raise ConfigError, "Total amount must be greater than zero" unless total.positive?
    raise ConfigError, "GST amount must not exceed total amount" if gst > total
    raise ConfigError, "Bill status must be found or missing" unless STATUSES.include?(status)
    attributes = {
      "label" => clean_label,
      "date" => date.iso8601,
      "gstAmount" => InvoiceCalculation.format_monetary_value(gst, "GST amount"),
      "totalAmount" => InvoiceCalculation.format_monetary_value(total, "total amount"),
      "status" => status
    }
    if status == "found"
      effective_label = found_month.to_s.strip.empty? ? date.strftime("%B %Y") : found_month
      found_start = InvoiceCalculation.parse_month(effective_label).first
      raise ConfigError, "Found period cannot be before the bill month" if found_start < start_date
      attributes["foundInMonth"] = found_start.strftime("%B %Y")
    end
    attributes
  end

  def decimal(value, label)
    InvoiceCalculation.decimal_value(value, label)
  end

  def update_state(config)
    store = InvoiceStore.new(config)
    FileUtils.mkdir_p(store.root)
    File.open(File.join(store.root, ".gst-input-bills.lock"), File::RDWR | File::CREAT, 0600) do |lock|
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
