import os
import tempfile
import unittest
import zipfile
import xml.etree.ElementTree as ET

from generate_timesheet import MAX_BODY_ROW_HEIGHT, create_workbook


NS = {"a": "http://schemas.openxmlformats.org/spreadsheetml/2006/main"}


class TimesheetGenerationTests(unittest.TestCase):
    def test_standalone_workbook_contains_rows_and_total_formula(self):
        rows = [
            {
                "date": "2026-08-14",
                "taskCategory": "Development",
                "taskDescription": "Implement invoice export",
                "ticketRef": "APP-42",
                "hours": 7.5,
                "billable": "Y",
                "notes": "Client work",
            },
            {
                "date": "2026-08-15",
                "taskCategory": "Bug Fix",
                "taskDescription": "Fix rounding",
                "ticketRef": "APP-43",
                "hours": 2,
                "billable": "Y",
                "notes": "",
            },
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "timesheet.xlsx")
            create_workbook(path, rows)
            self.assertTrue(zipfile.is_zipfile(path))
            with zipfile.ZipFile(path) as workbook:
                self.assertIn("xl/worksheets/sheet1.xml", workbook.namelist())
                root = ET.fromstring(workbook.read("xl/worksheets/sheet1.xml"))

        self.assertEqual(root.find("a:dimension", NS).attrib["ref"], "A1:G4")
        self.assertIsNotNone(root.find("a:autoFilter", NS))
        formula = root.find(".//a:c[@r='E4']/a:f", NS)
        self.assertEqual(formula.text, "SUM(E2:E3)")
        hours = root.find(".//a:c[@r='E2']/a:v", NS)
        self.assertEqual(hours.text, "7.5")

    def test_empty_workbook_has_non_circular_zero_total(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "empty.xlsx")
            create_workbook(path, [])
            with zipfile.ZipFile(path) as workbook:
                root = ET.fromstring(workbook.read("xl/worksheets/sheet1.xml"))
        formula = root.find(".//a:c[@r='E2']/a:f", NS)
        self.assertEqual(formula.text, "0")

    def test_body_row_height_adapts_to_wrapped_content_in_any_text_column(self):
        rows = [
            {
                "date": "2026-08-14", "taskCategory": "Development",
                "taskDescription": "Short description", "ticketRef": "APP-1",
                "hours": 1, "billable": "Y", "notes": "Short note",
            },
            {
                "date": "2026-08-15", "taskCategory": "Development",
                "taskDescription": "A detailed description " * 18, "ticketRef": "APP-2",
                "hours": 1, "billable": "Y", "notes": "Short note",
            },
            {
                "date": "2026-08-16", "taskCategory": "Development",
                "taskDescription": "Short description", "ticketRef": "APP-3",
                "hours": 1, "billable": "Y", "notes": "First line\nSecond line\nThird line",
            },
        ]
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "adaptive-rows.xlsx")
            create_workbook(path, rows)
            with zipfile.ZipFile(path) as workbook:
                root = ET.fromstring(workbook.read("xl/worksheets/sheet1.xml"))

        heights = {
            row.attrib["r"]: float(row.attrib["ht"])
            for row in root.findall(".//a:row", NS)
        }
        self.assertGreater(heights["3"], heights["2"])
        self.assertGreater(heights["4"], heights["2"])
        self.assertLessEqual(heights["3"], MAX_BODY_ROW_HEIGHT)

    def test_table_styles_define_full_cell_borders(self):
        with tempfile.TemporaryDirectory() as directory:
            path = os.path.join(directory, "bordered.xlsx")
            create_workbook(path, [{
                "date": "2026-08-14", "taskCategory": "Development",
                "taskDescription": "Task", "ticketRef": "APP-1",
                "hours": 1, "billable": "Y", "notes": "",
            }])
            with zipfile.ZipFile(path) as workbook:
                styles = ET.fromstring(workbook.read("xl/styles.xml"))

        borders = styles.find("a:borders", NS)
        self.assertEqual(borders.attrib["count"], "3")
        body_border = list(borders)[1]
        for edge in ("left", "right", "top", "bottom"):
            self.assertEqual(body_border.find(f"a:{edge}", NS).attrib["style"], "thin")


if __name__ == "__main__":
    unittest.main()
