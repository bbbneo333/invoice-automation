require "fileutils"
require "json"
require "rbconfig"

module AppPaths
  APP_NAME = "InvoiceTimer"

  module_function

  def macos?
    RbConfig::CONFIG["host_os"].match?(/darwin/i)
  end

  def home
    Dir.home
  end

  def data_dir
    @data_dir ||= expand_override("INVOICE_AUTOMATION_DATA_DIR") || if macos?
      File.join(home, "Library", "Application Support", APP_NAME)
    else
      File.join(ENV.fetch("XDG_DATA_HOME", File.join(home, ".local", "share")), APP_NAME)
    end
  end

  def log_dir
    @log_dir ||= expand_override("INVOICE_AUTOMATION_LOG_DIR") || if macos?
      File.join(home, "Library", "Logs", APP_NAME)
    else
      File.join(ENV.fetch("XDG_STATE_HOME", File.join(home, ".local", "state")), APP_NAME, "logs")
    end
  end

  def cache_dir
    @cache_dir ||= expand_override("INVOICE_AUTOMATION_CACHE_DIR") || if macos?
      File.join(home, "Library", "Caches", APP_NAME)
    else
      File.join(ENV.fetch("XDG_CACHE_HOME", File.join(home, ".cache")), APP_NAME)
    end
  end

  def registry_path
    File.expand_path(ENV.fetch("INVOICE_AUTOMATION_CONFIG", File.join(data_dir, "config.json")))
  end

  def error_log_path
    File.expand_path(ENV.fetch("INVOICE_AUTOMATION_ERROR_LOG", File.join(log_dir, "error.log")))
  end

  def project_jira_cache_dir(storage_key)
    File.join(cache_dir, "projects", storage_key, "jira")
  end

  def ensure_base_directories!
    [data_dir, cache_dir, log_dir, File.dirname(registry_path), File.dirname(error_log_path)].uniq.each do |path|
      FileUtils.mkdir_p(path)
    end
  end

  def ensure_registry!
    ensure_base_directories!
    return if File.exist?(registry_path)

    File.write(registry_path, JSON.pretty_generate("projects" => []) + "\n")
  end

  def expand_override(name)
    value = ENV[name]
    value && !value.strip.empty? ? File.expand_path(value) : nil
  end
end
