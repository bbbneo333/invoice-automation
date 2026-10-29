require "json"
require "fileutils"
require "date"
require "time"
require "open3"
require "bigdecimal"
require "digest"
require "securerandom"
require_relative "app_paths"
require_relative "invoice_calculation"
require_relative "invoice_store"

module TimeLog
  REGISTRY_PATH = AppPaths.registry_path
  ERROR_LOG_PATH = AppPaths.error_log_path

  module_function

  def error_log_path
    ERROR_LOG_PATH
  end

  def log_error(source, error, context = {})
    FileUtils.mkdir_p(File.dirname(ERROR_LOG_PATH))
    timestamp = Time.now.iso8601
    lines = [
      "[#{timestamp}] #{source}",
      *context.map { |key, value| "#{key}=#{value}" },
      "#{error.class}: #{error.message}",
      *(error.backtrace || [])
    ]
    File.open(ERROR_LOG_PATH, "a") do |file|
      file.puts(lines.join("\n"))
      file.puts("---")
    end
    ERROR_LOG_PATH
  end

  def load_registry
    AppPaths.ensure_registry!
    JSON.parse(File.read(REGISTRY_PATH))
  end

  def write_registry(registry)
    File.write(REGISTRY_PATH, JSON.pretty_generate(registry) + "\n")
  end

  def project_entries(registry = load_registry)
    registry.fetch("projects")
  end

  def active_project(registry = load_registry)
    project_entries(registry).find { |project| project["active"] } || project_entries(registry).first
  end

  def active_config_path(registry = load_registry)
    project = active_project(registry)
    raise "No active project configured in #{REGISTRY_PATH}" unless project

    project.fetch("configPath")
  end

  def load_config
    JSON.parse(File.read(active_config_path))
  end

  def project_status(registry = load_registry)
    project_entries(registry).map do |project|
      {
        "label" => project.fetch("label"),
        "configPath" => project.fetch("configPath"),
        "active" => !!project["active"]
      }
    end
  end

  def project_storage_key(project = active_project)
    raise "No active project configured in #{REGISTRY_PATH}" unless project

    explicit = project["storageKey"].to_s.strip
    return explicit unless explicit.empty?

    label = project.fetch("label").downcase.gsub(/[^a-z0-9]+/, "-").gsub(/\A-|\z/, "")
    label = "project" if label.empty?
    digest = Digest::SHA256.hexdigest(File.expand_path(project.fetch("configPath")))[0, 10]
    "#{label}-#{digest}"
  end

  def project_data_dir(project = active_project)
    AppPaths.project_dir(project_storage_key(project))
  end

  def project_jira_cache_dir(project = active_project)
    AppPaths.project_jira_cache_dir(project_storage_key(project))
  end

  def storagePaths
    registry = load_registry
    {
      "applicationSupport" => AppPaths.data_dir,
      "cache" => AppPaths.cache_dir,
      "logs" => AppPaths.log_dir,
      "registry" => REGISTRY_PATH,
      "errorLog" => ERROR_LOG_PATH,
      "projects" => project_entries(registry).map do |project|
        key = project_storage_key(project)
        {
          "label" => project.fetch("label"),
          "storageKey" => key,
          "configPath" => project.fetch("configPath"),
          "jiraCache" => AppPaths.project_jira_cache_dir(key)
        }
      end
    }
  end

  def switchProject(label)
    registry = load_registry
    projects = project_entries(registry)
    raise "Unknown project label: #{label}" unless projects.any? { |project| project["label"] == label }

    projects.each { |project| project["active"] = project["label"] == label }
    write_registry(registry)
  end

  def addProject(label, path)
    registry = load_registry
    projects = project_entries(registry)
    existing = projects.find { |project| project["label"] == label }
    raise "Project label already exists: #{label}" if existing

    config_path = File.expand_path(path.to_s)
    raise "Select an existing project config.json file" unless File.file?(config_path)
    raise "Project config must be a JSON file" unless File.extname(config_path).downcase == ".json"

    config = JSON.parse(File.read(config_path))
    raise "Project config must contain a JSON object" unless config.is_a?(Hash)
    output_dir = config["outputDir"]
    raise "Project config must define outputDir" unless output_dir.is_a?(String) && !output_dir.strip.empty?

    storage_key = "#{label.downcase.gsub(/[^a-z0-9]+/, '-').gsub(/\A-|\z/, '')}-#{SecureRandom.hex(5)}"

    projects.each { |project| project["active"] = false }
    projects << {
      "label" => label,
      "configPath" => config_path,
      "storageKey" => storage_key,
      "active" => true
    }
    write_registry(registry)
  end

  def run_invoice_generation(month_label = currentMonthLabel)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, File.join(__dir__, "generate_month.rb"), month_label)
    raise(stderr.empty? ? "Invoice generation failed" : stderr.strip) unless status.success?

    {
      "month" => month_label,
      "output" => stdout.strip,
      "message" => stderr.strip
    }
  end

  def run_gst_generation(month_label = currentMonthLabel)
    stdout, stderr, status = Open3.capture3(RbConfig.ruby, File.join(__dir__, "generate_gstr1.rb"), month_label)
    raise(stderr.empty? ? "GSTR-1 generation failed" : stderr.strip) unless status.success?

    {
      "month" => month_label,
      "output" => stdout.strip,
      "message" => stderr.strip
    }
  end

  def currentMonthLabel(now: Time.now)
    now.strftime("%B %Y")
  end

  def previousMonthLabel(now: Time.now)
    (Date.new(now.year, now.month, 1) << 1).strftime("%B %Y")
  end

  def invoice_records(config)
    InvoiceStore.new(config).records
  end

  def find_invoice_record(config, month_label)
    InvoiceStore.new(config).find(month_label)
  end

  def find_or_create_invoice_record(config, month_label)
    InvoiceStore.new(config).find_or_create(month_label)
  end

  def output_dir(config, record, month_label)
    InvoiceStore.new(config).directory(record)
  end

  def log_file_path(config, record, month_label)
    File.join(output_dir(config, record, month_label), "timelog.json")
  end

  def state_file_path(config, record, month_label)
    File.join(output_dir(config, record, month_label), "timelog.state.json")
  end

  def paths_for_record(config, record, month_label, init_log: true)
    dir = output_dir(config, record, month_label)
    FileUtils.mkdir_p(dir) if init_log
    log_path = log_file_path(config, record, month_label)
    ensure_monthly_log!(log_path, month_label) if init_log

    {
      config: config,
      record: record,
      month: month_label,
      outputDir: dir,
      logPath: log_path,
      statePath: state_file_path(config, record, month_label)
    }
  end

  def resolve_paths(month_label, config = load_config, init_log: true)
    record = find_or_create_invoice_record(config, month_label)
    paths_for_record(config, record, month_label, init_log: init_log)
  end

  def find_open_state_paths(config = load_config)
    matches = invoice_records(config).each_with_object([]) do |record, found|
      month_label = record["month"]
      next unless month_label

      paths = paths_for_record(config, record, month_label, init_log: false)
      next unless File.exist?(paths[:statePath])

      found << paths.merge(state: read_state(paths[:statePath]))
    end
    raise "Multiple open time logs found: #{matches.map { |item| item[:month] }.join(', ')}" if matches.length > 1

    matches.first
  end

  def read_state(path)
    return nil unless File.exist?(path)

    JSON.parse(File.read(path))
  end

  def write_state(path, state)
    InvoiceStore.write_json(path, state)
  end

  def seconds_between(started_at, ended_at)
    [Time.parse(ended_at) - Time.parse(started_at), 0].max
  end

  def today(now)
    now.to_date.iso8601
  end

  def elapsed_seconds_for_state(state, now)
    elapsed = state.fetch("elapsedSeconds", 0).to_f
    return elapsed unless state["status"] == "running" && state["currentStartedAt"]

    elapsed + seconds_between(state.fetch("currentStartedAt"), now.iso8601)
  end

  def statusLog(month_label = currentMonthLabel, now: Time.now)
    registry = load_registry
    active = active_project(registry)
    unless active
      return {
        "projectLabel" => "No Project",
        "projectConfigPath" => "",
        "projects" => [],
        "month" => currentMonthLabel(now: now),
        "currentMonth" => currentMonthLabel(now: now),
        "previousMonth" => previousMonthLabel(now: now),
        "date" => today(now),
        "workday" => today(now),
        "status" => "unconfigured",
        "startedAt" => nil,
        "currentStartedAt" => nil,
        "elapsedSeconds" => 0.0,
        "elapsedMinutes" => 0.0,
        "elapsedHours" => 0.0,
        "monthlyHours" => 0.0,
        "monthlyActualHours" => 0.0,
        "monthlyBilledHours" => 0.0,
        "workingDays" => 0,
        "averageHoursPerWorkingDay" => 0.0,
        "targetHours" => 0.0,
        "targetRemainingHours" => 0.0,
        "daysToTarget" => 0,
        "dailyTargetHours" => 0.0,
        "todayHours" => 0.0,
        "dailyTargetRemainingHours" => 0.0,
        "dailyOvertimeHours" => 0.0,
        "dailyTargetFinishAt" => nil,
        "dailyTargetAchieved" => false,
        "errorLogPath" => error_log_path,
        "logPath" => "",
        "statePath" => "",
        "outputDir" => "",
        "currentReimbursements" => [],
        "previousReimbursements" => []
      }
    end

    config = load_config
    open_paths = find_open_state_paths(config)
    paths = open_paths || resolve_paths(month_label, config)
    month_label = paths[:month]
    state = open_paths && open_paths[:state]
    elapsed_seconds = state ? elapsed_seconds_for_state(state, now) : 0.0
    daily = dailyHours(month_label)
    daily_target = daily.fetch("dailyTargetHours")
    workday = state ? state.fetch("date") : today(now)
    workday_hours = today_logged_hours(daily.fetch("rows"), workday)
    active_workday_hours = state ? elapsed_seconds / 3600.0 : 0.0
    workday_hours += active_workday_hours
    daily_remaining = daily_target.positive? ? (daily_target - workday_hours).round(2) : 0.0
    finish_at = if state && state["status"] == "running" && daily_remaining.positive?
                  (now + (daily_remaining * 3600)).iso8601
                end
    live_monthly_hours = daily.fetch("totalHours") + active_workday_hours
    target_hours = daily.fetch("targetHours")
    target_remaining = target_hours.positive? ? (target_hours - live_monthly_hours).round(2) : 0.0
    planning_average = daily_target.positive? ? daily_target : (daily.fetch("averageHoursPerWorkingDay").positive? ? daily.fetch("averageHoursPerWorkingDay") : 8.0)
    days_to_target = target_remaining.positive? ? (target_remaining / planning_average).ceil : 0

    {
      "projectLabel" => active && active["label"],
      "projectConfigPath" => active && active["configPath"],
      "projects" => project_status(registry),
      "month" => month_label,
      "currentMonth" => currentMonthLabel(now: now),
      "previousMonth" => previousMonthLabel(now: now),
      "date" => today(now),
      "workday" => workday,
      "status" => state ? state.fetch("status") : "idle",
      "startedAt" => state && state["startedAt"],
      "currentStartedAt" => state && state["currentStartedAt"],
      "elapsedSeconds" => elapsed_seconds,
      "elapsedMinutes" => (elapsed_seconds / 60.0).round(2),
      "elapsedHours" => (elapsed_seconds / 3600.0).round(2),
      "monthlyHours" => daily.fetch("totalHours"),
      "monthlyActualHours" => daily.fetch("totalActualHours"),
      "monthlyBilledHours" => daily.fetch("totalBilledHours"),
      "workingDays" => daily.fetch("workingDays"),
      "averageHoursPerWorkingDay" => daily.fetch("averageHoursPerWorkingDay"),
      "targetHours" => target_hours,
      "targetRemainingHours" => target_remaining,
      "daysToTarget" => days_to_target,
      "dailyTargetHours" => daily_target,
      "todayHours" => workday_hours.round(2),
      "dailyTargetRemainingHours" => daily_remaining,
      "dailyOvertimeHours" => daily_remaining.negative? ? daily_remaining.abs.round(2) : 0.0,
      "dailyTargetFinishAt" => finish_at,
      "dailyTargetAchieved" => daily_target.positive? && daily_remaining <= 0,
      "errorLogPath" => error_log_path,
      "logPath" => paths[:logPath],
      "statePath" => paths[:statePath],
      "outputDir" => paths[:outputDir],
      "currentReimbursements" => reimbursementEntries(currentMonthLabel(now: now)),
      "previousReimbursements" => reimbursementEntries(previousMonthLabel(now: now))
    }
  end

  def startLog(month_label = currentMonthLabel, now: Time.now)
    config = load_config
    open_paths = find_open_state_paths(config)
    paths = open_paths || resolve_paths(month_label, config)
    state = open_paths && open_paths[:state]

    if state && state["status"] == "running"
      return state.merge("logPath" => paths[:logPath], "outputDir" => paths[:outputDir])
    end

    if state && state["date"] != today(now)
      raise "Open time log is for #{state['date']}. Finish or discard it before starting #{today(now)}."
    end

    state ||= {
      "month" => month_label,
      "date" => today(now),
      "startedAt" => now.iso8601,
      "elapsedSeconds" => 0.0,
      "segments" => []
    }

    state["status"] = "running"
    state["currentStartedAt"] = now.iso8601
    write_state(paths[:statePath], state)

    state.merge("logPath" => paths[:logPath], "outputDir" => paths[:outputDir])
  end

  def pauseLog(month_label = currentMonthLabel, now: Time.now)
    paths = find_open_state_paths || resolve_paths(month_label)
    state = paths[:state] || read_state(paths[:statePath])
    raise "No active time log for #{month_label}" unless state

    return state.merge("logPath" => paths[:logPath], "outputDir" => paths[:outputDir]) if state["status"] == "paused"
    raise "Cannot pause a #{state['status']} time log" unless state["status"] == "running"

    started_at = state.fetch("currentStartedAt")
    ended_at = now.iso8601
    seconds = seconds_between(started_at, ended_at)
    state["segments"] << { "startedAt" => started_at, "endedAt" => ended_at, "seconds" => seconds }
    state["elapsedSeconds"] = state.fetch("elapsedSeconds", 0).to_f + seconds
    state["currentStartedAt"] = nil
    state["status"] = "paused"
    write_state(paths[:statePath], state)

    state.merge("logPath" => paths[:logPath], "outputDir" => paths[:outputDir])
  end

  def finishLog(month_label = currentMonthLabel, now: Time.now)
    paths = find_open_state_paths || resolve_paths(month_label)
    month_label = paths[:month]
    state = paths[:state] || read_state(paths[:statePath])
    raise "No active time log for #{month_label}" unless state

    state = pauseLog(month_label, now: now) if state["status"] == "running"
    state = read_state(paths[:statePath])

    seconds = state.fetch("elapsedSeconds", 0).to_f
    entry = {
      "date" => state.fetch("date"),
      "startedAt" => state.fetch("startedAt"),
      "finishedAt" => now.iso8601,
      "seconds" => seconds,
      "minutes" => (seconds / 60.0).round(2),
      "hours" => (seconds / 3600.0).round(2),
      "segments" => state.fetch("segments", [])
    }

    upsert_timer_day(paths[:logPath], month_label, entry)
    File.delete(paths[:statePath]) if File.exist?(paths[:statePath])

    entry.merge("logPath" => paths[:logPath], "outputDir" => paths[:outputDir])
  end

  def discardLog(month_label = currentMonthLabel)
    paths = find_open_state_paths || resolve_paths(month_label)
    File.delete(paths[:statePath]) if File.exist?(paths[:statePath])
    { "status" => "discarded", "logPath" => paths[:logPath], "outputDir" => paths[:outputDir] }
  end

  def blank_monthly_log(month_label)
    { "month" => month_label, "days" => [] }
  end

  def ensure_monthly_log!(path, month_label)
    return if File.exist?(path)

    InvoiceStore.write_json(path, blank_monthly_log(month_label))
  end

  def read_monthly_log(path, month_label)
    ensure_monthly_log!(path, month_label)
    payload = JSON.parse(File.read(path))
    payload["month"] ||= month_label
    payload["days"] ||= []
    before = JSON.generate(payload)
    payload.fetch("days").each { |day| normalize_day!(day) }
    InvoiceStore.write_json(path, payload) if JSON.generate(payload) != before
    payload
  end

  def write_monthly_log(path, payload)
    payload["days"] = payload.fetch("days", []).sort_by { |day| day.fetch("date") }
    InvoiceStore.write_json(path, payload)
  end

  def timer_hours(day)
    day.fetch("timer", {}).fetch("segments", []).sum { |segment| segment.fetch("seconds").to_f } / 3600.0
  end

  def effective_actual_hours(day)
    timer_hours(day).round(2)
  end

  def normalize_day!(day)
    day["timer"] ||= { "segments" => [] }
    day["source"] ||= "timer"
    day["actualHours"] = effective_actual_hours(day).round(2)
    day["billedHours"] = if day["source"] == "manual"
                           day.fetch("billedHours", day["actualHours"]).to_f.round(2)
                         else
                           day["actualHours"]
                         end
    day["hours"] = day["actualHours"]
    day["note"] ||= ""
    day
  end

  def upsert_timer_day(path, month_label, entry)
    payload = read_monthly_log(path, month_label)
    day = payload.fetch("days").find { |item| item["date"] == entry.fetch("date") }
    unless day
      day = {
        "date" => entry.fetch("date"),
        "source" => "timer",
        "actualHours" => 0,
        "timer" => { "segments" => [] },
        "note" => ""
      }
      payload.fetch("days") << day
    end

    day["timer"] ||= { "segments" => [] }
    day["timer"]["segments"].concat(entry.fetch("segments", []))
    day["source"] ||= "timer"
    day["actualHours"] = timer_hours(day).round(2) if day["source"] == "timer"
    normalize_day!(day)
    write_monthly_log(path, payload)
  end

  def dailyHours(month_label = currentMonthLabel)
    paths = resolve_paths(month_label)
    payload = read_monthly_log(paths[:logPath], month_label)
    rows = payload.fetch("days").map do |day|
      normalize_day!(day)
      calculated_timer_hours = timer_hours(day).round(2)
      {
        "date" => day.fetch("date"),
        "hours" => day.fetch("actualHours").to_f.round(2),
        "actualHours" => day.fetch("actualHours").to_f.round(2),
        "billedHours" => day.fetch("billedHours").to_f.round(2),
        "source" => day.fetch("source"),
        "timerHours" => calculated_timer_hours,
        "manualHours" => day["source"] == "manual" ? day.fetch("actualHours").to_f.round(2) : nil,
        "note" => day.fetch("note", "")
      }
    end.sort_by { |row| row.fetch("date") }
    total_actual_hours = rows.sum { |row| row.fetch("actualHours").to_f }.round(2)
    total_billed_hours = rows.sum { |row| row.fetch("billedHours").to_f }.round(2)
    working_days = rows.count
    average_hours = working_days.positive? ? (total_actual_hours / working_days).round(2) : 0.0
    daily_target_hours = current_daily_target_hours(paths[:config], paths[:record]).round(2)
    planning_average = daily_target_hours.positive? ? daily_target_hours : (average_hours.positive? ? average_hours : 8.0)
    target_hours = current_target_hours(paths[:config], paths[:record]).round(2)
    target_remaining = target_hours.positive? ? (target_hours - total_actual_hours).round(2) : 0.0
    days_to_target = target_remaining.positive? ? (target_remaining / planning_average).ceil : 0

    {
      "month" => month_label,
      "rows" => rows,
      "totalHours" => total_actual_hours,
      "totalActualHours" => total_actual_hours,
      "totalBilledHours" => total_billed_hours,
      "workingDays" => working_days,
      "averageHoursPerWorkingDay" => average_hours,
      "targetHours" => target_hours,
      "targetRemainingHours" => target_remaining,
      "daysToTarget" => days_to_target,
      "dailyTargetHours" => daily_target_hours,
      "logPath" => paths[:logPath],
      "outputDir" => paths[:outputDir]
    }
  end

  def today_logged_hours(rows, date)
    row = rows.find { |item| item.fetch("date") == date }
    row ? row.fetch("actualHours").to_f : 0.0
  end

  def current_target_hours(config, record)
    value = record["targetHours"]
    value = config["targetHours"] if value.nil?
    value.to_f
  end

  def current_daily_target_hours(config, record)
    value = record["dailyTargetHours"]
    value = config["dailyTargetHours"] if value.nil?
    value.nil? ? 8.0 : value.to_f
  end

  def setTargetHours(month_label, hours)
    value = hours.to_s.strip.empty? ? 0.0 : Float(hours)
    raise "Target hours cannot be negative" if value.negative?

    paths = resolve_paths(month_label)
    InvoiceStore.new(paths[:config]).update_metadata(month_label, "targetHours" => value.round(2))
    dailyHours(month_label)
  end

  def setDailyTargetHours(month_label, hours)
    value = hours.to_s.strip.empty? ? 8.0 : Float(hours)
    raise "Daily target hours cannot be negative" if value.negative?

    paths = resolve_paths(month_label)
    InvoiceStore.new(paths[:config]).update_metadata(month_label, "dailyTargetHours" => value.round(2))
    dailyHours(month_label)
  end

  def setDailyHours(month_label, date, source, hours = nil, billed_hours = nil, note = "")
    paths = resolve_paths(month_label)
    Date.iso8601(date)
    payload = read_monthly_log(paths[:logPath], month_label)
    day = payload.fetch("days").find { |item| item["date"] == date }
    unless day
      day = {
        "date" => date,
        "source" => "timer",
        "actualHours" => 0,
        "timer" => { "segments" => [] },
        "note" => ""
      }
      payload.fetch("days") << day
    end

    case source
    when "timer"
      day["source"] = "timer"
      day["actualHours"] = timer_hours(day).round(2)
      day["billedHours"] = day["actualHours"]
      day["note"] = note.to_s
    when "manual"
      billed_value = if billed_hours.to_s.strip.empty?
                       timer_hours(day)
                     else
                       Float(billed_hours)
                     end
      raise "Billed hours cannot be negative" if billed_value.negative?

      day["source"] = "manual"
      day["actualHours"] = timer_hours(day).round(2)
      day["billedHours"] = billed_value.round(2)
      day["note"] = note.to_s
      day["timer"] ||= { "segments" => [] }
    else
      raise "Unsupported source: #{source}"
    end

    normalize_day!(day)
    write_monthly_log(paths[:logPath], payload)
    dailyHours(month_label)
  end

  def deleteDailyHours(month_label, date)
    paths = resolve_paths(month_label)
    Date.iso8601(date)
    payload = read_monthly_log(paths[:logPath], month_label)
    payload["days"] = payload.fetch("days").reject { |day| day["date"] == date }
    write_monthly_log(paths[:logPath], payload)
    dailyHours(month_label)
  end

  def calculateMonthlyHours(month_label = currentMonthLabel)
    dailyHours(month_label).fetch("totalHours")
  end

  def calculateMonthlyBilledHours(month_label = currentMonthLabel)
    dailyHours(month_label).fetch("totalBilledHours")
  end

  def decimal_money(value)
    InvoiceCalculation.money(value)
  end

  def calculated_invoice_amount(config, record, month_label, hours)
    period_start = InvoiceCalculation.parse_month(month_label).first
    InvoiceCalculation.calculate(config, record.merge("hours" => hours), period_start).fetch("grandTotal")
  end

  def reimbursementEntries(month_label)
    config = load_config
    record = find_invoice_record(config, month_label)
    return [] unless record

    record.fetch("reimbursements", []).map do |item|
      {
        "id" => item.fetch("id"),
        "name" => item.fetch("name"),
        "amount" => item.fetch("amount").to_f.round(2),
        "attachment" => item["attachment"]
      }
    end
  end

  def addReimbursement(month_label, name, amount, attachment_path = nil)
    clean_name = name.to_s.strip
    raise "Reimbursement name must not be empty" if clean_name.empty?
    value = decimal_money(amount)
    raise "Reimbursement amount must be greater than zero" unless value.positive?
    config = load_config
    store = InvoiceStore.new(config)
    store.find_or_create(month_label)
    hours = calculateMonthlyBilledHours(month_label)
    entry = { "id" => SecureRandom.uuid, "name" => clean_name, "amount" => value.to_f }
    source = attachment_path.to_s.strip
    target = nil
    copied = false
    begin
      store.update_reimbursements(month_label) do |entries, record|
        unless source.empty?
          raise "Attachment does not exist: #{source}" unless File.file?(source)
          target = File.join(store.directory(record), "reimbursements", File.basename(source))
          raise "A reimbursement attachment named #{File.basename(source)} already exists" if File.exist?(target)
          entry["attachment"] = File.join("reimbursements", File.basename(source))
        end
        updated = entries + [entry]
        calculated_invoice_amount(config, record.merge("reimbursements" => updated), month_label, hours)
        if target
          FileUtils.mkdir_p(File.dirname(target))
          FileUtils.cp(source, target)
          copied = true
        end
        updated
      end
    rescue StandardError
      File.delete(target) if copied && File.file?(target)
      raise
    end
    reimbursementEntries(month_label)
  end

  def removeReimbursement(month_label, id)
    config = load_config
    store = InvoiceStore.new(config)
    hours = calculateMonthlyBilledHours(month_label)
    removed = nil
    record = nil
    store.update_reimbursements(month_label) do |entries, metadata|
      record = metadata
      removed = entries.find { |item| item["id"] == id }
      raise "Unknown reimbursement: #{id}" unless removed
      updated = entries.reject { |item| item["id"] == id }
      calculated_invoice_amount(config, record.merge("reimbursements" => updated), month_label, hours)
      updated
    end
    if removed["attachment"]
      directory = store.directory(record)
      reimbursements_dir = File.expand_path(File.join(directory, "reimbursements"))
      path = File.expand_path(File.join(directory, removed["attachment"]))
      File.delete(path) if path.start_with?("#{reimbursements_dir}#{File::SEPARATOR}") && File.file?(path)
    end
    reimbursementEntries(month_label)
  end

  def invoice_data(month_label, config = load_config)
    record = find_or_create_invoice_record(config, month_label)
    hours = calculateMonthlyBilledHours(month_label)
    total = calculated_invoice_amount(config, record, month_label, hours)
    record.merge("hours" => hours, "amount" => total.frac.zero? ? total.to_i : total.to_f)
  end

  def monthlySummary(month_label = currentMonthLabel)
    config = load_config
    record = invoice_data(month_label, config)
    {
      "month" => month_label,
      "synced" => true,
      "hours" => record["hours"],
      "billedHours" => record["hours"],
      "amount" => record["amount"],
      "logPath" => log_file_path(config, record, month_label),
      "outputDir" => output_dir(config, record, month_label)
    }
  end

