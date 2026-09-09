require "minitest/autorun"
require_relative "jira_support"

class JiraSupportTest < Minitest::Test
  def test_missing_jira_config_is_disabled
    refute JiraSupport.enabled?({})
  end

  def test_enabled_config_is_validated
    error = assert_raises(RuntimeError) do
      JiraSupport.validated_settings("jira" => { "enabled" => true })
    end
    assert_includes error.message, "jira.domain"
  end

  def test_rows_are_enriched_from_active_issues
    rows = [{
      "date" => "2026-08-14", "taskCategory" => "", "taskDescription" => "",
      "ticketRef" => "", "hours" => 8, "billable" => "Y", "notes" => ""
    }]
    issues = [{
      "key" => "APP-42", "summary" => "Implement billing export", "type" => "Story",
      "startedAt" => "2026-08-13T09:00:00+05:30", "activeEnd" => "2026-08-15T18:00:00+05:30"
    }]

    enriched = JiraSupport.enrich_rows(rows, issues).first
    assert_equal "APP-42", enriched.fetch("ticketRef")
    assert_equal "Implement billing export", enriched.fetch("taskDescription")
    assert_equal "Development", enriched.fetch("taskCategory")
  end

  def test_bug_maps_to_bug_fix
    rows = [{ "date" => "2026-08-14" }]
    issues = [{
      "key" => "APP-7", "summary" => "Fix export", "type" => "Bug",
      "startedAt" => "2026-08-14T09:00:00+05:30", "activeEnd" => "2026-08-14T18:00:00+05:30"
    }]

    assert_equal "Bug Fix", JiraSupport.enrich_rows(rows, issues).first.fetch("taskCategory")
  end
end
