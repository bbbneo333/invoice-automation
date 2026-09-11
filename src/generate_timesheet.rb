require "date"
require "json"
require "fileutils"
require "optparse"
require "tempfile"
require_relative "backend_dependencies"
require_relative "document_locale"

module TimesheetGenerator
  COLUMN_WIDTHS = { "A" => 13, "B" => 18, "C" => 44, "D" => 18, "E" => 11, "F" => 11, "G" => 36 }.freeze
  MIN_BODY_ROW_HEIGHT = 22
  LINE_HEIGHT = 15
  VERTICAL_PADDING = 7
  MAX_BODY_ROW_HEIGHT = 300
  EXCEL_WIDTH_TO_TEXT_UNITS = 1.2
  TEMPLATE_DIR = File.expand_path("../templates/timesheet", __dir__)
  STATIC_PARTS = %w[[Content_Types].xml _rels/.rels xl/workbook.xml xl/_rels/workbook.xml.rels xl/styles.xml].freeze
  UNICODE_WIDTHS = JSON.parse(File.read(File.join(TEMPLATE_DIR, "unicode_widths.json"))).freeze

  module_function

  def escape_xml(value)
    value.to_s.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;")
  end

  def inline_cell(reference, value, style = 0)
    text = escape_xml(value)
    whitespace_edge = !text.empty? && (unicode_property?(text[0], "space") || unicode_property?(text[-1], "space"))
    preserve = whitespace_edge ? ' xml:space="preserve"' : ""
    %(<c r="#{reference}" s="#{style}" t="inlineStr"><is><t#{preserve}>#{text}</t></is></c>)
  end

  def number_cell(reference, value, style = 0)
    %(<c r="#{reference}" s="#{style}"><v>#{value}</v></c>)
  end

  def formula_cell(reference, formula, style = 0)
    %(<c r="#{reference}" s="#{style}"><f>#{escape_xml(formula)}</f></c>)
  end

  def unicode_property?(character, property)
    codepoint = character.ord
    range = UNICODE_WIDTHS.fetch(property).bsearch { |_, last| last >= codepoint }
    range && range.first <= codepoint
  end

  def character_width(character)
    return 4 if character == "\t"
    return 0.55 if unicode_property?(character, "space")
    return 2 if unicode_property?(character, "wide")
    return 1.08 if unicode_property?(character, "upper")
    return 0.5 if "ilI.,:;'|!".include?(character)
    return 1.35 if "mwMW@#%&".include?(character)
    1
  end

  def wrapped_line_count(value, column_width)
    text = value.nil? || value == false ? "" : value.to_s
    return 1 if text.empty?
    usable_width = [(column_width - 1.5) * EXCEL_WIDTH_TO_TEXT_UNITS, 1].max
    # A negative limit preserves trailing blank lines, as Python split does.
    text.split("\n", -1).sum do |paragraph|
      current_width = 0
      lines = 1
      paragraph.each_char do |character|
        width = character_width(character)
        if current_width.positive? && current_width + width > usable_width
          lines += 1
          current_width = 0
        end
        current_width += width
      end
      lines
    end
  end

  def body_row_height(item)
    fields = { "B" => "taskCategory", "C" => "taskDescription", "D" => "ticketRef", "F" => "billable", "G" => "notes" }
    lines = fields.map { |column, key| wrapped_line_count(item.fetch(key, key == "billable" ? "Y" : ""), COLUMN_WIDTHS[column]) }.max
    [[lines * LINE_HEIGHT + VERTICAL_PADDING, MIN_BODY_ROW_HEIGHT].max, MAX_BODY_ROW_HEIGHT].min
  end

  def worksheet_xml(rows)
    headers = ["Date", "Task Category", "Task Description", "Ticket/Ref", "Hours", "Billable", "Notes"]
    sheet_rows = ['<row r="1" ht="28" customHeight="1">' + COLUMN_WIDTHS.keys.zip(headers).map { |column, header| inline_cell("#{column}1", header, 1) }.join + "</row>"]
    rows.each_with_index do |item, index|
      row_number = index + 2
      work_date = Date.iso8601(item.fetch("date"))
      cells = [
        number_cell("A#{row_number}", (work_date - Date.new(1899, 12, 30)).to_i, 2),
        inline_cell("B#{row_number}", item.fetch("taskCategory", "")),
        inline_cell("C#{row_number}", item.fetch("taskDescription", "")),
        inline_cell("D#{row_number}", item.fetch("ticketRef", "")),
        number_cell("E#{row_number}", item.fetch("hours"), 3),
        inline_cell("F#{row_number}", item.fetch("billable", "Y")),
        inline_cell("G#{row_number}", item.fetch("notes", ""))
      ]
      sheet_rows << %(<row r="#{row_number}" ht="#{body_row_height(item)}" customHeight="1">#{cells.join}</row>)
    end
    total_row = rows.length + 2
    formula = rows.empty? ? "0" : "SUM(E2:E#{total_row - 1})"
    sheet_rows << %(<row r="#{total_row}" ht="24" customHeight="1">#{inline_cell("D#{total_row}", "Total", 4)}#{formula_cell("E#{total_row}", formula, 5)}</row>)
    columns = COLUMN_WIDTHS.each_with_index.map do |(_, width), index|
      %(<col min="#{index + 1}" max="#{index + 1}" width="#{width}" customWidth="1"/>)
    end.join
    <<~XML.chomp
      <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
      <worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
        <sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>
        <dimension ref="A1:G#{total_row}"/>
        <sheetViews><sheetView showGridLines="0" workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
        <sheetFormatPr defaultRowHeight="20"/>
        <cols>
          #{columns}
        </cols>
        <sheetData>#{sheet_rows.join}</sheetData>
        <autoFilter ref="A1:G#{[1, rows.length + 1].max}"/>
        <pageMargins left="0.3" right="0.3" top="0.5" bottom="0.5" header="0.2" footer="0.2"/>
        <pageSetup orientation="landscape" paperSize="9" fitToWidth="1" fitToHeight="0"/>
      </worksheet>
    XML
  end

  def create_workbook(output_path, rows, locale: DocumentLocale::DEFAULT)
    date_format = DocumentLocale.profile(locale).fetch(:excel_date)
    output_path = File.expand_path(output_path)
    FileUtils.mkdir_p(File.dirname(output_path))
    parts = STATIC_PARTS.map { |name| [name, File.read(File.join(TEMPLATE_DIR, name), encoding: "UTF-8")] }.to_h
    parts["xl/styles.xml"] = parts.fetch("xl/styles.xml").sub('formatCode="dd mmm yyyy"', %(formatCode="#{date_format}"))
    parts["xl/worksheets/sheet1.xml"] = worksheet_xml(rows)
    temporary = Tempfile.new(["timesheet-", ".xlsx"], File.dirname(output_path))
    temporary_path = temporary.path
    temporary.close
    begin
      Zip::OutputStream.open(temporary_path) do |archive|
        parts.each do |name, content|
          archive.put_next_entry(name)
          archive.write(content)
        end
      end
      File.rename(temporary_path, output_path)
    ensure
      temporary.close!
    end
    output_path
  end
end

if $PROGRAM_NAME == __FILE__
  begin
    options = {}
    parser = OptionParser.new do |opts|
      opts.banner = "Usage: ruby src/generate_timesheet.rb --output FILE.xlsx --data FILE.json"
      opts.on("--output PATH") { |path| options[:output] = path }
      opts.on("--data PATH") { |path| options[:data] = path }
    end
    parser.parse!
    raise OptionParser::MissingArgument, "--output and --data are required" unless options[:output] && options[:data]
    raise OptionParser::InvalidArgument, ARGV.join(" ") unless ARGV.empty?
    payload = JSON.parse(File.read(options[:data]))
    puts TimesheetGenerator.create_workbook(options[:output], payload.fetch("rows"), locale: DocumentLocale.from_config(payload))
  rescue OptionParser::ParseError, SystemCallError, JSON::ParserError, KeyError, ArgumentError, Zip::Error => error
    warn "Timesheet generation failed: #{error.message}"
    exit 1
  end
end
