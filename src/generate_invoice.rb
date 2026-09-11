require "json"
require "fileutils"
require "open3"
require "tmpdir"
require "time"
require_relative "app_paths"
require_relative "invoice_calculation"
require_relative "document_locale"
require_relative "time_log"

module InvoiceGenerator
  ConfigError = InvoiceCalculation::ConfigError
  BASE_DIR = File.expand_path("..", __dir__)
  RENDERER_PATH = File.join(__dir__, "render_invoice.mjs")
  TEMPLATE_PATH = File.join(BASE_DIR, "templates", "invoice.html")

  module_function

  def active_config_path
    registry = JSON.parse(File.read(AppPaths.registry_path))
    projects = InvoiceCalculation.field(registry, "projects", Array)
    active = projects.select { |project| project["active"] }
    raise ConfigError, "Exactly one project in config.json must have active=true" unless active.length == 1
    InvoiceCalculation.field(active.first, "configPath", String)
  end

  def calculate_invoice(config, record, period_start)
    InvoiceCalculation.calculate(config, record, period_start, validate_document: true, check_amount: true)
  end

  def quantity_format(value)
    DocumentLocale.quantity(value)
  end

  def build_template_context(config, record, period_start, period_end, invoice_date, calc)
    locale = DocumentLocale.from_config(config)
    tax_profile = InvoiceCalculation.tax_profile(config) if calc["taxEnabled"]
    bank = config["bank"]
    %w[name holder account ifsc].each { |key| InvoiceCalculation.field(bank, key, String) } unless bank.nil?
    items = [{
      "description" => "Development & Implementation",
      "detail" => "Refer to attached timesheet for work log and hours",
      "sacCode" => calc["taxEnabled"] ? tax_profile["gstSacCode"] : nil,
      "sacDescription" => calc["taxEnabled"] ? tax_profile["gstSacDescription"]&.strip : nil,
      "quantity" => DocumentLocale.quantity(calc["hours"], locale),
      "amount" => DocumentLocale.money(calc["serviceAmount"], locale)
    }]
    items.concat(calc["reimbursements"].map do |item|
      {
        "description" => "Reimbursement - #{item['name']}", "detail" => "",
        "sacCode" => nil, "sacDescription" => nil, "quantity" => "-", "amount" => DocumentLocale.money(item["amount"], locale)
      }
    end)
    tax_rows = calc["taxes"].map do |name, rate, amount|
      { "name" => name, "rate" => DocumentLocale.quantity(rate, locale), "amount" => DocumentLocale.money(amount, locale) }
    end
    {
      "title" => "INVOICE", "supplier" => config["from"], "client" => config["client"],
      "invoice" => {
        "number" => record["invoiceNo"], "date" => DocumentLocale.date(invoice_date, locale),
        "period" => "#{DocumentLocale.date(period_start, locale)} - #{DocumentLocale.date(period_end, locale)}"
      },
      "items" => items, "tax" => { "enabled" => calc["taxEnabled"], "rows" => tax_rows },
      "totals" => { "taxableValue" => DocumentLocale.money(calc["taxableValue"], locale), "grandTotal" => DocumentLocale.money(calc["grandTotal"], locale) },
      "rates" => { "usd" => DocumentLocale.quantity(config["rateUsd"], locale), "exchange" => DocumentLocale.money(config["exchRate"], locale) },
      "bank" => bank
    }
  end

  def find_node
    nvm_nodes = Dir.glob(File.expand_path("~/.nvm/versions/node/*/bin/node"))
      .sort_by { |path| path.split("/versions/node/v", 2).last.split("/", 2).first.split(".").map(&:to_i) }.reverse
    path_nodes = ENV.fetch("PATH", "").split(File::PATH_SEPARATOR).map { |dir| File.join(dir, "node") }
    candidates = [ENV["INVOICE_NODE"], File.join(BASE_DIR, "runtime", "node"), *nvm_nodes, *path_nodes]
    candidates.compact.uniq.each do |candidate|
      next unless File.file?(candidate) && File.executable?(candidate)
      version, status = Open3.capture2(candidate, "--version", err: File::NULL)
      return candidate if status.success? && version.strip.match?(/\Av\d+\./) && version.delete_prefix("v").to_i >= 20
    rescue SystemCallError
      next
    end
    raise ConfigError, "Node.js 20 or newer was not found. Set INVOICE_NODE to a compatible executable."
  end

  def render_invoice(context, output_path)
    raise ConfigError, "Invoice template not found: #{TEMPLATE_PATH}" unless File.file?(TEMPLATE_PATH)
    raise ConfigError, "Invoice renderer not found: #{RENDERER_PATH}" unless File.file?(RENDERER_PATH)
    Dir.mktmpdir("invoice-render-") do |directory|
      data_path = File.join(directory, "invoice.json")
      File.write(data_path, JSON.generate(context))
      stdout, stderr, status = Open3.capture3(find_node, RENDERER_PATH, "--data", data_path, "--output", output_path)
      raise "Invoice rendering failed: #{stderr.empty? ? stdout : stderr}" unless status.success?
    end
  end

  def decimal_string(value)
    InvoiceCalculation.decimal_value(value, "snapshot value").to_s("F")
  end

  def build_snapshot(config, record, period_start, period_end, invoice_date, calc, context)
    tax = calc["taxEnabled"] ? InvoiceCalculation.tax_profile(config) : {}
    treatment = config.fetch("reimbursements", {}).fetch("gstTreatment", "excludedFromTaxableValue")
    snapshot = {
      "version" => 1, "generatedAt" => Time.now.utc.iso8601(6),
      "invoiceNo" => record.fetch("invoiceNo"), "invoiceDate" => invoice_date.iso8601,
      "periodStart" => period_start.iso8601, "periodEnd" => period_end.iso8601,
      "currency" => "INR", "locale" => DocumentLocale.from_config(config),
      "supplier" => config.fetch("from").select { |key, _| %w[name address email phone gst].include?(key) },
      "customer" => config.fetch("client").select { |key, _| %w[name address email phone gst].include?(key) },
      "bank" => config["bank"]&.select { |key, _| %w[name holder account ifsc].include?(key) },
      "service" => {
        "description" => context["items"][0]["description"], "detail" => context["items"][0]["detail"],
        "sacCode" => tax["gstSacCode"], "sacDescription" => tax["gstSacDescription"],
        "hours" => decimal_string(calc["hours"]), "rateUsd" => decimal_string(config["rateUsd"]),
        "exchangeRate" => decimal_string(config["exchRate"]), "rateInr" => decimal_string(calc["rateInr"]),
        "amount" => decimal_string(calc["serviceAmount"])
      },
      "gst" => {
        "enabled" => calc["taxEnabled"], "treatment" => calc["treatment"],
        "placeOfSupply" => %w[intraState interState].include?(calc["treatment"]) ? config.dig("client", "gst", "stateCode") : nil,
        "reverseCharge" => tax.fetch("gstReverseCharge", false),
        "ratePercent" => tax["gstRatePercent"] && decimal_string(tax["gstRatePercent"]),
        "taxes" => calc["taxes"].map { |name, rate, amount| { "name" => name, "ratePercent" => decimal_string(rate), "amount" => decimal_string(amount) } }
      },
      "reimbursements" => calc["reimbursements"].each_with_index.map do |item, index|
        { "name" => item["name"], "amount" => decimal_string(item["amount"]),
          "gstTreatment" => treatment, "attachment" => record.fetch("reimbursements", [])[index]["attachment"] }
      end,
      "totals" => %w[serviceAmount subtotal taxableValue excludedReimbursements taxTotal grandTotal].to_h { |key| [key, decimal_string(calc[key])] }
    }
    JSON.parse(JSON.generate(snapshot))
  end

  def snapshot_context(snapshot)
    locale = snapshot.fetch("locale")
    service, gst, totals = snapshot.values_at("service", "gst", "totals")
    items = [{
      "description" => service.fetch("description"), "detail" => service.fetch("detail"),
      "sacCode" => service["sacCode"], "sacDescription" => service["sacDescription"]&.strip,
      "quantity" => DocumentLocale.quantity(service.fetch("hours"), locale),
      "amount" => DocumentLocale.money(service.fetch("amount"), locale)
    }]
    items.concat(snapshot.fetch("reimbursements").map do |item|
      { "description" => "Reimbursement - #{item.fetch('name')}", "detail" => "",
        "sacCode" => nil, "sacDescription" => nil, "quantity" => "-",
        "amount" => DocumentLocale.money(item.fetch("amount"), locale) }
    end)
    {
      "title" => "INVOICE", "supplier" => snapshot.fetch("supplier"), "client" => snapshot.fetch("customer"),
      "invoice" => {
        "number" => snapshot.fetch("invoiceNo"), "date" => DocumentLocale.date(Date.iso8601(snapshot.fetch("invoiceDate")), locale),
        "period" => "#{DocumentLocale.date(Date.iso8601(snapshot.fetch('periodStart')), locale)} - #{DocumentLocale.date(Date.iso8601(snapshot.fetch('periodEnd')), locale)}"
      },
      "items" => items,
      "tax" => { "enabled" => gst.fetch("enabled"), "rows" => gst.fetch("taxes").map do |tax|
        { "name" => tax.fetch("name"), "rate" => DocumentLocale.quantity(tax.fetch("ratePercent"), locale),
          "amount" => DocumentLocale.money(tax.fetch("amount"), locale) }
      end },
      "totals" => { "taxableValue" => DocumentLocale.money(totals.fetch("taxableValue"), locale), "grandTotal" => DocumentLocale.money(totals.fetch("grandTotal"), locale) },
      "rates" => { "usd" => DocumentLocale.quantity(service.fetch("rateUsd"), locale), "exchange" => DocumentLocale.money(service.fetch("exchangeRate"), locale) },
      "bank" => snapshot["bank"]
    }
  rescue KeyError, NoMethodError, ArgumentError => error
    raise ConfigError, "Invalid invoice snapshot: #{error.message}"
  end

  def generate(month_label, reproduce: false)
    config = JSON.parse(File.read(active_config_path))
    store = InvoiceStore.new(config)
    record = store.find(month_label)
    if reproduce
      snapshot = record && record["snapshot"]
      unless snapshot.is_a?(Hash) && snapshot["version"] == 1
        raise ConfigError, "No supported snapshot exists for #{month_label}; older invoices are not backfilled"
      end
    else
      record = TimeLog.invoice_data(month_label, config)
      period_start, period_end, invoice_date = InvoiceCalculation.parse_month(month_label)
      calc = calculate_invoice(config, record, period_start)
      context = build_template_context(config, record, period_start, period_end, invoice_date, calc)
      snapshot = build_snapshot(config, record, period_start, period_end, invoice_date, calc, context)
    end
    snapshot = snapshot.reject { |key, _| key == "renderContext" }
    output_dir = store.directory(record)
    output_path = File.join(output_dir, "#{record['invoiceNo']} Invoice - #{month_label}.pdf")
    Dir.mktmpdir("invoice-publish-", output_dir) do |directory|
      rendered = File.join(directory, "invoice.pdf")
      render_invoice(snapshot_context(snapshot), rendered)
      store.save_generation(month_label, snapshot, rendered, output_path, reproduce: reproduce)
    end
    output_path
  end

end

if $PROGRAM_NAME == __FILE__
  reproduce = !!ARGV.delete("--reproduce")
  abort('Usage: ruby src/generate_invoice.rb [--reproduce] "August 2026"') if ARGV.empty?
  begin
    puts InvoiceGenerator.generate(ARGV.join(" "), reproduce: reproduce)
  rescue InvoiceGenerator::ConfigError, SystemCallError, JSON::ParserError, RuntimeError => error
    warn "Invoice generation failed: #{error.message}"
    exit 1
  end
end
