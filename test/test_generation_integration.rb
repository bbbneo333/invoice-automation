require "minitest/autorun"
require "json"
require "tmpdir"
require "fileutils"
require "open3"
require "rbconfig"
require_relative "../src/backend_dependencies"
require_relative "../src/invoice_calculation"

# Requires the renderer dependencies (or an already-built app bundle).
class GenerationIntegrationTest < Minitest::Test
  BACKEND = File.expand_path(ENV.fetch("INVOICE_TEST_BACKEND", File.expand_path("..", __dir__)))

  def command(environment, script, *arguments)
    stdout, stderr, status = Open3.capture3(environment, RbConfig.ruby, File.join(BACKEND, "src", script), *arguments, chdir: File::SEPARATOR)
    assert status.success?, "#{script} #{arguments.inspect} failed:\n#{stderr}\n#{stdout}"
    stdout
  end

  def test_monthly_generation_and_cli_with_isolated_storage
    Dir.mktmpdir("invoice-ruby-integration-") do |directory|
      data = File.join(directory, "app-data")
      fixture = JSON.parse(File.read(File.join(__dir__, "fixtures", "invoice_cases.json"))).first
      config = fixture.fetch("config")
      config["locale"] = "de-DE"
      # Exercise the minimal GST profile without optional SAC display text.
      config.fetch("taxProfile").delete("sacDescription")
      config["taxProfile"] = InvoiceCalculation.tax_profile(config)
      config["outputDir"] = File.join(directory, "exports & spaces")
      config["invoices"] = []
      config["jira"] = { "enabled" => false }
      config_path = File.join(directory, "project.json")
      File.write(config_path, JSON.generate(config))
      # Any accidental invocation of the removed Python backend must fail.
      bin = File.join(directory, "bin")
      FileUtils.mkdir_p(bin)
      %w[python python3].each do |name|
        path = File.join(bin, name)
        File.write(path, "#!/bin/sh\necho 'Python is not part of this backend' >&2\nexit 99\n")
        File.chmod(0755, path)
      end
      environment = {
        "INVOICE_AUTOMATION_DATA_DIR" => data,
        "INVOICE_AUTOMATION_CONFIG" => File.join(data, "config.json"),
        "INVOICE_AUTOMATION_CACHE_DIR" => File.join(directory, "cache"),
        "INVOICE_AUTOMATION_LOG_DIR" => File.join(directory, "logs"),
        "INVOICE_AUTOMATION_ERROR_LOG" => File.join(directory, "logs", "error.log"),
        "PATH" => "#{bin}#{File::PATH_SEPARATOR}/usr/bin#{File::PATH_SEPARATOR}/bin"
      }
      if File.directory?(File.join(BACKEND, "vendor", "rubyzip"))
        environment.merge!("GEM_HOME" => File.join(directory, "no-gems"), "GEM_PATH" => File.join(directory, "no-gems"), "BUNDLE_GEMFILE" => nil, "RUBYOPT" => nil, "RUBYLIB" => nil)
      end
      state = JSON.parse(command(environment, "time_log.rb", "add-project", "TEST", config_path))
      assert_equal "TEST", state.fetch("projectLabel")
      %w[start pause finish].each do |action|
        state = JSON.parse(command(environment, "time_log.rb", action))
        assert_equal({ "start" => "running", "pause" => "paused", "finish" => "idle" }.fetch(action), state.fetch("status"))
      end
      command(environment, "time_log.rb", "set-day", "August 2026", "2026-08-14", "manual", "", "7.5", "Work & <review>\nSecond line")
      command(environment, "time_log.rb", "add-reimbursement", "August 2026", "Hosting", "998.005")
      result = JSON.parse(command(environment, "time_log.rb", "generate", "August 2026"))
      target = result.fetch("generation").fetch("output")
      assert File.directory?(target)
      record = JSON.parse(File.read(config_path)).fetch("invoices").find { |item| item["month"] == "August 2026" }
      assert_equal 7.5, record.fetch("hours")
      prefix = record.fetch("invoiceNo")
      pdf = File.join(target, "#{prefix} Invoice - August 2026.pdf")
      xlsx = File.join(target, "#{prefix} Timesheet - August 2026.xlsx")
      assert_equal "%PDF-", File.binread(pdf, 5)
      Zip::File.open(xlsx) do |archive|
        sheet = archive.read("xl/worksheets/sheet1.xml")
        assert_includes sheet, '<v>7.5</v>'
        assert_includes sheet, "Work &amp; &lt;review&gt;"
        assert_includes sheet, "SUM(E2:E2)"
        assert_includes archive.read("xl/styles.xml"), '[$-407]dd.mm.yyyy'
      end
      standalone = File.join(directory, "standalone.xlsx")
      command(environment, "generate_timesheet.rb", "--data", File.join(__dir__, "fixtures", "timesheet_rows.json"), "--output", standalone)
      assert File.file?(standalone)
      assert_equal pdf, command(environment, "generate_invoice.rb", "August 2026").strip
      if ENV["INVOICE_TEST_ARTIFACT_DIR"]
        destination = File.expand_path(ENV.fetch("INVOICE_TEST_ARTIFACT_DIR"))
        FileUtils.mkdir_p(destination)
        FileUtils.cp(pdf, File.join(destination, "invoice.pdf"))
        FileUtils.cp(xlsx, File.join(destination, "monthly-timesheet.xlsx"))
        FileUtils.cp(standalone, File.join(destination, "unicode-timesheet.xlsx"))
      end
    end
  end
end
