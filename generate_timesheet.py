#!/usr/bin/env python3
import argparse
import json
import os
import tempfile
import unicodedata
import zipfile
from datetime import date, datetime
from xml.sax.saxutils import escape


COLUMN_WIDTHS = {
    "A": 13,
    "B": 18,
    "C": 44,
    "D": 18,
    "E": 11,
    "F": 11,
    "G": 36,
}

MIN_BODY_ROW_HEIGHT = 22
LINE_HEIGHT = 15
VERTICAL_PADDING = 7
MAX_BODY_ROW_HEIGHT = 300
EXCEL_WIDTH_TO_TEXT_UNITS = 1.2


def parse_args():
    parser = argparse.ArgumentParser(description="Create a standalone XLSX timesheet from daily timer rows.")
    parser.add_argument("--output", required=True, help="Destination .xlsx path")
    parser.add_argument("--data", required=True, help="Daily timer-row JSON path")
    return parser.parse_args()


def excel_serial(value):
    return (value - date(1899, 12, 30)).days


def inline_cell(reference, value, style=0):
    text = escape(str(value))
    preserve = ' xml:space="preserve"' if text != text.strip() else ""
    return f'<c r="{reference}" s="{style}" t="inlineStr"><is><t{preserve}>{text}</t></is></c>'


def number_cell(reference, value, style=0):
    return f'<c r="{reference}" s="{style}"><v>{value}</v></c>'


def formula_cell(reference, formula, style=0):
    return f'<c r="{reference}" s="{style}"><f>{escape(formula)}</f></c>'


def character_width(character):
    if character == "\t":
        return 4
    if character.isspace():
        return 0.55
    if unicodedata.east_asian_width(character) in {"W", "F"}:
        return 2
    if character.isupper():
        return 1.08
    if character in "ilI.,:;'|!":
        return 0.5
    if character in "mwMW@#%&":
        return 1.35
    return 1


def wrapped_line_count(value, column_width):
    text = str(value or "")
    if not text:
        return 1

    usable_width = max((column_width - 1.5) * EXCEL_WIDTH_TO_TEXT_UNITS, 1)
    lines = 0
    for paragraph in text.split("\n"):
        if not paragraph:
            lines += 1
            continue

        current_width = 0
        paragraph_lines = 1
        for character in paragraph:
            width = character_width(character)
            if current_width and current_width + width > usable_width:
                paragraph_lines += 1
                current_width = 0
            current_width += width
        lines += paragraph_lines
    return max(lines, 1)


def body_row_height(item):
    values_by_column = {
        "B": item.get("taskCategory", ""),
        "C": item.get("taskDescription", ""),
        "D": item.get("ticketRef", ""),
        "F": item.get("billable", "Y"),
        "G": item.get("notes", ""),
    }
    required_lines = max(
        wrapped_line_count(value, COLUMN_WIDTHS[column])
        for column, value in values_by_column.items()
    )
    calculated = required_lines * LINE_HEIGHT + VERTICAL_PADDING
    return min(max(calculated, MIN_BODY_ROW_HEIGHT), MAX_BODY_ROW_HEIGHT)


def worksheet_xml(rows):
    headers = ["Date", "Task Category", "Task Description", "Ticket/Ref", "Hours", "Billable", "Notes"]
    sheet_rows = [
        '<row r="1" ht="28" customHeight="1">'
        + "".join(inline_cell(f"{column}1", header, 1) for column, header in zip("ABCDEFG", headers))
        + "</row>"
    ]

    for row_number, item in enumerate(rows, start=2):
        work_date = datetime.fromisoformat(item["date"]).date()
        description = item.get("taskDescription", "")
        notes = item.get("notes", "")
        height = body_row_height(item)
        cells = [
            number_cell(f"A{row_number}", excel_serial(work_date), 2),
            inline_cell(f"B{row_number}", item.get("taskCategory", "")),
            inline_cell(f"C{row_number}", description),
            inline_cell(f"D{row_number}", item.get("ticketRef", "")),
            number_cell(f"E{row_number}", item["hours"], 3),
            inline_cell(f"F{row_number}", item.get("billable", "Y")),
            inline_cell(f"G{row_number}", notes),
        ]
        sheet_rows.append(f'<row r="{row_number}" ht="{height}" customHeight="1">{"".join(cells)}</row>')

    total_row = len(rows) + 2
    total_formula = f"SUM(E2:E{total_row - 1})" if rows else "0"
    sheet_rows.append(
        f'<row r="{total_row}" ht="24" customHeight="1">'
        + inline_cell(f"D{total_row}", "Total", 4)
        + formula_cell(f"E{total_row}", total_formula, 5)
        + "</row>"
    )
    last_row = total_row
    return f'''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <sheetPr><pageSetUpPr fitToPage="1"/></sheetPr>
  <dimension ref="A1:G{last_row}"/>
  <sheetViews><sheetView showGridLines="0" workbookViewId="0"><pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/></sheetView></sheetViews>
  <sheetFormatPr defaultRowHeight="20"/>
  <cols>
    {''.join(f'<col min="{index}" max="{index}" width="{COLUMN_WIDTHS[column]}" customWidth="1"/>' for index, column in enumerate("ABCDEFG", start=1))}
  </cols>
  <sheetData>{''.join(sheet_rows)}</sheetData>
  <autoFilter ref="A1:G{max(1, len(rows) + 1)}"/>
  <pageMargins left="0.3" right="0.3" top="0.5" bottom="0.5" header="0.2" footer="0.2"/>
  <pageSetup orientation="landscape" paperSize="9" fitToWidth="1" fitToHeight="0"/>
</worksheet>'''


