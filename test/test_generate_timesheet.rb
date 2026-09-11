require "minitest/autorun"
require "tmpdir"
require "rexml/document"
require_relative "../src/generate_timesheet"

class TimesheetGenerationTest < Minitest::Test
  FIXTURES = File.join(__dir__, "fixtures")

  def rows
    JSON.parse(File.read(File.join(FIXTURES, "timesheet_rows.json"))).fetch("rows")
  end

  def test_generated_archive_contents_match_python_baseline
    Dir.mktmpdir("timesheet-test-") do |directory|
      path = File.join(directory, "Timesheet & Unicode 日本語.xlsx")
      TimesheetGenerator.create_workbook(path, rows)
      Zip::File.open(path) do |archive|
        assert_equal (TimesheetGenerator::STATIC_PARTS + ["xl/worksheets/sheet1.xml"]).sort, archive.entries.map(&:name).sort
        TimesheetGenerator::STATIC_PARTS.each do |name|
          assert_equal File.binread(File.join(TimesheetGenerator::TEMPLATE_DIR, name)), archive.read(name)
          assert REXML::Document.new(archive.read(name)).root
        end
        assert_equal File.binread(File.join(FIXTURES, "timesheet_expected.xml")), archive.read("xl/worksheets/sheet1.xml")
      end
    end
  end

  def test_empty_sheet_has_non_circular_total
    actual = TimesheetGenerator.worksheet_xml([])
    assert_equal File.read(File.join(FIXTURES, "timesheet_empty_expected.xml")), actual
    xml = REXML::Document.new(actual)
    assert_equal "0", REXML::XPath.first(xml, "//c[@r='E2']/f").text
  end

  def test_cells_formulas_layout_and_wrapping
    xml = REXML::Document.new(TimesheetGenerator.worksheet_xml(rows))
    assert_equal "7.5", REXML::XPath.first(xml, "//c[@r='E2']/v").text
    assert_equal "SUM(E2:E6)", REXML::XPath.first(xml, "//c[@r='E7']/f").text
    assert_equal "frozen", REXML::XPath.first(xml, "//pane").attributes["state"]
    assert_equal "landscape", REXML::XPath.first(xml, "//pageSetup").attributes["orientation"]
    assert_equal rows[1]["taskDescription"], REXML::XPath.first(xml, "//c[@r='C3']/is/t").text
    assert_equal "preserve", REXML::XPath.first(xml, "//c[@r='G3']/is/t").attributes["xml:space"]
    heights = REXML::XPath.match(xml, "//row").map { |row| [row.attributes["r"], row.attributes["ht"].to_f] }.to_h
    assert_operator heights["4"], :>, heights["2"]
    assert_equal TimesheetGenerator::MAX_BODY_ROW_HEIGHT, heights["6"]
  end

  def test_text_starting_with_equals_stays_text
    xml = REXML::Document.new(TimesheetGenerator.worksheet_xml([{ "date" => "2026-08-01", "hours" => 1, "notes" => '=HYPERLINK("example")' }]))
    cell = REXML::XPath.first(xml, "//c[@r='G2']")
    assert_equal "inlineStr", cell.attributes["t"]
    assert_nil cell.elements["f"]
  end

  def test_unicode_widths_and_trailing_blank_lines
    { "\t" => 4, "\u00a0" => 0.55, "界" => 2, "Ａ" => 2, "😀" => 2, "M" => 1.08, "i" => 0.5, "m" => 1.35, "\u0301" => 1 }.each do |character, width|
      assert_equal width, TimesheetGenerator.character_width(character)
    end
    assert_equal 3, TimesheetGenerator.wrapped_line_count("text\n\n", 44)
  end

  def test_failed_write_preserves_existing_workbook_and_cleans_temporary_file
    Dir.mktmpdir("timesheet-failure-") do |directory|
      path = File.join(directory, "timesheet.xlsx")
      TimesheetGenerator.create_workbook(path, rows)
      original = File.binread(path)
      failure = ->(*) { raise IOError, "Simulated disk failure" }
      Zip::OutputStream.stub(:open, failure) do
        assert_raises(IOError) { TimesheetGenerator.create_workbook(path, []) }
      end
      assert_equal original, File.binread(path)
      assert_equal ["timesheet.xlsx"], Dir.children(directory)
      TimesheetGenerator.create_workbook(path, [])
      Zip::File.open(path) { |archive| assert_equal TimesheetGenerator.worksheet_xml([]).b, archive.read("xl/worksheets/sheet1.xml") }
    end
  end
end
