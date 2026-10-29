require "date"
require "digest"
require "fileutils"
require "json"
require "time"
require_relative "invoice_calculation"
require_relative "invoice_store"
require_relative "gst_input_tracker"

module GstFiling
  ConfigError = InvoiceCalculation::ConfigError
  SCHEMES = %w[monthly qrmp].freeze
  IFF_SETTINGS = %w[disabled enabled].freeze
  STATE_VERSION = 1

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
    state
  rescue JSON::ParserError => error
    raise ConfigError, "Invalid gst-filings.json: #{error.message}"
  end

  def blank_state
    { "version" => STATE_VERSION, "iff" => {}, "gstr1" => {}, "preferences" => {} }
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
    filed = entries.any? { |entry| entry["status"] == "filed" }
    generated = entries.any? { |entry| entry["status"] == "generated" }
    {
      "locked" => filed || generated,
      "reason" => filed ? "a filing is already marked filed" : generated ? "a GST JSON has already been generated" : nil
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
    snapshots = InvoiceStore.new(config).records.each_with_object([]) do |record, result|
      snapshot = record["snapshot"]
      result << snapshot if snapshot.is_a?(Hash) && snapshot["version"] == 1 && snapshot.dig("gst", "enabled") == true
    end
    quarter_starts = relevant_quarter_starts(config, snapshots, state, now)
    periods = quarter_starts.flat_map { |start_date| dashboard_quarter_periods(config, snapshots, state, now, start_date) }
    preferences = quarter_starts.map { |start_date| dashboard_preference(config, state, start_date) }
    input_months = GstInputTracker.month_summaries(
      config, quarter_starts.flat_map { |start_date| quarter(start_date).fetch("monthLabels") }
    )
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

  def dashboard_quarter_periods(config, snapshots, state, now, start_date)
    details = quarter(start_date)
    configured = settings_from_state(config, state, start_date)
    now_month = Date.new(now.year, now.month, 1)
    details.fetch("months").each_with_index.map do |month, index|
      month_label = month.strftime("%B %Y")
      if configured.fetch("scheme") == "qrmp" && index < 2
        selected = snapshots_in_month(snapshots, month)
        entry = state.fetch("iff")[period_key(month_label)]
        dashboard_period(
          config, month_label, details.fetch("label"), "iff", entry, selected, configured,
          action_title: "IFF", can_generate: configured.fetch("iff") == "enabled" && month <= now_month && !selected.empty?
        )
      elsif configured.fetch("scheme") == "qrmp"
        selected = snapshots.select { |snapshot| (details.fetch("startDate")..details.fetch("endDate")).cover?(Date.iso8601(snapshot.fetch("invoiceDate"))) }
        entry = state.fetch("gstr1")[period_key(month_label)]
        dashboard_period(
          config, month_label, details.fetch("label"), "quarterlyGstr1", entry, selected, configured,
          action_title: "Quarterly GSTR-1", can_generate: month <= now_month && !selected.empty?
        )
      else
        selected = snapshots_in_month(snapshots, month)
        entry = state.fetch("gstr1")[period_key(month_label)]
        dashboard_period(
          config, month_label, details.fetch("label"), "monthlyGstr1", entry, selected, configured,
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

  def dashboard_period(config, month_label, quarter_label, kind, entry, snapshots, configured, action_title:, can_generate:)
    status = entry&.fetch("status", nil) || "pending"
    validate_entry_snapshots!(config, entry) if status == "filed"
    {
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
