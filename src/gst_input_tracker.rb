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
    bills = read_state(config).fetch("bills").select do |bill|
      (start_date..end_date).cover?(Date.iso8601(bill.fetch("date")))
    end.sort_by { |bill| [bill.fetch("date"), bill.fetch("label")] }
    summary(month_label, bills).merge("bills" => bills)
  end

  def month_summaries(config, month_labels)
    state = read_state(config)
    month_labels.map do |month_label|
      start_date, end_date = InvoiceCalculation.parse_month(month_label)
      bills = state.fetch("bills").select do |bill|
        (start_date..end_date).cover?(Date.iso8601(bill.fetch("date")))
      end
      summary(month_label, bills)
    end
  end

  def tracked_months(config)
    read_state(config).fetch("bills").map do |bill|
      Date.iso8601(bill.fetch("date")).strftime("%B %Y")
    end.uniq
  end

  def add(config, month_label, label:, date:, gst_amount:, total_amount:, status: "missing", now: Time.now.utc)
    attributes = validated_attributes(month_label, label, date, gst_amount, total_amount, status)
    update_state(config) do |state|
      state.fetch("bills") << attributes.merge(
        "id" => SecureRandom.uuid,
        "createdAt" => now.iso8601,
        "updatedAt" => now.iso8601
      )
    end
    month(config, month_label)
  end

  def update(config, month_label, id, label:, date:, gst_amount:, total_amount:, status:, now: Time.now.utc)
    attributes = validated_attributes(month_label, label, date, gst_amount, total_amount, status)
    update_state(config) do |state|
      bill = state.fetch("bills").find { |candidate| candidate["id"] == id }
      raise ConfigError, "Unknown GST input bill: #{id}" unless bill
      bill.replace(bill.slice("id", "createdAt").merge(attributes).merge("updatedAt" => now.iso8601))
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

  def summary(month_label, bills)
    normal_gst = bills.sum { |bill| decimal(bill.fetch("gstAmount"), "gstAmount") }
    found = bills.select { |bill| bill.fetch("status") == "found" }
    {
      "month" => month_label,
      "quarterLabel" => quarter_label(month_label),
      "normalGst" => normal_gst.round(2).to_f,
      "effectiveGst" => found.sum { |bill| decimal(bill.fetch("gstAmount"), "gstAmount") }.round(2).to_f,
      "totalAmount" => bills.sum { |bill| decimal(bill.fetch("totalAmount"), "totalAmount") }.round(2).to_f,
      "invoiceCount" => bills.length,
      "foundCount" => found.length,
      "missingCount" => bills.length - found.length
    }
  end

  def quarter_label(month_label)
    date = InvoiceCalculation.parse_month(month_label).first
    start_month = ((date.month - 1) / 3) * 3 + 1
    start_date = Date.new(date.year, start_month, 1)
    end_date = start_date >> 2
    "#{start_date.strftime('%B')}-#{end_date.strftime('%B %Y')}"
  end

  def validated_attributes(month_label, label, date_value, gst_amount, total_amount, status)
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
    {
      "label" => clean_label,
      "date" => date.iso8601,
      "gstAmount" => InvoiceCalculation.format_monetary_value(gst, "GST amount"),
      "totalAmount" => InvoiceCalculation.format_monetary_value(total, "total amount"),
      "status" => status
    }
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