end

if $PROGRAM_NAME == __FILE__
  command = ARGV.shift
  month_label = ARGV.empty? ? TimeLog.currentMonthLabel : ARGV.join(" ")
  month_arg = lambda do
    if ARGV.first&.match?(/\A[A-Za-z]+ \d{4}\z/)
      ARGV.shift
    else
      TimeLog.currentMonthLabel
    end
  end

  abort("Usage: ruby src/time_log.rb status|start|pause|finish|discard|total|sync|generate|generate-gst [\"May 2026\"]") if command.nil?

  begin
    result = case command
    when "status"
      TimeLog.statusLog(month_label)
    when "projects"
      { "projects" => TimeLog.project_status }
    when "migrate-storage"
      InvoiceStore.migrate_config(TimeLog.active_config_path)
    when "storage-paths"
      TimeLog.storagePaths
    when "reimbursements"
      TimeLog.reimbursementEntries(month_label)
    when "add-reimbursement"
      reimbursement_month = month_arg.call
      abort("Usage: ruby src/time_log.rb add-reimbursement [\"May 2026\"] NAME AMOUNT [ATTACHMENT]") if ARGV.length < 2
      name = ARGV.shift
      amount = ARGV.shift
      attachment = ARGV.shift
      TimeLog.addReimbursement(reimbursement_month, name, amount, attachment)
      TimeLog.statusLog
    when "remove-reimbursement"
      reimbursement_month = month_arg.call
      abort("Usage: ruby src/time_log.rb remove-reimbursement [\"May 2026\"] ID") if ARGV.empty?
      TimeLog.removeReimbursement(reimbursement_month, ARGV.shift)
      TimeLog.statusLog
    when "switch-project"
      abort("Usage: ruby src/time_log.rb switch-project LABEL") if ARGV.empty?

      TimeLog.switchProject(ARGV.join(" "))
      TimeLog.statusLog
    when "add-project"
      abort("Usage: ruby src/time_log.rb add-project LABEL /path/to/config.json") if ARGV.length < 2

      label = ARGV.shift
      path = ARGV.join(" ")
      TimeLog.addProject(label, path)
      TimeLog.statusLog
    when "generate"
      result = TimeLog.run_invoice_generation(month_label)
      TimeLog.statusLog(month_label).merge(
        "generation" => {
          "output" => result["output"],
          "message" => result["message"]
        }
      )
    when "generate-gst"
      result = TimeLog.run_gst_generation(month_label)
      TimeLog.statusLog.merge(
        "month" => result["month"],
        "outputDir" => File.dirname(result["output"]),
        "generation" => {
          "output" => result["output"],
          "message" => result["message"]
        }
      )
    when "daily-hours"
      TimeLog.dailyHours(month_label)
    when "set-day"
      edit_month = month_arg.call
      abort("Usage: ruby src/time_log.rb set-day [\"May 2026\"] DATE timer|manual [ACTUAL_HOURS] [BILLED_HOURS] [NOTE]") if ARGV.length < 2

      date = ARGV.shift
      source = ARGV.shift
      hours = ARGV.shift
      billed_hours = ARGV.shift
      note = ARGV.join(" ")
      TimeLog.setDailyHours(edit_month, date, source, hours, billed_hours, note)
    when "delete-day"
      edit_month = month_arg.call
      abort("Usage: ruby src/time_log.rb delete-day [\"May 2026\"] DATE") if ARGV.empty?

      TimeLog.deleteDailyHours(edit_month, ARGV.shift)
    when "set-target"
      edit_month = month_arg.call
      abort("Usage: ruby src/time_log.rb set-target [\"May 2026\"] HOURS") if ARGV.empty?

      TimeLog.setTargetHours(edit_month, ARGV.shift)
    when "set-daily-target"
      edit_month = month_arg.call
      abort("Usage: ruby src/time_log.rb set-daily-target [\"May 2026\"] HOURS") if ARGV.empty?

      TimeLog.setDailyTargetHours(edit_month, ARGV.shift)
    when "start"
      TimeLog.startLog(month_label)
      TimeLog.statusLog(month_label)
    when "pause"
      TimeLog.pauseLog(month_label)
      TimeLog.statusLog(month_label)
    when "finish"
      TimeLog.finishLog(month_label)
      TimeLog.statusLog(month_label)
    when "discard"
      TimeLog.discardLog(month_label)
      TimeLog.statusLog(month_label)
    when "total"
      {
        "month" => month_label,
        "actualHours" => TimeLog.calculateMonthlyHours(month_label),
        "billedHours" => TimeLog.calculateMonthlyBilledHours(month_label)
      }
    when "sync"
      TimeLog.monthlySummary(month_label)
    else
      abort("Unknown time log command: #{command}")
    end

    puts JSON.pretty_generate(result)
  rescue StandardError => e
    path = TimeLog.log_error("time_log.rb", e, "command" => command)
    warn "#{e.message}\nDetails: #{path}"
    exit 1
  end
end
