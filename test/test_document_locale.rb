require "minitest/autorun"
require_relative "../src/document_locale"
require_relative "../src/generate_invoice"
require_relative "../src/generate_timesheet"

class DocumentLocaleTest < Minitest::Test
  def test_defaults_and_validation
    assert_equal "en-IN", DocumentLocale.from_config({})
    [nil, "", "en_GB", "fr-FR", true].each do |locale|
      assert_raises(InvoiceCalculation::ConfigError) { DocumentLocale.from_config("locale" => locale) }
    end
  end

  def test_decimal_grouping_precision_and_sign
    { "en-IN" => "12,34,567.89", "en-US" => "1,234,567.89", "de-DE" => "1.234.567,89" }.each do |locale, expected|
      assert_equal expected, DocumentLocale.money("1234567.89", locale)
      assert_equal "-#{expected}", DocumentLocale.money("-1234567.89", locale)
    end
    assert_equal "0.00", DocumentLocale.money(0)
    assert_equal "1.01", DocumentLocale.money("1.005", "en-US")
    assert_equal "-1,01", DocumentLocale.money("-1.005", "de-DE")
    assert_equal "123.456.789.012.345,68", DocumentLocale.money("123456789012345.675", "de-DE")
    assert_equal "158,5", DocumentLocale.quantity("158.5", "de-DE")
    assert_equal "160", DocumentLocale.quantity(160, "de-DE")
  end

  def test_dates
    date = Date.new(2026, 9, 1)
    assert_equal "01 Sep 2026", DocumentLocale.date(date, "en-IN")
    assert_equal "Sep 01, 2026", DocumentLocale.date(date, "en-US")
    assert_equal "01.09.2026", DocumentLocale.date(date, "de-DE")
  end

  def test_locale_reaches_all_invoice_presentation_fields_without_changing_totals
    item = JSON.parse(File.read(File.join(__dir__, "fixtures", "invoice_cases.json"))).first
    config, record = item.values_at("config", "record")
    start, finish, date = InvoiceCalculation.parse_month(record["month"])
    original = InvoiceGenerator.calculate_invoice(config, record, start)
    config["locale"] = "de-DE"
    calc = InvoiceGenerator.calculate_invoice(config, record, start)
    assert_equal original, calc
    context = InvoiceGenerator.build_template_context(config, record, start, finish, date, calc)
    assert_equal "01.09.2026", context["invoice"]["date"]
    assert_equal "01.08.2026 - 31.08.2026", context["invoice"]["period"]
    assert_equal "158,555", context["items"][0]["quantity"]
    assert_equal DocumentLocale.money(calc["serviceAmount"], "de-DE"), context["items"][0]["amount"]
    assert_equal "998,01", context["items"][1]["amount"]
    assert_equal "25,015", context["rates"]["usd"]
    assert_equal "91,01", context["rates"]["exchange"]
    assert_equal DocumentLocale.money(calc["grandTotal"], "de-DE"), context["totals"]["grandTotal"]
    assert_equal DocumentLocale.money(calc["taxes"][0][2], "de-DE"), context["tax"]["rows"][0]["amount"]
  end

  def test_timesheet_localizes_date_style_without_changing_numeric_cells_or_formulas
    rows = [{ "date" => "2026-09-01", "hours" => 7.5 }]
    Dir.mktmpdir("locale-test-") do |directory|
      %w[en-US de-DE].each do |locale|
        path = File.join(directory, "#{locale}.xlsx")
        TimesheetGenerator.create_workbook(path, rows, locale: locale)
        Zip::File.open(path) do |archive|
          assert_equal TimesheetGenerator.worksheet_xml(rows).b, archive.read("xl/worksheets/sheet1.xml")
          assert_includes archive.read("xl/styles.xml"), DocumentLocale.profile(locale)[:excel_date]
        end
      end
    end
  end
end
