require "minitest/autorun"
require "tmpdir"
require_relative "../src/ims_importer"
require_relative "../src/gst_filing"

class ImsImporterTest < Minitest::Test
  HEADERS = [
    "GSTIN of Supplier", "Trade/Legal name", "Invoice Number", "Invoice Type",
    "Invoice Date", "Invoice Value ", "Status", "Place of Supply", " Taxable Value ",
    "Integrated Tax ", "Central Tax ", "State/UT Tax ", "Cess ", "Remarks",
    " Source", "Source Return Period", "Source Filing Status",
    "Source Return Filing Date", "Filing Frequency of Supplier "
  ].freeze

  def setup
    @directory = Dir.mktmpdir("ims-import-test-")
    @config = { "outputDir" => File.join(@directory, "invoices") }
  end

  def teardown
    FileUtils.remove_entry(@directory)
  end

  def test_imports_real_portal_csv_shape_without_treating_it_as_final_itc
    GstInputTracker.add(
      @config, "September 2026", label: "September software", date: "2026-09-21",
      gst_amount: "18", total_amount: "118", status: "missing"
    )
    GstInputTracker.add(
      @config, "August 2026", label: "Still absent", date: "2026-08-10",
      gst_amount: "9", total_amount: "59", status: "missing"
    )
    path = write_ims_csv([
      row("29SUPPLIER0001Z1", "Software Ltd", "S-1", "21/09/2026", 118, 100, 18, "No Action", "09/2026", "Filed"),
      row("29SUPPLIER0002Z1", "Hosting Ltd", "H-1", "05/10/2026", 236, 200, 36, "Pending", "10/2026", "Not Filed")
    ])

    entry = ImsImporter.import(@config, "October 2026", path, now: Time.utc(2026, 10, 30, 10))
    summary = entry.fetch("summary")
    assert_equal "csv", entry.fetch("sourceFormat")
    assert_equal 2, summary.fetch("portalInvoiceCount")
    assert_equal 1, summary.fetch("matchedCount")
    assert_equal 1, summary.fetch("importedCount")
    assert_equal 1, summary.fetch("noActionCount")
    assert_equal 1, summary.fetch("pendingCount")
    assert_equal 1, summary.fetch("missingLocalCount")
    assert_equal 2, summary.fetch("newCount")

    september = GstInputTracker.month(@config, "September 2026")
    bill = september.fetch("bills").find { |candidate| candidate.fetch("label") == "September software" }
    assert_equal "missing", bill.fetch("status")
    assert_equal "no_action", bill.fetch("imsStatus")
    assert_equal 0.0, september.fetch("effectiveGst")

    october = GstInputTracker.month(@config, "October 2026")
    assert_equal 2, october.fetch("imsSeenCount")
    assert_equal 2, october.fetch("imsAwaiting2bCount")
    imported = october.fetch("bills").find { |candidate| candidate["invoiceNumber"] == "H-1" }
    assert_equal "missing", imported.fetch("status")
    assert imported.fetch("imsImported")

    write_ims_csv([
      row("29SUPPLIER0001Z1", "Software Ltd", "S-1", "21/09/2026", 118, 100, 18, "No Action", "09/2026", "Filed"),
      row("29SUPPLIER0002Z1", "Hosting Ltd", "H-1", "05/10/2026", 236, 200, 36, "Accepted", "10/2026", "Filed")
    ])
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

    gstr2b_path = File.join(@directory, "gstr2b.json")
    InvoiceStore.write_json(gstr2b_path, {
      "data" => { "fp" => "122026", "docdata" => { "b2b" => [
        portal_supplier("29SUPPLIER0001Z1", "Software Ltd", "S-1", "21-09-2026", 118, 100, 18),
        portal_supplier("29SUPPLIER0002Z1", "Hosting Ltd", "H-1", "05-10-2026", 236, 200, 36)
      ] } }
    })
    Gstr2bImporter.import(@config, "December 2026", gstr2b_path, now: Time.utc(2027, 1, 14, 10))
    assert_equal 0.0, GstInputTracker.month(@config, "September 2026").fetch("effectiveGst")
    assert_equal 54.0, GstInputTracker.month(@config, "December 2026").fetch("effectiveGst")
  end

  def test_rejects_non_ims_csv_and_wrong_recipient_filename
    invalid = File.join(@directory, "not-ims.csv")
    File.write(invalid, "label,amount\nTest,100\n")
    assert_raises(ImsImporter::ConfigError) { ImsImporter.parse_csv(invalid) }

    @config["from"] = { "gst" => { "gstin" => "08AAAAA0000A1Z5" } }
    path = write_ims_csv([
      row("29SUPPLIER0001Z1", "Software Ltd", "S-1", "21/09/2026", 118, 100, 18, "No Action", "09/2026", "Filed")
    ], gstin: "08BBBBB0000B1Z5")
    assert_raises(ImsImporter::ConfigError) do
      ImsImporter.import(@config, "October 2026", path)
    end
  end

  private

  def row(gstin, name, number, date, value, taxable, tax, status, source_period, filing_status)
    [
      gstin, name, number, "Regular", date, value, status, "Rajasthan", taxable,
      tax, 0, 0, 0, "", "GSTR-1/IFF", source_period, filing_status,
      filing_status == "Filed" ? "19/10/2026" : "NA", "Monthly"
    ]
  end

  def write_ims_csv(rows, gstin: "08AAAAA0000A1Z5")
    path = File.join(@directory, "IMS_B2B_#{gstin}_30102026.csv")
    CSV.open(path, "wb") do |csv|
      csv << ["Goods and Services Tax  - IMS"]
      csv << ["Taxable inward supplies received from registered persons"]
      csv << HEADERS
      rows.each { |row| csv << row }
    end
    path
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
end
