require "json"
require "fileutils"
require "open3"
require "tmpdir"
require_relative "app_paths"
require_relative "invoice_calculation"
require_relative "document_locale"

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

  def generate(month_label)
    config = JSON.parse(File.read(active_config_path))
    matches = config.fetch("invoices", []).select { |record| record["month"] == month_label }
    raise ConfigError, "Expected exactly one invoice record for #{month_label}" unless matches.length == 1
    record = matches.first
    InvoiceCalculation.field(record, "invoiceNo", String)
    period_start, period_end, invoice_date = InvoiceCalculation.parse_month(month_label)
    calc = calculate_invoice(config, record, period_start)
    output_dir = File.join(InvoiceCalculation.field(config, "outputDir", String), "#{record['invoiceNo']} #{month_label}")
    FileUtils.mkdir_p(output_dir)
    output_path = File.join(output_dir, "#{record['invoiceNo']} Invoice - #{month_label}.pdf")
    render_invoice(build_template_context(config, record, period_start, period_end, invoice_date, calc), output_path)
    output_path
  end
end

if $PROGRAM_NAME == __FILE__
  abort('Usage: ruby src/generate_invoice.rb "August 2026"') if ARGV.empty?
  begin
    puts InvoiceGenerator.generate(ARGV.join(" "))
  rescue InvoiceGenerator::ConfigError, SystemCallError, JSON::ParserError, RuntimeError => error
    warn "Invoice generation failed: #{error.message}"
    exit 1
  end
end
