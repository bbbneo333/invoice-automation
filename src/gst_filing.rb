require "date"
require "digest"
require "fileutils"
require "json"
require "time"
require_relative "invoice_calculation"
require_relative "invoice_store"
require_relative "gst_input_tracker"
require_relative "gstr2b_importer"
require_relative "ims_importer"

module GstFiling
  ConfigError = InvoiceCalculation::ConfigError
  SCHEMES = %w[monthly qrmp].freeze
  IFF_SETTINGS = %w[disabled enabled].freeze
  STATE_VERSION = 1
  GSTR3B_DAY_22_STATE_CODES = %w[22 23 24 25 26 27 29 30 31 32 33 34 35 36 37].freeze

  module_function

  def default_settings(config)
    raw = config.fetch("gstFiling", {})
    raise ConfigError, "gstFiling must be an object" unless raw.is_a?(Hash)

    scheme = raw.fetch("scheme", "monthly")
    iff = raw.fetch("iff", "disabled")
    validate_settings(scheme, iff)
  end

  def validate_settings(scheme, iff)
    raise ConfigError, "gstFiling.scheme must be monthly or qrmp" unless SCHEMES.include?(scheme)
    raise ConfigError, "gstFiling.iff must be disabled or enabled" unless IFF_SETTINGS.include?(iff)
    if scheme == "monthly" && iff != "disabled"
      raise ConfigError, "gstFiling.iff can be enabled only when gstFiling.scheme is qrmp"
    end
    { "scheme" => scheme, "iff" => iff }
  end

  def settings(config, period: nil)
    defaults = default_settings(config)
    return defaults unless period

    details = quarter(period)
    inherited = read_state(config).fetch("preferences").values.select do |entry|
      entry.is_a?(Hash) && entry["quarterStart"] && month_start(entry.fetch("quarterStart")) <= details.fetch("startDate")
    end.max_by { |entry| month_start(entry.fetch("quarterStart")) }
    inherited ? validate_settings(inherited.fetch("scheme"), inherited.fetch("iff")) : defaults
  end

  def month_start(month_label)
    InvoiceCalculation.parse_month(month_label).first
  end

  def quarter(value)
    date = value.is_a?(Date) ? value : month_start(value)
    start_month = ((date.month - 1) / 3) * 3 + 1
    start_date = Date.new(date.year, start_month, 1)
    months = 3.times.map { |offset| start_date >> offset }
    finish_date = (start_date >> 3) - 1
    {
      "startDate" => start_date,
      "endDate" => finish_date,
      "months" => months,
      "monthLabels" => months.map { |month| month.strftime("%B %Y") },
      "label" => "#{months.first.strftime('%B')}-#{months.last.strftime('%B %Y')}",
      "endMonth" => months.last.strftime("%B %Y")
    }
  end

  def iff_eligible?(month_label)
    date = month_start(month_label)
    quarter(date).fetch("months").first(2).include?(date)
  end

  def period_key(month_label)
    month_start(month_label).strftime("%m%Y")
  end

  def state_path(config)
    File.join(InvoiceStore.new(config).root, "gst-filings.json")
  end

  def read_state(config)
    path = state_path(config)
    return blank_state unless File.file?(path)

    state = JSON.parse(File.read(path))
    unless state.is_a?(Hash) && state["version"] == STATE_VERSION && state["iff"].is_a?(Hash)
      raise ConfigError, "gst-filings.json has an unsupported format"
    end
    state["gstr1"] ||= {}
    raise ConfigError, "gst-filings.json has an unsupported format" unless state["gstr1"].is_a?(Hash)
    state["preferences"] ||= {}
    raise ConfigError, "gst-filings.json has an unsupported format" unless state["preferences"].is_a?(Hash)
    state["tasks"] ||= {}
    raise ConfigError, "gst-filings.json has an unsupported format" unless state["tasks"].is_a?(Hash)
    state
  rescue JSON::ParserError => error
    raise ConfigError, "Invalid gst-filings.json: #{error.message}"
  end

  def blank_state
    { "version" => STATE_VERSION, "iff" => {}, "gstr1" => {}, "preferences" => {}, "tasks" => {} }
  end

  def mark_task_complete(config, month_label, task, now: Time.now.utc)
    configured = settings(config, period: month_label)
    valid = case task
    when "pmt06_review", "pmt06"
      configured.fetch("scheme") == "qrmp" && iff_eligible?(month_label)
    when "gstr3b_review", "gstr3b"
      configured.fetch("scheme") == "monthly" || !iff_eligible?(month_label)
    else
      false
    end
    raise ConfigError, "#{task} is not applicable to #{month_label}" unless valid

    state = read_state(config)
    if task == "pmt06" && !task_complete?(state, month_label, "pmt06_review")
      raise ConfigError, "Review the #{month_label} GST liability before marking PMT-06 paid"
    end
    if task == "gstr3b_review"
      raise ConfigError, "Mark GSTR-1 filed before reviewing GSTR-3B" unless gstr1_filed?(config, month_label)
      raise ConfigError, "Import GSTR-2B before reviewing GSTR-3B" unless Gstr2bImporter.latest(config, month_label)
    end
    if task == "gstr3b"
      raise ConfigError, "Mark GSTR-1 filed before marking GSTR-3B filed" unless gstr1_filed?(config, month_label)
      raise ConfigError, "Import GSTR-2B before marking GSTR-3B filed" unless Gstr2bImporter.latest(config, month_label)
      unless task_complete?(state, month_label, "gstr3b_review")
        raise ConfigError, "Review the final GST balance before marking GSTR-3B filed"
      end
    end

    update_state(config) do |state|
      key = "#{period_key(month_label)}:#{task}"
      state.fetch("tasks")[key] ||= {
        "month" => month_label,
        "task" => task,
        "status" => "complete",
        "completedAt" => now.iso8601
      }
    end.fetch("tasks").fetch("#{period_key(month_label)}:#{task}")
  end

  def task_complete?(state, month_label, task)
    state.dig("tasks", "#{period_key(month_label)}:#{task}", "status") == "complete"
  end

  def set_preference(config, quarter_period, scheme, iff, now: Time.now.utc)
    configured = validate_settings(scheme, iff)
    details = quarter(quarter_period)
    update_state(config) do |state|
      lock = preference_lock(state, details)
      if lock.fetch("locked")
        current = settings_from_state(config, state, details.fetch("startDate"))
        unless current == configured
          raise ConfigError, "#{details.fetch('label')} filing preference is locked because #{lock.fetch('reason')}"
        end
      end
      state.fetch("preferences")[period_key(details.fetch("startDate").strftime("%B %Y"))] = {
        "quarterStart" => details.fetch("startDate").strftime("%B %Y"),
        "quarterLabel" => details.fetch("label"),
        "scheme" => configured.fetch("scheme"),
        "iff" => configured.fetch("iff"),
        "savedAt" => now.iso8601
      }
    end.fetch("preferences").fetch(period_key(details.fetch("startDate").strftime("%B %Y")))
  end

  def settings_from_state(config, state, period)
    details = quarter(period)
    inherited = state.fetch("preferences").values.select do |entry|
      entry.is_a?(Hash) && entry["quarterStart"] && month_start(entry.fetch("quarterStart")) <= details.fetch("startDate")
    end.max_by { |entry| month_start(entry.fetch("quarterStart")) }
    inherited ? validate_settings(inherited.fetch("scheme"), inherited.fetch("iff")) : default_settings(config)
  end

  def preference_lock(state, details)
    keys = details.fetch("monthLabels").map { |month| period_key(month) }
    entries = keys.map { |key| state.fetch("iff")[key] }.compact + keys.map { |key| state.fetch("gstr1")[key] }.compact
    completed_task = state.fetch("tasks", {}).values.any? do |entry|
      entry.is_a?(Hash) && entry["month"] && details.fetch("monthLabels").include?(entry.fetch("month")) && entry["status"] == "complete"
    end
    filed = entries.any? { |entry| entry["status"] == "filed" }
    generated = entries.any? { |entry| entry["status"] == "generated" }
    {
      "locked" => filed || generated || completed_task,
      "reason" => if filed
        "a filing is already marked filed"
      elsif generated
        "a GST JSON has already been generated"
      elsif completed_task
        "a GST checklist action is already marked complete"
      end
    }
  end

  def iff_entry(config, month_label)
    read_state(config).fetch("iff").fetch(period_key(month_label), nil)
  end

  def iff_filed?(config, month_label, invoice_no = nil)
    entry = iff_entry(config, month_label)
    return false unless entry.is_a?(Hash) && entry["status"] == "filed"
    invoice_no.nil? || entry.fetch("invoiceNumbers", []).include?(invoice_no)
  end

  def gstr1_entry(config, filing_period_label)
    read_state(config).fetch("gstr1").fetch(period_key(filing_period_label), nil)
  end

  def gstr1_filed?(config, filing_period_label)
    entry = gstr1_entry(config, filing_period_label)
    entry.is_a?(Hash) && entry["status"] == "filed"
  end

  def snapshot_digest(snapshot)
    Digest::SHA256.hexdigest(JSON.generate(snapshot))
  end

  def iff_filed_snapshot?(config, month_label, snapshot)
    entry = iff_entry(config, month_label)
    return false unless entry.is_a?(Hash) && entry["status"] == "filed"
    number = snapshot.fetch("invoiceNo")
    return false unless entry.fetch("invoiceNumbers", []).include?(number)
    expected = entry.fetch("snapshotDigests", {})[number]
    unless expected == snapshot_digest(snapshot)
      raise ConfigError, "Invoice #{number} changed after the #{month_label} IFF was marked filed"
    end
    true
  end

  def record_iff_generated(config, month_label, snapshots, output_path, now: Time.now.utc)
    update_state(config) do |state|
      key = period_key(month_label)
      existing = state.fetch("iff")[key]
      raise ConfigError, "IFF for #{month_label} is already marked filed" if existing && existing["status"] == "filed"
      state.fetch("iff")[key] = {
        "month" => month_label,
        "status" => "generated",
        "invoiceNumbers" => snapshots.map { |snapshot| snapshot.fetch("invoiceNo") },
        "snapshotDigests" => snapshots.to_h { |snapshot| [snapshot.fetch("invoiceNo"), snapshot_digest(snapshot)] },
        "generatedAt" => now.iso8601,
        "outputPath" => relative_output_path(config, output_path)
      }
    end
  end

  def mark_iff_filed(config, month_label, now: Time.now.utc)
    require_qrmp_iff!(config, month_label)
    raise ConfigError, "IFF is available only for the first two months of a quarter" unless iff_eligible?(month_label)
    update_state(config) do |state|
      key = period_key(month_label)
      entry = state.fetch("iff")[key]
      raise ConfigError, "Generate the #{month_label} IFF JSON before marking it filed" unless entry
      validate_entry_snapshots!(config, entry)
      quarter_key = period_key(quarter(month_label).fetch("endMonth"))
      quarterly_return = state.fetch("gstr1")[quarter_key]
      if quarterly_return && quarterly_return["status"] == "filed"
        raise ConfigError, "The quarter's GSTR-1 is already filed; #{month_label} IFF cannot be marked filed now"
      end
      state.fetch("gstr1").delete(quarter_key) if quarterly_return && quarterly_return["status"] == "generated"
      entry["status"] = "filed"
      entry["filedAt"] = now.iso8601
    end.fetch("iff").fetch(period_key(month_label))
  end

  def record_gstr1_generated(config, filing_period_label, snapshots, output_path, kind:, now: Time.now.utc)
    update_state(config) do |state|
      key = period_key(filing_period_label)
      existing = state.fetch("gstr1")[key]
      raise ConfigError, "GSTR-1 for #{filing_period_label} is already marked filed" if existing && existing["status"] == "filed"
      state.fetch("gstr1")[key] = {
        "filingPeriod" => filing_period_label,
        "kind" => kind,
        "status" => "generated",
        "invoiceNumbers" => snapshots.map { |snapshot| snapshot.fetch("invoiceNo") },
        "snapshotDigests" => snapshots.to_h { |snapshot| [snapshot.fetch("invoiceNo"), snapshot_digest(snapshot)] },
        "generatedAt" => now.iso8601,
        "outputPath" => relative_output_path(config, output_path)
      }
    end
  end

  def mark_gstr1_filed(config, filing_period_label, now: Time.now.utc)
    update_state(config) do |state|
      key = period_key(filing_period_label)
      entry = state.fetch("gstr1")[key]
      raise ConfigError, "Generate the #{filing_period_label} GSTR-1 JSON before marking it filed" unless entry
      validate_entry_snapshots!(config, entry)
      entry["status"] = "filed"
      entry["filedAt"] = now.iso8601
    end.fetch("gstr1").fetch(period_key(filing_period_label))
  end

  def validate_entry_snapshots!(config, entry)
    current = InvoiceStore.new(config).records.each_with_object({}) do |record, snapshots|
      snapshot = record["snapshot"]
      snapshots[snapshot.fetch("invoiceNo")] = snapshot if snapshot.is_a?(Hash) && snapshot["version"] == 1
    end
    entry.fetch("snapshotDigests", {}).each do |number, expected|
      snapshot = current[number]
      unless snapshot && snapshot_digest(snapshot) == expected
        raise ConfigError, "Invoice #{number} changed after this GST JSON was generated; regenerate it before marking it filed"
      end
    end
    true
  end

  def assert_invoice_editable!(config, snapshot)
    invoice_no = snapshot.fetch("invoiceNo")
    invoice_month = Date.iso8601(snapshot.fetch("invoiceDate")).strftime("%B %Y")
    if iff_filed?(config, invoice_month, invoice_no)
      raise ConfigError, "Invoice #{invoice_no} is locked because the #{invoice_month} IFF is filed"
    end

    filed_return = read_state(config).fetch("gstr1").values.find do |entry|
      entry.is_a?(Hash) && entry["status"] == "filed" && entry.fetch("invoiceNumbers", []).include?(invoice_no)
    end
    if filed_return
      raise ConfigError, "Invoice #{invoice_no} is locked because the #{filed_return.fetch('filingPeriod')} GSTR-1 is filed"
    end
    true
  end

  def dashboard(config, now: Time.now)
    state = read_state(config)
    gstr2b_imports = Gstr2bImporter.read_state(config).fetch("imports")
    ims_imports = ImsImporter.read_state(config).fetch("imports")
    snapshots = InvoiceStore.new(config).records.each_with_object([]) do |record, result|
      snapshot = record["snapshot"]
      result << snapshot if snapshot.is_a?(Hash) && snapshot["version"] == 1 && snapshot.dig("gst", "enabled") == true
    end
    quarter_starts = relevant_quarter_starts(config, snapshots, state, now)
    input_months = GstInputTracker.month_summaries(
      config, quarter_starts.flat_map { |start_date| quarter(start_date).fetch("monthLabels") }
    )
    periods = quarter_starts.flat_map do |start_date|
      dashboard_quarter_periods(config, snapshots, state, now, start_date, input_months, gstr2b_imports, ims_imports)
    end
    preferences = quarter_starts.map { |start_date| dashboard_preference(config, state, start_date) }
    configured = settings_from_state(config, state, now.to_date)
    {
      "scheme" => configured.fetch("scheme"),
      "iffEnabled" => configured.fetch("iff") == "enabled",
      "defaultPeriod" => default_dashboard_period(periods, now),
      "periods" => periods,
      "preferences" => preferences,
      "inputMonths" => input_months
    }
  end

  def relevant_quarter_starts(config, snapshots, state, now)
    current = quarter(now.to_date)
    quarter_starts = snapshots.map { |snapshot| quarter(Date.iso8601(snapshot.fetch("invoiceDate"))).fetch("startDate") }
    quarter_starts << current.fetch("startDate")
    state.fetch("iff").values.each do |entry|
      quarter_starts << quarter(entry.fetch("month")).fetch("startDate") if entry.is_a?(Hash) && entry["month"]
    end
    state.fetch("gstr1").values.each do |entry|
      quarter_starts << quarter(entry.fetch("filingPeriod")).fetch("startDate") if entry.is_a?(Hash) && entry["filingPeriod"]
    end
    state.fetch("preferences").values.each do |entry|
      quarter_starts << quarter(entry.fetch("quarterStart")).fetch("startDate") if entry.is_a?(Hash) && entry["quarterStart"]
    end
    GstInputTracker.tracked_months(config).each do |month|
      quarter_starts << quarter(month).fetch("startDate")
    end
    Gstr2bImporter.tracked_periods(config).each do |month|
      quarter_starts << quarter(month).fetch("startDate")
    end
    ImsImporter.tracked_periods(config).each do |month|
      quarter_starts << quarter(month).fetch("startDate")
    end
    quarter_starts.uniq.sort.reverse
  end

  def dashboard_preference(config, state, start_date)
    details = quarter(start_date)
    configured = settings_from_state(config, state, start_date)
    lock = preference_lock(state, details)
    {
      "quarterStartMonth" => details.fetch("startDate").strftime("%B %Y"),
      "quarterLabel" => details.fetch("label"),
      "scheme" => configured.fetch("scheme"),
      "iffEnabled" => configured.fetch("iff") == "enabled",
      "locked" => lock.fetch("locked"),
      "lockReason" => lock.fetch("reason")
    }
  end

  def dashboard_quarter_periods(config, snapshots, state, now, start_date, input_months, gstr2b_imports, ims_imports)
    details = quarter(start_date)
    configured = settings_from_state(config, state, start_date)
    now_month = Date.new(now.year, now.month, 1)
    details.fetch("months").each_with_index.map do |month, index|
      month_label = month.strftime("%B %Y")
      gstr2b_entry = gstr2b_imports[period_key(month_label)]
      ims_entry = ims_imports[period_key(month_label)]
      if configured.fetch("scheme") == "qrmp" && index < 2
        selected = snapshots_in_month(snapshots, month)
        entry = state.fetch("iff")[period_key(month_label)]
        dashboard_period(
          config, month_label, details.fetch("label"), "iff", entry, selected, configured, state, input_months, gstr2b_entry, ims_entry, now,
          action_title: "IFF", can_generate: configured.fetch("iff") == "enabled" && month <= now_month && !selected.empty?
        )
      elsif configured.fetch("scheme") == "qrmp"
        selected = snapshots.select { |snapshot| (details.fetch("startDate")..details.fetch("endDate")).cover?(Date.iso8601(snapshot.fetch("invoiceDate"))) }
        entry = state.fetch("gstr1")[period_key(month_label)]
        dashboard_period(
          config, month_label, details.fetch("label"), "quarterlyGstr1", entry, selected, configured, state, input_months, gstr2b_entry, ims_entry, now,
          action_title: "Quarterly GSTR-1", can_generate: month <= now_month && !selected.empty?
        )
      else
        selected = snapshots_in_month(snapshots, month)
        entry = state.fetch("gstr1")[period_key(month_label)]
        dashboard_period(
          config, month_label, details.fetch("label"), "monthlyGstr1", entry, selected, configured, state, input_months, gstr2b_entry, ims_entry, now,
          action_title: "GSTR-1", can_generate: month <= now_month && !selected.empty?
        )
      end
    end
  end

  def snapshots_in_month(snapshots, month)
    snapshots.select do |snapshot|
      date = Date.iso8601(snapshot.fetch("invoiceDate"))
      date.year == month.year && date.month == month.month
    end
  end

  def dashboard_period(config, month_label, quarter_label, kind, entry, snapshots, configured, state, input_months, gstr2b_entry, ims_entry, now, action_title:, can_generate:)
    status = entry&.fetch("status", nil) || "pending"
    validate_entry_snapshots!(config, entry) if status == "filed"
    period = {
      "month" => month_label,
      "quarterLabel" => quarter_label,
      "scheme" => configured.fetch("scheme"),
      "iffEnabled" => configured.fetch("iff") == "enabled",
      "kind" => kind,
      "actionTitle" => action_title,
      "status" => status,
      "locked" => status == "filed",
      "canGenerate" => can_generate && status != "filed",
      "outputPath" => entry && absolute_output_path(config, entry["outputPath"]),
      "generatedAt" => entry && entry["generatedAt"],
      "filedAt" => entry && entry["filedAt"],
      "amounts" => dashboard_amounts(snapshots),
      "invoices" => snapshots.sort_by { |snapshot| Date.iso8601(snapshot.fetch("invoiceDate")) }.map { |snapshot| dashboard_invoice(snapshot) }
    }
    period["checklist"] = dashboard_checklist(config, period, snapshots, state, input_months, gstr2b_entry, ims_entry, now)
    period
  end

  def dashboard_checklist(config, period, snapshots, state, input_months, gstr2b_entry, ims_entry, now)
    month_label = period.fetch("month")
    quarterly = period.fetch("kind") == "quarterlyGstr1"
    relevant_inputs = if quarterly
      input_months.select { |summary| summary.fetch("quarterLabel") == period.fetch("quarterLabel") }
    else
      input_months.select { |summary| summary.fetch("month") == month_label }
    end
    input = combine_input_summaries(relevant_inputs)
    input_title = quarterly ? "Record #{period.fetch('quarterLabel')} purchase bills" : "Record #{month_label} purchase bills"
    input_status = if input.fetch("invoiceCount").zero? && input.fetch("carriedInCount").zero? && input.fetch("missingCount").zero?
      "pending"
    elsif input.fetch("missingCount").zero?
      "complete"
    else
      "attention"
    end

    due_date = return_due_date(period.fetch("kind"), month_label)
    generate_status = period.fetch("status") == "pending" ? (period.fetch("canGenerate") ? "ready" : "blocked") : "complete"
    file_status = period.fetch("status") == "filed" ? "complete" : (period.fetch("status") == "generated" ? "ready" : "blocked")
    return_label = period.fetch("kind") == "iff" ? "#{month_label} IFF" : (quarterly ? "#{period.fetch('quarterLabel')} GSTR-1" : "#{month_label} GSTR-1")
    items = [
      {
        "id" => "input",
        "title" => input_title,
        "status" => input_status,
        "action" => "manageBills",
        "invoiceCount" => input.fetch("invoiceCount"),
        "foundCount" => input.fetch("foundCount"),
        "missingCount" => input.fetch("missingCount"),
        "carriedInCount" => input.fetch("carriedInCount"),
        "resolvedLaterCount" => input.fetch("resolvedLaterCount"),
        "ineligibleCount" => input.fetch("ineligibleCount"),
        "imsSeenCount" => input.fetch("imsSeenCount"),
        "imsAwaiting2bCount" => input.fetch("imsAwaiting2bCount"),
        "gstAmount" => input.fetch("normalGst"),
        "effectiveInputGst" => input.fetch("effectiveGst")
      },
      {
        "id" => "generate",
        "title" => "Generate #{return_label} JSON",
        "status" => generate_status,
        "action" => period.fetch("status") == "pending" ? "generate" : "viewJson",
        "dueDate" => due_date&.iso8601,
        "invoiceCount" => period.dig("amounts", "invoiceCount"),
        "taxableValue" => period.dig("amounts", "taxableValue"),
        "gstAmount" => period.dig("amounts", "outputTax")
      },
      {
        "id" => "file",
        "title" => "Upload and file #{return_label} on the GST portal",
        "status" => file_status,
        "action" => "markFiled",
        "dueDate" => due_date&.iso8601,
        "generatedAt" => period["generatedAt"],
        "completedAt" => period["filedAt"]
      }
    ]

    ims_summary = ims_entry&.fetch("summary", {}) || {}
    ims_recommended_date = ims_review_date(month_label)
    ims_imported_date = ims_entry && Date.parse(ims_entry.fetch("importedAt"))
    ims_needs_refresh = ims_imported_date && ims_imported_date < ims_recommended_date && now.to_date >= ims_recommended_date
    ims_title = if now.to_date < ims_recommended_date
      "Check IMS for #{month_label} purchase bills"
    else
      "Download the current IMS B2B CSV and reconcile #{month_label} purchase bills"
    end
    ims_item = {
      "id" => "imsImport",
      "title" => ims_title,
      "status" => ims_needs_refresh ? "attention" : (ims_entry ? "complete" : (month_start(month_label) <= Date.new(now.year, now.month, 1) ? "ready" : "blocked")),
      "action" => ims_needs_refresh || !ims_entry ? "importIms" : "viewIms",
      "recommendedDate" => ims_recommended_date.iso8601,
      "completedAt" => ims_entry && ims_entry["importedAt"]
    }
    ims_item.merge!({
      "portalInvoiceCount" => ims_summary.fetch("portalInvoiceCount", 0),
      "matchedCount" => ims_summary.fetch("matchedCount", 0),
      "importedCount" => ims_summary.fetch("importedCount", 0),
      "ambiguousCount" => ims_summary.fetch("ambiguousCount", 0),
      "missingLocalCount" => ims_summary.fetch("missingLocalCount", 0),
      "acceptedCount" => ims_summary.fetch("acceptedCount", 0),
      "rejectedCount" => ims_summary.fetch("rejectedCount", 0),
      "pendingCount" => ims_summary.fetch("pendingCount", 0),
      "noActionCount" => ims_summary.fetch("noActionCount", 0),
      "newCount" => ims_summary.fetch("newCount", 0),
      "changedCount" => ims_summary.fetch("changedCount", 0),
      "removedCount" => ims_summary.fetch("removedCount", 0),
      "gstAmount" => ims_summary.fetch("portalGst", 0)
    }) if ims_entry
    items.insert(1, ims_item)

    output_tax = period.dig("amounts", "outputTax")
    estimated_balance = (output_tax - input.fetch("effectiveGst")).round(2)
    if period.fetch("kind") == "iff"
      payment_complete = task_complete?(state, month_label, "pmt06")
      review_complete = payment_complete || task_complete?(state, month_label, "pmt06_review")
      items << {
        "id" => "paymentReview",
        "title" => "Review #{month_label} GST liability and generate the PMT-06 challan on the GST portal",
        "status" => review_complete ? "complete" : "ready",
        "action" => "markPmt06Reviewed",
        "dueDate" => payment_due_date(month_label).iso8601,
        "gstAmount" => output_tax,
        "effectiveInputGst" => input.fetch("effectiveGst"),
        "estimatedBalance" => estimated_balance,
        "completedAt" => state.dig("tasks", "#{period_key(month_label)}:pmt06_review", "completedAt")
      }
      items << {
        "id" => "payment",
        "title" => "Pay the #{month_label} PMT-06 challan on the GST portal",
        "status" => payment_complete ? "complete" : (review_complete ? "ready" : "blocked"),
        "action" => "markPmt06Paid",
        "dueDate" => payment_due_date(month_label).iso8601,
        "gstAmount" => output_tax,
        "effectiveInputGst" => input.fetch("effectiveGst"),
        "estimatedBalance" => estimated_balance,
        "completedAt" => state.dig("tasks", "#{period_key(month_label)}:pmt06", "completedAt")
      }
    elsif quarterly || period.fetch("kind") == "monthlyGstr1"
      filing_complete = task_complete?(state, month_label, "gstr3b")
      review_complete = filing_complete || task_complete?(state, month_label, "gstr3b_review")
      return_filed = period.fetch("status") == "filed"
      gstr2b_available = gstr2b_available_date(month_label)
      gstr2b_complete = !gstr2b_entry.nil?
      gstr2b_summary = gstr2b_entry&.fetch("summary", {}) || {}
      gstr2b_label = quarterly ? period.fetch("quarterLabel") : month_label
      gstr2b_item = {
        "id" => "gstr2bImport",
        "title" => "Import and reconcile #{gstr2b_label} GSTR-2B",
        "status" => gstr2b_complete ? "complete" : (now.to_date >= gstr2b_available ? "ready" : "blocked"),
        "action" => gstr2b_complete ? "viewGstr2b" : "importGstr2b",
        "availableDate" => gstr2b_available.iso8601,
        "completedAt" => gstr2b_entry && gstr2b_entry["importedAt"]
      }
      gstr2b_item.merge!({
        "portalInvoiceCount" => gstr2b_summary.fetch("portalInvoiceCount", 0),
        "matchedCount" => gstr2b_summary.fetch("matchedCount", 0),
        "importedCount" => gstr2b_summary.fetch("importedCount", 0),
        "ambiguousCount" => gstr2b_summary.fetch("ambiguousCount", 0),
        "missingLocalCount" => gstr2b_summary.fetch("missingLocalCount", 0),
        "previousBillsResolvedCount" => gstr2b_summary.fetch("previousBillsResolvedCount", 0),
        "gstAmount" => gstr2b_summary.fetch("portalGst", 0),
        "effectiveInputGst" => gstr2b_summary.fetch("representedGst", 0)
      }) if gstr2b_complete
      items << gstr2b_item
      items << {
        "id" => "gstr3bReview",
        "title" => quarterly ? "Review GSTR-2B credit and the final GSTR-3B balance on the GST portal" : "Review input credit and the final GSTR-3B balance on the GST portal",
        "status" => review_complete ? "complete" : (return_filed && gstr2b_complete ? "ready" : "blocked"),
        "action" => "markGstr3bReviewed",
        "dueDate" => gstr3b_due_date(config, month_label, snapshots, quarterly: quarterly)&.iso8601,
        "gstAmount" => output_tax,
        "effectiveInputGst" => input.fetch("effectiveGst"),
        "estimatedBalance" => estimated_balance,
        "completedAt" => state.dig("tasks", "#{period_key(month_label)}:gstr3b_review", "completedAt")
      }
      items << {
        "id" => "gstr3b",
        "title" => "Pay any remaining balance and file GSTR-3B on the GST portal",
        "status" => filing_complete ? "complete" : (return_filed && gstr2b_complete && review_complete ? "ready" : "blocked"),
        "action" => "markGstr3bFiled",
        "dueDate" => gstr3b_due_date(config, month_label, snapshots, quarterly: quarterly)&.iso8601,
        "gstAmount" => output_tax,
        "effectiveInputGst" => input.fetch("effectiveGst"),
        "estimatedBalance" => estimated_balance,
        "completedAt" => state.dig("tasks", "#{period_key(month_label)}:gstr3b", "completedAt")
      }
    end
    items
  end

  def combine_input_summaries(summaries)
    latest = summaries.max_by { |summary| month_start(summary.fetch("month")) }
    {
      "normalGst" => summaries.sum { |summary| summary.fetch("normalGst") }.round(2),
      "effectiveGst" => summaries.sum { |summary| summary.fetch("effectiveGst") }.round(2),
      "invoiceCount" => summaries.sum { |summary| summary.fetch("invoiceCount") },
      "foundCount" => summaries.sum { |summary| summary.fetch("foundCount") },
      "missingCount" => latest&.fetch("pendingCount", 0) || 0,
      "carriedInCount" => summaries.sum { |summary| summary.fetch("carriedInCount", 0) },
      "resolvedLaterCount" => summaries.sum { |summary| summary.fetch("resolvedLaterCount", 0) },
      "ineligibleCount" => summaries.sum { |summary| summary.fetch("ineligibleCount", 0) },
      "imsSeenCount" => latest&.fetch("imsSeenCount", 0) || 0,
      "imsAwaiting2bCount" => latest&.fetch("imsAwaiting2bCount", 0) || 0
    }
  end

  def return_due_date(kind, month_label)
    month = month_start(month_label) >> 1
    Date.new(month.year, month.month, kind == "monthlyGstr1" ? 11 : 13)
  end

  def payment_due_date(month_label)
    month = month_start(month_label) >> 1
    Date.new(month.year, month.month, 25)
  end

  def gstr2b_available_date(month_label)
    month = month_start(month_label) >> 1
    Date.new(month.year, month.month, 14)
  end

  def ims_review_date(month_label)
    month = month_start(month_label) >> 1
    Date.new(month.year, month.month, 14)
  end

  def gstr3b_due_date(config, month_label, snapshots, quarterly:)
    month = month_start(month_label) >> 1
    return Date.new(month.year, month.month, 20) unless quarterly

    configured_state_code = config.dig("from", "gst", "stateCode")
    snapshot_state_codes = snapshots.map { |snapshot| snapshot.dig("supplier", "gst", "stateCode") }.compact.uniq
    state_code = configured_state_code || (snapshot_state_codes.first if snapshot_state_codes.length == 1)
    return nil unless state_code

    day = GSTR3B_DAY_22_STATE_CODES.include?(state_code.to_s.rjust(2, "0")) ? 22 : 24
    Date.new(month.year, month.month, day)
  end

  def dashboard_invoice(snapshot)
    {
      "number" => snapshot.fetch("invoiceNo"),
      "date" => snapshot.fetch("invoiceDate"),
      "customer" => snapshot.dig("customer", "name") || snapshot.dig("customer", "gst", "gstin") || "Customer",
      "taxableValue" => money_number(snapshot.dig("totals", "taxableValue")),
      "taxTotal" => snapshot.fetch("gst").fetch("taxes", []).sum { |tax| InvoiceCalculation.decimal_value(tax.fetch("amount"), "GST tax amount") }.round(2).to_f,
      "totalValue" => money_number(snapshot.dig("totals", "grandTotal"))
    }
  end

  def dashboard_amounts(snapshots)
    tax_totals = Hash.new { |hash, key| hash[key] = BigDecimal("0") }
    snapshots.each do |snapshot|
      snapshot.fetch("gst").fetch("taxes", []).each do |tax|
        tax_totals[tax.fetch("name").upcase] += InvoiceCalculation.decimal_value(tax.fetch("amount"), "GST tax amount")
      end
    end
    {
      "invoiceCount" => snapshots.length,
      "taxableValue" => sum_snapshot_money(snapshots, "taxableValue"),
      "igst" => tax_totals["IGST"].round(2).to_f,
      "cgst" => tax_totals["CGST"].round(2).to_f,
      "sgst" => tax_totals["SGST"].round(2).to_f,
      "utgst" => tax_totals["UTGST"].round(2).to_f,
      "cess" => tax_totals["CESS"].round(2).to_f,
      "outputTax" => tax_totals.values.sum.round(2).to_f,
      "invoiceValue" => sum_snapshot_money(snapshots, "grandTotal")
    }
  end

  def sum_snapshot_money(snapshots, key)
    snapshots.sum { |snapshot| InvoiceCalculation.decimal_value(snapshot.dig("totals", key), "snapshot.totals.#{key}") }.round(2).to_f
  end

  def money_number(value)
    InvoiceCalculation.decimal_value(value, "GST dashboard amount").round(2).to_f
  end

  def default_dashboard_period(periods, now)
    current_quarter = quarter(now.to_date).fetch("label")
    current = periods.select { |period| period.fetch("quarterLabel") == current_quarter }
    actionable = current.find do |period|
      period.fetch("canGenerate") && period.fetch("status") != "filed" && period.dig("amounts", "invoiceCount").positive?
    end
    (actionable || current.find { |period| period.fetch("month") == now.strftime("%B %Y") } || periods.first)&.fetch("month", nil)
  end

  def filing_status(config, now: Time.now)
    configured = settings(config, period: now.to_date)
    current_quarter = quarter(now.to_date)
    previous_quarter = quarter(now.to_date << 3)
    state = read_state(config)
    periods = current_quarter.fetch("monthLabels").first(2).map do |month|
      entry = state.fetch("iff")[period_key(month)]
      { "month" => month, "status" => entry&.fetch("status", nil) || "pending" }
    end
    {
      "gstFilingScheme" => configured.fetch("scheme"),
      "gstIffEnabled" => configured.fetch("iff") == "enabled",
      "gstQuarterLabel" => current_quarter.fetch("label"),
      "gstQuarterEndMonth" => current_quarter.fetch("endMonth"),
      "gstPreviousQuarterLabel" => previous_quarter.fetch("label"),
      "gstPreviousQuarterEndMonth" => previous_quarter.fetch("endMonth"),
      "gstIffPeriods" => periods
    }
  end

  def returns_directory(config, period)
    File.join(InvoiceStore.new(config).root, "returns", quarter(period).fetch("label"))
  end

  def require_qrmp_iff!(config, period)
    configured = settings(config, period: period)
    raise ConfigError, "gstFiling.scheme must be qrmp for IFF generation" unless configured["scheme"] == "qrmp"
    raise ConfigError, "gstFiling.iff must be enabled for IFF generation" unless configured["iff"] == "enabled"
  end

  def require_qrmp!(config, period)
    raise ConfigError, "gstFiling.scheme must be qrmp for quarterly GSTR-1 generation" unless settings(config, period: period)["scheme"] == "qrmp"
  end

  def require_monthly!(config, period)
    raise ConfigError, "GST filing preference for #{quarter(period).fetch('label')} is not monthly" unless settings(config, period: period)["scheme"] == "monthly"
  end

  def update_state(config)
    store = InvoiceStore.new(config)
    FileUtils.mkdir_p(store.root)
    File.open(File.join(store.root, ".gst-filings.lock"), File::RDWR | File::CREAT, 0600) do |lock|
      lock.flock(File::LOCK_EX)
      state = read_state(config)
      yield(state)
      InvoiceStore.write_json(state_path(config), state)
      state
    ensure
      lock.flock(File::LOCK_UN) if lock
    end
  end

  def absolute_output_path(config, path)
    return nil if path.to_s.empty?
    File.expand_path(path, InvoiceStore.new(config).root)
  end

  def relative_output_path(config, path)
    root = InvoiceStore.new(config).root
    expanded = File.expand_path(path)
    prefix = "#{root}#{File::SEPARATOR}"
    expanded.start_with?(prefix) ? expanded.delete_prefix(prefix) : expanded
  end
end
