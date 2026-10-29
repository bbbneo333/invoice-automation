require "minitest/autorun"
require "tmpdir"
require_relative "../src/gstr2b_importer"

class Gstr2bImporterTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("gstr2b-import-test-")
    @config = { "outputDir" => File.join(@directory, "invoices") }
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_parses_official_style_json_and_reconciles_current_previous_and_untracked_bills
    add_bill("October 2026", "October hosting", "2026-10-04", "18", "118")
    add_bill("September 2026", "Old software", "2026-09-20", "36", "236")
    2.times { |index| add_bill("November 2026", "Duplicate #{index}", "2026-11-10", "9", "59") }
    path = write_json([
      portal_invoice("29SUPPLIER0001Z1", "Hosting Ltd", "H-1", "04-10-2026", 118, 100, 18),
      portal_invoice("29SUPPLIER0002Z1", "Software Ltd", "S-1", "20-09-2026", 236, 200, 36),
      portal_invoice("29SUPPLIER0003Z1", "New Vendor", "N-1", "12-12-2026", 354, 300, 54),
      portal_invoice("29SUPPLIER0004Z1", "Ambiguous Vendor", "A-1", "10-11-2026", 59, 50, 9),
      portal_invoice("29SUPPLIER0005Z1", "Ineligible Vendor", "I-1", "15-12-2026", 118, 100, 18, itc: "N")
    ])

    entry = Gstr2bImporter.import(@config, "December 2026", path, now: Time.utc(2027, 1, 14, 10))
    summary = entry.fetch("summary")
    assert_equal 5, summary.fetch("portalInvoiceCount")
    assert_equal 2, summary.fetch("matchedCount")
    assert_equal 2, summary.fetch("importedCount")
    assert_equal 1, summary.fetch("ambiguousCount")
    assert_equal 2, summary.fetch("missingLocalCount")
    assert_equal 1, summary.fetch("previousBillsResolvedCount")
    assert_equal 117.0, summary.fetch("portalGst")
    assert_equal 108.0, summary.fetch("representedGst")

    december = GstInputTracker.month(@config, "December 2026")
    assert_equal 108.0, december.fetch("effectiveGst")
    assert_equal 2, december.fetch("carriedInCount")
    assert_equal 1, december.fetch("ineligibleCount")
    october = GstInputTracker.month(@config, "October 2026")
    assert_equal 0.0, october.fetch("effectiveGst")
    assert_equal 1, october.fetch("resolvedLaterCount")

    first_count = GstInputTracker.read_state(@config).fetch("bills").length
    Gstr2bImporter.import(@config, "December 2026", path, now: Time.utc(2027, 1, 15, 10))
    assert_equal first_count, GstInputTracker.read_state(@config).fetch("bills").length
    assert_equal "December 2026", Gstr2bImporter.latest(@config, "December 2026").fetch("period")
  end

  def test_rejects_file_for_a_different_filing_period
    path = write_json([portal_invoice("29SUPPLIER0001Z1", "Hosting", "H-1", "04-10-2026", 118, 100, 18)], fp: "112026")
    error = assert_raises(Gstr2bImporter::ConfigError) do
      Gstr2bImporter.import(@config, "December 2026", path)
    end
    assert_includes error.message, "November 2026"
  end

  def test_parses_header_driven_xlsx_download
    path = File.join(@directory, "gstr2b.xlsx")
    headers = [
      "GSTIN of supplier", "Trade/Legal name", "Invoice number", "Invoice Date",
      "Invoice Value(₹)", "Taxable Value (₹)", "Integrated Tax(₹)",
      "Central Tax(₹)", "State/UT Tax(₹)", "Cess(₹)", "ITC Availability"
    ]
    values = ["29SUPPLIER0001Z1", "Hosting Ltd", "H-1", "04/10/2026", "118", "100", "0", "0", "18", "0", "Not Available"]
    Zip::File.open(path, create: true) do |archive|
      archive.get_output_stream("xl/worksheets/sheet1.xml") do |stream|
        stream.write worksheet_xml([headers, values])
      end
    end

    parsed = Gstr2bImporter.parse(path)
    invoice = parsed.fetch("invoices").first
    assert_equal "29SUPPLIER0001Z1", invoice.fetch("supplierGstin")
    assert_equal "H-1", invoice.fetch("invoiceNumber")
    assert_equal "2026-10-04", invoice.fetch("invoiceDate")
    assert_equal 118.0, invoice.fetch("invoiceValue")
    assert_equal 18.0, invoice.fetch("gstAmount")
    refute invoice.fetch("itcAvailable")
  end

  private

  def add_bill(month, label, date, gst, total)
    GstInputTracker.add(@config, month, label: label, date: date, gst_amount: gst, total_amount: total)
  end

  def portal_invoice(gstin, name, number, date, value, taxable, igst, itc: "Y")
    {
      "ctin" => gstin,
      "trdnm" => name,
      "inv" => [{
        "inum" => number,
        "dt" => date,
        "val" => value,
        "itcavl" => itc,
        "items" => [{ "txval" => taxable, "igst" => igst, "cgst" => 0, "sgst" => 0, "cess" => 0 }]
      }]
    }
  end

  def write_json(suppliers, fp: "122026")
    path = File.join(@directory, "gstr2b.json")
    InvoiceStore.write_json(path, { "data" => { "gstin" => "08RECIPIENT0001Z1", "fp" => fp, "docdata" => { "b2b" => suppliers } } })
    path
  end

  def worksheet_xml(rows)
    body = rows.each_with_index.map do |row, row_index|
      cells = row.each_with_index.map do |value, column_index|
        reference = "#{column_letters(column_index + 1)}#{row_index + 1}"
        %(<c r="#{reference}" t="inlineStr"><is><t>#{REXML::Text.normalize(value.to_s)}</t></is></c>)
      end.join
      %(<row r="#{row_index + 1}">#{cells}</row>)
    end.join
    %(<?xml version="1.0" encoding="UTF-8"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>#{body}</sheetData></worksheet>)
  end

  def column_letters(index)
    result = ""
    while index.positive?
      index -= 1
      result.prepend((65 + index % 26).chr)
      index /= 26
    end
    result
  end
end