STYLES_XML = '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">
  <numFmts count="2"><numFmt numFmtId="164" formatCode="dd mmm yyyy"/><numFmt numFmtId="165" formatCode="0.00"/></numFmts>
  <fonts count="2">
    <font><sz val="11"/><color theme="1"/><name val="Aptos"/><family val="2"/></font>
    <font><b/><sz val="11"/><color rgb="FFFFFFFF"/><name val="Aptos Display"/><family val="2"/></font>
  </fonts>
  <fills count="3"><fill><patternFill patternType="none"/></fill><fill><patternFill patternType="gray125"/></fill><fill><patternFill patternType="solid"><fgColor rgb="FF334155"/><bgColor indexed="64"/></patternFill></fill></fills>
  <borders count="3">
    <border/>
    <border>
      <left style="thin"><color rgb="FFCBD5E1"/></left>
      <right style="thin"><color rgb="FFCBD5E1"/></right>
      <top style="thin"><color rgb="FFCBD5E1"/></top>
      <bottom style="thin"><color rgb="FFCBD5E1"/></bottom>
    </border>
    <border>
      <left style="thin"><color rgb="FF475569"/></left>
      <right style="thin"><color rgb="FF475569"/></right>
      <top style="thin"><color rgb="FF475569"/></top>
      <bottom style="thin"><color rgb="FF475569"/></bottom>
    </border>
  </borders>
  <cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>
  <cellXfs count="6">
    <xf numFmtId="0" fontId="0" fillId="0" borderId="1" xfId="0" applyAlignment="1"><alignment vertical="top" wrapText="1"/></xf>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="2" xfId="0" applyAlignment="1"><alignment vertical="center"/></xf>
    <xf numFmtId="164" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment vertical="top"/></xf>
    <xf numFmtId="165" fontId="0" fillId="0" borderId="1" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="right" vertical="top"/></xf>
    <xf numFmtId="0" fontId="1" fillId="2" borderId="2" xfId="0" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
    <xf numFmtId="165" fontId="1" fillId="2" borderId="2" xfId="0" applyNumberFormat="1" applyAlignment="1"><alignment horizontal="right" vertical="center"/></xf>
  </cellXfs>
  <cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>
</styleSheet>'''


def create_workbook(output_path, rows):
    os.makedirs(os.path.dirname(os.path.abspath(output_path)), exist_ok=True)
    parts = {
        "[Content_Types].xml": '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/><Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/><Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/></Types>''',
        "_rels/.rels": '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/></Relationships>''',
        "xl/workbook.xml": '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"><sheets><sheet name="Timesheet" sheetId="1" r:id="rId1"/></sheets></workbook>''',
        "xl/_rels/workbook.xml.rels": '''<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/><Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/></Relationships>''',
        "xl/styles.xml": STYLES_XML,
        "xl/worksheets/sheet1.xml": worksheet_xml(rows),
    }
    with tempfile.NamedTemporaryFile(suffix=".xlsx", delete=False, dir=os.path.dirname(os.path.abspath(output_path))) as temporary:
        temporary_path = temporary.name
    try:
        with zipfile.ZipFile(temporary_path, "w", zipfile.ZIP_DEFLATED) as workbook:
            for name, content in parts.items():
                workbook.writestr(name, content)
        os.replace(temporary_path, output_path)
    finally:
        if os.path.exists(temporary_path):
            os.unlink(temporary_path)


def main():
    args = parse_args()
    with open(args.data, encoding="utf-8") as stream:
        payload = json.load(stream)
    create_workbook(args.output, payload["rows"])
    print(args.output)


if __name__ == "__main__":
    main()
