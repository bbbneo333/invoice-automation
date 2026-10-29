require "minitest/autorun"
require "tmpdir"
require_relative "../src/ims_importer"
require_relative "../src/gst_filing"

class ImsImporterTest < Minitest::Test
  def setup
    @directory = Dir.mktmpdir("ims-import-test-")
    @config = { "outputDir" => File.join(@directory, "invoices") }
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_imports_ims_snapshot_without_treating_it_as_final_itc
    GstInputTracker.add(
      @config, "September 2026", label: "September software", date: "2026-09-21",
      gst_amount: "18", total_amount: "118", status: "missing"
    )
    GstInputTracker.add(
      @config, "August 2026", label: "Still absent", date: "2026-08-10",
      gst_amount: "9", total_amount: "59", status: "missing"
    )
    path = write_ims_xlsx(
      "Accepted Records (B2B)" => [row("29SUPPLIER0001Z1", "Software Ltd", "S-1", "21/09/2026", 118, 100, 18)],
      "Pending Records (B2B)" => [row("29SUPPLIER0002Z1", "Hosting Ltd", "H-1", "05/10/2026", 236, 200, 36)]
    )

    entry = ImsImporter.import(@config, "October 2026", path, now: Time.utc(2026, 10, 30, 10))
    summary = entry.fetch("summary")
    assert_equal 2, summary.fetch("portalInvoiceCount")
    assert_equal 1, summary.fetch("matchedCount")
    assert_equal 1, summary.fetch("importedCount")
    assert_equal 1, summary.fetch("acceptedCount")
    assert_equal 1, summary.fetch("pendingCount")
    assert_equal 1, summary.fetch("missingLocalCount")
    assert_equal 2, summary.fetch("newCount")

    september = GstInputTracker.month(@config, "September 2026")
    bill = september.fetch("bills").find { |candidate| candidate.fetch("label") == "September software" }
    assert_equal "missing", bill.fetch("status")
    assert_equal "accepted", bill.fetch("imsStatus")
    assert_equal 0.0, september.fetch("effectiveGst")

    october = GstInputTracker.month(@config, "October 2026")
    assert_equal 2, october.fetch("imsSeenCount")
    assert_equal 2, october.fetch("imsAwaiting2bCount")
    imported = october.fetch("bills").find { |candidate| candidate["invoiceNumber"] == "H-1" }
    assert_equal "missing", imported.fetch("status")
    assert imported.fetch("imsImported")

    write_ims_xlsx(
      "Accepted Records (B2B)" => [
        row("29SUPPLIER0001Z1", "Software Ltd", "S-1", "21/09/2026", 118, 100, 18),
        row("29SUPPLIER0002Z1", "Hosting Ltd", "H-1", "05/10/2026", 236, 200, 36)
      ]
    )
    refreshed = ImsImporter.import(@config, "October 2026", path, now: Time.utc(2026, 10, 31, 10))
    assert_equal 0, refreshed.dig("summary", "newCount")
    assert_equal 1, refreshed.dig("summary", "changedCount")
    assert_equal 0, refreshed.dig("summary", "removedCount")
    assert_equal 3, GstInputTracker.read_state(@config).fetch("bills").length

    dashboard = GstFiling.dashboard(@config, now: Time.local(2026, 11, 14, 9))
    october = dashboard.fetch("periods").find { |period| period.fetch("month") == "October 2026" }
    ims_task = october.fetch("checklist").find { |item| item.fetch("id") == "imsImport" }
    assert_equal "attention", ims_task.fetch("status")
    assert_equal "importIms", ims_task.fetch("action")
    assert_equal "Download current IMS Excel and reconcile October 2026 purchase bills", ims_task.fetch("title")

    gstr2b_path = File.join(@directory, "gstr2b.json")
    InvoiceStore.write_json(gstr2b_path, {
      "data" => {
        "fp" => "122026",
        "docdata" => {
          "b2b" => [
            portal_supplier("29SUPPLIER0001Z1", "Software Ltd", "S-1", "21-09-2026", 118, 100, 18),
            portal_supplier("29SUPPLIER0002Z1", "Hosting Ltd", "H-1", "05-10-2026", 236, 200, 36)
          ]
        }
      }
    })
    Gstr2bImporter.import(@config, "December 2026", gstr2b_path, now: Time.utc(2027, 1, 14, 10))
    assert_equal 0.0, GstInputTracker.month(@config, "September 2026").fetch("effectiveGst")
    assert_equal 54.0, GstInputTracker.month(@config, "December 2026").fetch("effectiveGst")
  end

  private

  def row(gstin, name, number, date, value, taxable, state_tax)
    [gstin, name, number, date, value.to_s, taxable.to_s, "0", "0", state_tax.to_s, "0"]
  end

  def portal_supplier(gstin, name, number, date, value, taxable, igst)
    {
      "ctin" => gstin, "trdnm" => name,
      "inv" => [{
        "inum" => number, "dt" => date, "val" => value, "itcavl" => "Y",
        "items" => [{ "txval" => taxable, "igst" => igst }]
      }]
    }
  end

  def headers
    [
      "GSTIN of supplier", "Trade/Legal name", "Invoice number", "Invoice Date",
      "Invoice Value(₹)", "Taxable Value (₹)", "Integrated Tax(₹)",
      "Central Tax(₹)", "State/UT Tax(₹)", "Cess(₹)"
    ]
  end

  def write_ims_xlsx(sheets)
    path = File.join(@directory, "ims.xlsx")
    FileUtils.rm_f(path)
    Zip::File.open(path, create: true) do |archive|
      workbook_sheets = []
      relationships = []
      sheets.each_with_index do |(name, rows), index|
        number = index + 1
        archive.get_output_stream("xl/worksheets/sheet#{number}.xml") do |stream|
          stream.write worksheet_xml([headers, *rows])
        end
        workbook_sheets << %(<sheet name="#{REXML::Text.normalize(name)}" sheetId="#{number}" r:id="rId#{number}"/>)
        relationships << %(<Relationship Id="rId#{number}" Type="worksheet" Target="worksheets/sheet#{number}.xml"/>)
      end
      archive.get_output_stream("xl/workbook.xml") do |stream|
        stream.write %(<?xml version="1.0"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets>#{workbook_sheets.join}</sheets></workbook>)
      end
      archive.get_output_stream("xl/_rels/workbook.xml.rels") do |stream|
        stream.write %(<?xml version="1.0"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">#{relationships.join}</Relationships>)
      end
    end
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
    %(<?xml version="1.0"?><worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"><sheetData>#{body}</sheetData></worksheet>)
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
