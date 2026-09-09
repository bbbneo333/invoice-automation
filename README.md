# Invoice Automation

A deterministic invoice and work-time toolkit with:

- a native macOS menu-bar timer;
- monthly time logs with timer/manual billing modes;
- self-contained XLSX timesheet generation;
- GST-aware invoice calculations; and
- editable HTML/CSS invoices rendered to PDF with Playwright.

No LLM or hosted service is required. All calculations, state transitions, and
document generation are implemented in the checked-in Ruby, Python, JavaScript,
and Swift code.

## Requirements

- macOS 13 or later for the menu-bar app
- Ruby
- Python 3
- Node.js 20 or later (development builds only; packaged in the app bundle)
- Swift 6 toolchain/Xcode command-line tools
- Optional: `curl` when Jira enrichment is enabled

## Setup

1. Install renderer dependencies:

   ```sh
   npm install
   npm run setup:renderer
   ```

2. Create a project config from `project-config.example.json`. Set its
   `outputDir` to the directory where invoice-month folders should be stored.

3. Register that existing config with the app, or with the CLI:

   ```sh
   ruby time_log.rb add-project CLIENT /path/to/project/config.json
   ```

4. Print the resolved paths:

   ```sh
   ruby time_log.rb storage-paths
   ```

   Keep the project config private. It can contain GSTINs, bank details,
   addresses, phone numbers, invoice history, and output paths.

## Usage

Generate a monthly invoice package:

```sh
ruby generate_month.rb "January 2026"
```

Generate an invoice directly:

```sh
python3 generate_invoice.py "January 2026"
```

Use the timer CLI:

```sh
ruby time_log.rb status
ruby time_log.rb start
ruby time_log.rb pause
ruby time_log.rb finish
ruby time_log.rb discard
```

Build the menu-bar app:

```sh
cd macos-timer
./bundle_app.sh
open build/InvoiceTimer.app
```

The built app contains its backend, renderer dependencies, Node.js runtime, and
headless Chromium. It can be moved out of the checkout without losing access to
the application code. Ruby and Python are invoked from macOS for the current
backend implementation.

## Configuration and privacy

Mutable application data is not stored in the source checkout. On macOS:

- project registry: `~/Library/Application Support/InvoiceTimer/config.json`
- project configs: remain at the user-selected `configPath`
- timer logs and open-session state: the corresponding invoice-month directory under `outputDir`
- optional Jira snapshots: `~/Library/Caches/InvoiceTimer/projects/<key>/jira/`
- diagnostics: `~/Library/Logs/InvoiceTimer/`
- generated invoices/timesheets: the project's user-selected `outputDir`

On other Unix-like systems, the equivalent XDG data, cache, and state locations
are used. `ruby time_log.rb storage-paths` prints the exact resolved paths.

Each registry entry retains the absolute `configPath` selected when the project
was added. The app does not copy or create project configs. The selected
project config's `outputDir` determines where invoice-month folders, time logs,
PDFs, timesheets, and reimbursement attachments are stored. See
`config.example.json` and `project-config.example.json` for the supported shapes.

Each invoice month is self-contained under the configured output directory:

```text
<outputDir>/<invoiceNo> <Month>/
  TimeLog_<Month>_<Year>.json
  TimeLog_<Month>_<Year>.state.json   # only while a session is unfinished
  <invoiceNo> Invoice - <Month>.pdf
  <invoiceNo> Timesheet - <Month>.xlsx
  reimbursements/
```

Invoice generation reads the monthly time log directly from this directory.

## Optional Jira enrichment

Jira is disabled by default and is not required for timing, manual billed-hour
overrides, GST calculations, invoices, or PDF generation. Enable it per project
by adding/filling the `jira` object in the private project config:

```json
{
  "jira": {
    "enabled": true,
    "domain": "your-company",
    "email": "you@example.com",
    "apiToken": "your-jira-api-token",
    "assignee": "currentUser",
    "issueTypes": ["Story", "Task", "Bug"],
    "inProgressStatus": "In Progress",
    "doneStatus": "Done"
  }
}
```

`domain` is the Atlassian site prefix from
`https://<domain>.atlassian.net`. `assignee` may be `currentUser` or
`accountId:<Jira account ID>`.

Enabling Jira means that monthly generation:

1. connects to the configured Atlassian REST API;
2. fetches matching issues and their status histories for the invoice month;
3. writes a regenerable issue snapshot to the project cache directory;
4. matches each billed timer date to issues active on that date; and
5. fills the timesheet category, description, and ticket reference from Jira.

Story and Task issues map to `Development`; Bug issues map to `Bug Fix`. If no
issue overlaps a billed date, the nearest issue in that month is used. Jira data
never changes timer duration, billed hours, invoice amounts, or tax calculations.

Generation fails fast when Jira is enabled but its configuration is incomplete
or the API request fails. Set `enabled` back to `false` to generate locally with
blank task/category/reference cells.

The API token is currently stored in the private project config under
Application Support. Protect that file and never commit it. macOS Keychain
storage is not implemented yet.

## Reimbursements

Reimbursements use one project-level GST policy:

```json
{
  "reimbursements": {
    "gstTreatment": "excludedFromTaxableValue"
  }
}
```

The supported values are `excludedFromTaxableValue` and
`includedInTaxableValue`. Every reimbursement in that project follows the same
policy.

In the menu-bar app, open `Reimbursements`, choose Current Month or Previous
Month, and select `Add Reimbursement…`. Each entry contains only:

- a required name;
- a positive INR amount; and
- an optional supporting attachment.

The attachment is copied without parsing or modification to:

```text
<outputDir>/<invoiceNo> <Month>/reimbursements/<original filename>
```

Duplicate destination filenames are rejected. The app does not scan folders,
extract invoice data, infer amounts, or reconcile files with config. Removing an
entry also removes its copied attachment after confirmation. Reimbursement
changes recalculate the configured invoice amount immediately.

Build products, dependencies, caches, and editor metadata are ignored. Before
every release, review staged files with:

```sh
git status --short
git diff --cached
```

## Tests

```sh
python3 -m unittest test_generate_invoice.py test_generate_timesheet.py
ruby test_reimbursements.rb
ruby test_jira_support.rb
ruby -c time_log.rb
ruby -c generate_month.rb
cd macos-timer && swift build
```

## License

No open-source license has been selected yet. Add a license before inviting
external contributors or reuse.
