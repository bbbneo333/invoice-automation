require "json"
require "fileutils"
require "open3"
require "base64"
require "date"
require "time"

module JiraSupport
  module_function

  def enabled?(config)
    jira = config["jira"]
    return false unless jira
    raise "jira must be an object" unless jira.is_a?(Hash)
    raise "jira.enabled must be true or false" unless [true, false].include?(jira["enabled"])

    jira["enabled"]
  end

  def validated_settings(config)
    jira = config.fetch("jira")
    %w[domain email apiToken assignee inProgressStatus doneStatus].each do |key|
      raise "jira.#{key} must not be empty when Jira is enabled" if jira[key].to_s.strip.empty?
    end
    issue_types = jira["issueTypes"]
    raise "jira.issueTypes must be a non-empty array" unless issue_types.is_a?(Array) && issue_types.any?
    unless jira["assignee"] == "currentUser" || jira["assignee"].start_with?("accountId:")
      raise "jira.assignee must be currentUser or accountId:<Jira account ID>"
    end

    jira
  end

  def fetch_month(config, month_label, cache_dir)
    return [] unless enabled?(config)

    settings = validated_settings(config)
    start_date = Date.strptime(month_label, "%B %Y")
    end_date = start_date.next_month
    issue_types = settings.fetch("issueTypes").map { |value| %Q{"#{value.to_s.gsub('"', '\\"')}"} }.join(",")
    assignee = settings.fetch("assignee") == "currentUser" ? "currentUser()" : %Q{"#{settings.fetch('assignee').delete_prefix('accountId:')}"}
    in_progress = settings.fetch("inProgressStatus")
    done = settings.fetch("doneStatus")
    jql = %(assignee=#{assignee} AND issuetype in (#{issue_types}) AND status CHANGED TO "#{in_progress}" BEFORE "#{end_date.iso8601}" AND (status CHANGED TO "#{done}" AFTER "#{start_date.iso8601}" OR status != "#{done}"))
    auth = "Authorization: Basic #{Base64.strict_encode64("#{settings.fetch('email')}:#{settings.fetch('apiToken')}")}"
    base_url = "https://#{settings.fetch('domain')}.atlassian.net/rest/api/3"

    search = curl_json(
      "#{base_url}/search/jql", auth,
      "jql" => jql,
      "fields" => "summary,issuetype,status,created,parent",
      "maxResults" => 100
    )
    issues = search.fetch("issues", []).map do |issue|
      histories = fetch_histories(base_url, issue.fetch("key"), auth)
      started_at = first_transition_at(histories, in_progress) || issue.dig("fields", "created")
      done_at = first_transition_at(histories, done)
      {
        "key" => issue.fetch("key"),
        "summary" => issue.dig("fields", "summary").to_s,
        "type" => issue.dig("fields", "issuetype", "name").to_s,
        "startedAt" => started_at,
        "doneAt" => done_at,
        "activeEnd" => done_at || (end_date - 1).iso8601
      }
    end

    FileUtils.mkdir_p(cache_dir)
    cache_path = File.join(cache_dir, "#{month_label.downcase.tr(' ', '_')}.json")
    File.write(cache_path, JSON.pretty_generate("month" => month_label, "issues" => issues) + "\n")
    issues
  end

  def enrich_rows(rows, issues)
    rows.map do |row|
      matching = issues_for_date(issues, Date.iso8601(row.fetch("date")))
      row.merge(
        "taskCategory" => matching.map { |issue| issue["type"] == "Bug" ? "Bug Fix" : "Development" }.uniq.join(", "),
        "taskDescription" => matching.map { |issue| issue["summary"] }.reject(&:empty?).uniq.join(", "),
        "ticketRef" => matching.map { |issue| issue["key"] }.uniq.join(", "),
        "tasks" => matching.map { |issue| { "key" => issue["key"], "summary" => issue["summary"] } }
      )
    end
  end

  def issues_for_date(issues, date)
    active = issues.select do |issue|
      start_date = Time.parse(issue.fetch("startedAt")).to_date
      end_date = Time.parse(issue.fetch("activeEnd")).to_date
      (start_date..end_date).cover?(date)
    end
    return active if active.any?
    return [] if issues.empty?

    [issues.min_by do |issue|
      start_date = Time.parse(issue.fetch("startedAt")).to_date
      end_date = Time.parse(issue.fetch("activeEnd")).to_date
      date < start_date ? start_date - date : date > end_date ? date - end_date : 0
    end]
  end

  def fetch_histories(base_url, issue_key, auth)
    start_at = 0
    histories = []
    loop do
      page = curl_json("#{base_url}/issue/#{issue_key}/changelog", auth, "startAt" => start_at, "maxResults" => 100)
      values = page.fetch("values", [])
      histories.concat(values)
      break if page["isLast"] || values.empty? || histories.length >= page.fetch("total", 0)
      start_at += page.fetch("maxResults", 100)
    end
    histories
  end

  def first_transition_at(histories, status)
    histories.each_with_object([]) do |history, matches|
      matches << history["created"] if history.fetch("items", []).any? do |item|
        item["field"] == "status" && item["toString"] == status
      end
    end.min
  end

  def curl_json(url, auth, query)
    args = ["curl", "-sS", "-G", "--config", "-", url]
    query.each { |key, value| args.concat(["--data-urlencode", "#{key}=#{value}"]) }
    stdin = "header = \"#{auth}\"\nheader = \"Accept: application/json\"\n"
    stdout, stderr, status = Open3.capture3(*args, stdin_data: stdin)
    raise(stderr.empty? ? "Jira request failed: #{url}" : stderr.strip) unless status.success?
    JSON.parse(stdout)
  end
end
