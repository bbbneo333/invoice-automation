require "json"
require "fileutils"
require "open3"
require "tempfile"
require_relative "time_log"
require_relative "jira_support"

BASE_DIR = __dir__

def run!(*args)
  stdout, stderr, status = Open3.capture3(*args)
  raise(stderr.empty? ? "Command failed: #{args.join(' ')}" : stderr) unless status.success?

  stdout
end

def load_config
  TimeLog.load_config
end

def output_dir(config, record, month_label)
  File.join(config.fetch("outputDir"), "#{record.fetch("invoiceNo")} #{month_label}")
end

def timesheet_payload(config, month_label, jira_issues = [])
  rows = TimeLog.dailyHours(month_label).fetch("rows").each_with_object([]) do |row, result|
    hours = row.fetch("billedHours").to_f
    next unless hours.positive?

    result << {
      "date" => row.fetch("date"),
      "taskCategory" => "",
      "taskDescription" => "",
      "ticketRef" => "",
      "hours" => hours,
      "billable" => "Y",
      "notes" => row.fetch("note", "")
    }
  end

  rows = JiraSupport.enrich_rows(rows, jira_issues) if jira_issues.any?

  {
    "month" => month_label,
    "rows" => rows
  }
end

def generate_timesheet(config, record, month_label, target_dir, payload)
  target = File.join(target_dir, "#{record.fetch('invoiceNo')} Timesheet - #{month_label}.xlsx")

  Tempfile.create(["invoice-timer-timesheet", ".json"]) do |file|
    file.write(JSON.pretty_generate(payload))
    file.flush
    run!(
      "python3",
      File.join(BASE_DIR, "generate_timesheet.py"),
      "--output", target,
      "--data", file.path
    )
  end

  target
end

def main(arguments)
  abort('Usage: ruby generate_month.rb "March 2026"') if arguments.empty?

  month_label = arguments.join(" ")
  config = load_config
  jira_issues = JiraSupport.fetch_month(config, month_label, TimeLog.project_jira_cache_dir)
  record = TimeLog.find_or_create_invoice_record(config, month_label)
  target_dir = output_dir(config, record, month_label)
  FileUtils.mkdir_p(target_dir)

  sync = TimeLog.syncMonthlyHoursToConfig(month_label)
  config = load_config
  record = TimeLog.find_or_create_invoice_record(config, month_label)

  payload = timesheet_payload(config, month_label, jira_issues)

  generate_timesheet(config, record, month_label, target_dir, payload)
  run!("python3", File.join(BASE_DIR, "generate_invoice.py"), month_label)

  puts target_dir
  warn "Synced #{sync['hours']} billed hours from #{sync['logPath']}"
rescue StandardError => e
  path = TimeLog.log_error("generate_month.rb", e, "month" => arguments.join(" "))
  warn "#{e.message}\nDetails: #{path}"
  1
end

exit(main(ARGV) || 0) if $PROGRAM_NAME == __FILE__
