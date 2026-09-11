# Migration baselines

These synthetic fixtures were captured from the Python generators before their
replacement with Ruby. They contain no project or customer data.

- `invoice_cases.json`: calculation results and renderer contexts for all five
  tax treatments, both reverse-charge settings, both reimbursement policies,
  fractional input/rounding, pre-GST and zero-hour invoices.
- `timesheet_rows.json`: ordinary, multiline, XML-special, Unicode and long text.
- `timesheet_expected.xml` and `timesheet_empty_expected.xml`: exact worksheet
  XML from the original generator. Static workbook parts are preserved under
  `templates/timesheet`.

Do not regenerate expected values from the Ruby implementation under test.
Changing an established output requires reviewing the expected difference.

`templates/timesheet/unicode_widths.json` freezes the original generator's
Unicode 15.0.0 wide/fullwidth, whitespace and uppercase classifications. The
table preserves its row-height heuristic across Ruby/Unicode versions; it is
data, not a Python runtime dependency. Update it only alongside reviewed layout
changes and representative Unicode fixtures.
