# Invoice Automation

A deterministic invoice and work-time toolkit with:

- a native macOS menu-bar timer;
- monthly time logs with timer/manual billing modes;
- self-contained XLSX timesheet generation;
- GST-aware invoice calculations; and
- editable HTML/CSS invoices rendered to PDF with Playwright.

No LLM or hosted service is required. All calculations, state transitions, and
document generation are implemented in the checked-in Ruby, JavaScript, and
Swift code. Ruby owns the backend, including invoice calculations and XLSX
generation; Swift provides the native UI and Node/Playwright renders PDFs.

## Project structure

```text
src/                  Ruby backend and Node PDF renderer
test/                 Ruby tests
  fixtures/           Synthetic invoice and timesheet baselines
templates/            Invoice HTML/CSS and timesheet XML/Unicode data
macos-timer/          Swift menu-bar app and app-bundle build script
Gemfile, Gemfile.lock Ruby dependencies
package.json          PDF renderer dependencies
```

Run the CLI and tests from the repository root using `ruby src/<command>.rb`
and `ruby test/<test_name>.rb`. The app bundle keeps the same `src/` and
`templates/` layout inside `Contents/Resources/Backend`.

## Requirements

- macOS 13 or later for the menu-bar app
- Ruby 2.6 or later, with Bundler for development builds
- Node.js 20 or later (development builds only; packaged in the app bundle)
- Swift 6 toolchain/Xcode command-line tools
- Optional: `curl` when Jira enrichment is enabled

## Setup

1. Install backend and renderer dependencies:

   ```sh
   bundle install --path vendor/bundle
   npm install
   npm run setup:renderer
   ```

2. Create a project config from `project-config.example.json`. Set its
   `outputDir` to the directory where invoice-month folders should be stored.

3. Register that existing config with the app, or with the CLI:

   ```sh
   ruby src/time_log.rb add-project CLIENT /path/to/project/config.json
   ```

4. Print the resolved paths:

   ```sh
   ruby src/time_log.rb storage-paths
   ```

   Keep the project config private. It can contain GSTINs, bank details,
   addresses, phone numbers, invoice history, and output paths.

## Usage

Generate a monthly invoice package:

```sh
ruby src/generate_month.rb "January 2026"
```

Generate an invoice directly:

```sh
ruby src/generate_invoice.rb "January 2026"
```

Use the timer CLI:

```sh
ruby src/time_log.rb status
ruby src/time_log.rb start
ruby src/time_log.rb pause
ruby src/time_log.rb finish
ruby src/time_log.rb discard
```

Build the menu-bar app:

```sh
cd macos-timer
./bundle_app.sh
open build/InvoiceTimer.app
```

The built app contains its backend, pinned Rubyzip dependency, renderer
dependencies, Node.js runtime, and headless Chromium. It can be moved out of the
checkout without losing access to the application code. It invokes Ruby from
macOS; Python, Bundler, and globally installed gems are not needed at runtime.

Rubyzip is locked to 2.4.1 for compatibility with Ruby 2.6. The build copies the
resolved gem into the app's private backend directory. The timesheet generator
preserves its XML layout under `templates/timesheet`, including a versioned
Unicode table used to estimate wrapped row heights.

## Configuration and privacy

Mutable application data is not stored in the source checkout. On macOS:

- project registry: `~/Library/Application Support/InvoiceTimer/config.json`
- project configs: read-only settings at the user-selected `configPath`
- invoice numbering: `sequence.json` under the project's `outputDir`
- invoice metadata and reimbursements: JSON files in each invoice-month directory
- timer logs and open-session state: the corresponding invoice-month directory under `outputDir`
- optional Jira snapshots: `~/Library/Caches/InvoiceTimer/projects/<key>/jira/`
- diagnostics: `~/Library/Logs/InvoiceTimer/`
- generated invoices/timesheets: the project's user-selected `outputDir`

On other Unix-like systems, the equivalent XDG data, cache, and state locations
are used. `ruby src/time_log.rb storage-paths` prints the exact resolved paths.

Each registry entry retains the absolute `configPath` selected when the project
was added. The app does not copy or create project configs. The selected
project config's `outputDir` determines where invoice-month folders, time logs,
PDFs, timesheets, and reimbursement attachments are stored. See
`config.example.json` and `project-config.example.json` for the supported shapes.

Use a separate `outputDir` for each project. Each invoice month is self-contained
under that directory:

```text
<outputDir>/
  sequence.json
  .sequence.lock
  001 September 2026/
    invoice.json
    timelog.json
    timelog.state.json             # only while a session is unfinished
    reimbursements.json
    reimbursements/
    001 Invoice - September 2026.pdf
    001 Timesheet - September 2026.xlsx
```

`sequence.json` contains `nextInvoiceNo` (an integer starting at 1) and an internal
`legacyImported` flag. Number allocation uses a file lock and atomic JSON writes.
An existing month's number is reused; a new month gets the next number regardless
of calendar order. Existing numbered folders prevent an interrupted allocation
or a stale counter from reusing a number. Keep the sequence file when backing up
or moving the output directory, and do not lower its counter.

`invoice.json` contains `month`, `invoiceNo`, and optional monthly `targetHours`
and `dailyTargetHours` overrides. `reimbursements.json` is an array of entries
with `id`, `name`, `amount`, and an optional relative `attachment` path. Hours and
invoice amounts are calculated from `timelog.json`, reimbursement entries, and
project settings. Successful invoice generation saves the values used in
`invoice.json` under `snapshot`; project config remains input only.

QRMP filing state is stored separately in `gst-filings.json` under `outputDir`.
Generated IFF and quarterly GSTR-1 JSON files are written under
`<outputDir>/returns/<quarter>/`. An IFF or GSTR-1 remains `generated` until it
is explicitly marked `filed`; generating a JSON file never records a portal filing.

### Invoice snapshots

Generation saves invoice identity and ISO dates, supplier/customer details,
service descriptions and SAC, hours and conversion rates, GST treatment and tax
breakdown, reimbursement amounts/treatment/attachment references, totals, locale,
and printed bank details. Decimal values are JSON strings. `snapshot.version`
and `generatedAt` identify the format and generation time. Display text is derived
from these structured values; no renderer context or draft/issued status is stored.
Credentials and the full config are not copied. Top-level `pdfSha256` identifies the corresponding PDF.

Normal generation creates or refreshes a snapshot only after rendering
succeeds. Older invoices are **not backfilled**. Explicitly regenerating an older
invoice creates its first snapshot from current inputs; it does not reconstruct
historical values from its old PDF. Merely reading an invoice or using the timer
does not create a snapshot.

To reproduce an invoice from its saved values, without recalculating from current
rates, tax settings, reimbursements, or time logs:

```sh
ruby src/generate_invoice.rb --reproduce "September 2026"
```

This requires an existing snapshot and preserves its saved billing values. It uses
the current HTML/CSS template, so layout and PDF bytes can differ after template
or renderer updates. Keep the original PDF for an exact archival copy. The active
project config is still used to locate the output directory.

Existing snapshots from the previous format remain readable. On explicit generation
or reproduction, obsolete `status` and `renderContext` fields are removed from
that invoice only. No older invoices are scanned or rewritten for this cleanup.
Monthly target overrides remain outside the snapshot.

Normal timer actions, target edits, reimbursements, and generation never write
the project config. The application registry still stores the active project
selection. The `sync` CLI command is retained for compatibility, but now only
returns recalculated hours and totals; it does not update config.

### Migrating existing projects

On first access to an output directory, existing `config.invoices` entries are
imported into monthly files. Their numbers, folder names, target overrides, and
reimbursements are retained. `TimeLog_<Month>_<Year>.json` and its `.state.json`
counterpart are renamed to `timelog.json` and `timelog.state.json`. Receipts and
existing PDFs/XLSX files stay in place. Conflicting files or duplicate invoice
numbers stop migration rather than overwrite data. After import, the legacy
config entries are ignored, so deleted reimbursements cannot reappear.

To also remove the legacy `invoices` property from the active project's config,
quit the old app and run this once from the repository root:

```sh
ruby src/time_log.rb migrate-storage
```

This explicitly requested command imports data if necessary, saves the original
config under `<outputDir>/.migration/`, and removes only the `invoices` property.
It can be rerun safely and prints the backup path when it edits config. Repeat
for each project after selecting it. Ordinary app operations never perform this
config cleanup themselves. Start the rebuilt app after migration; older versions
expect the previous time-log filenames and config storage.

## Document locale

Set `locale` at the root of the project JSON:

```json
"locale": "en-IN"
```

Omitting it preserves the existing `en-IN` output. Supported values are:

| Locale | Example amount | Example invoice date |
| --- | --- | --- |
| `en-IN` | `12,34,567.89` | `01 Sep 2026` |
| `en-US` | `1,234,567.89` | `Sep 01, 2026` |
| `de-DE` | `1.234.567,89` | `01.09.2026` |

The setting controls invoice amounts, decimal quantities/rates and displayed
dates, plus timesheet date formats. Money still uses two decimal places and
decimal half-up rounding. It does not change currencies, exchange rates, GST,
invoice calculations, English labels, or filenames. Timesheet hours and dates
remain numeric Excel cells; numeric separators are displayed by the spreadsheet
application according to its own settings.

Unsupported values (including an empty string or `null`) produce an error.
The standalone timesheet command also accepts `locale` in its input JSON beside
`rows`; monthly generation reads it from the project config.

## Invoice date

Set `invoiceDateTiming` in the project JSON to control the date printed on a
monthly invoice and saved in its snapshot:

```json
"invoiceDateTiming": "lastOfServiceMonth"
```

Supported values are:

- `firstOfFollowingMonth`: date an August invoice on September 1. This is the
  default and preserves existing configurations.
- `lastOfServiceMonth`: date an August invoice on August 31.

GSTR-1 export uses the saved invoice date to select its filing period. With
`lastOfServiceMonth`, generate the return for the service month; with the
default, generate it for the following month. Reproducing a saved snapshot
retains its original invoice date. Normal regeneration applies the project's
current setting.

## GST settings in the project JSON

Open the active project's JSON using **Open Config JSON** in the app. GST is
controlled by `taxProfile.type: "gst"`, the only supported tax type. Settings
apply per project. Generic settings (`enabled`, `effectiveFrom`, and
`amountsIncludeTax`) remain separate from GST-specific fields prefixed with `gst`.

For invoices without GST, omit `taxProfile` or use:

```json
"taxProfile": { "type": "gst", "enabled": false }
```

For GST, configure the start date, total percentage rate, and treatment. This
example uses a total 18% rate and the app's inter-state calculation:

```json
"taxProfile": {
  "type": "gst",
  "enabled": true,
  "effectiveFrom": "2026-08-01",
  "gstRatePercent": 18,
  "gstDefaultTreatment": "interState",
  "gstSacCode": "998314",
  "gstUqc": "NA",
  "amountsIncludeTax": false,
  "gstReverseCharge": false
}
```

| Field | How the app uses it |
| --- | --- |
| `type` | Use `"gst"`. Any other value is rejected, including on a disabled profile. |
| `enabled` | `true` enables the GST profile; `false` disables it. |
| `effectiveFrom` | Required `YYYY-MM-DD`. GST applies when the invoice month's first day is on or after this date. A mid-month date therefore starts GST with the next invoice month; the app does not prorate tax within a month. |
| `gstRatePercent` | Required total rate from 0 to 100. For `intraState`, the app divides this rate equally between CGST and SGST. |
| `gstDefaultTreatment` | Required calculation mode, listed below. |
| `gstSacCode` | Required for a GST invoice; a string of 4 or 6 digits. Not required when GST does not apply. |
| `gstSacDescription` | Optional display text. Omit it, use `null`, or leave it blank to print just the SAC code. It does not change tax calculations. |
| `gstUqc` | Required only for GSTR-1 JSON export. Use `"NA"` for service SAC codes; the exporter reports service quantity as zero as required by the current Offline Tool. |
| `amountsIncludeTax` | Required; currently only `false` is supported. Configured service amounts exclude tax. |
| `gstReverseCharge` | Required boolean. `true` suppresses the app's added tax rows and tax amount. |

Supported `gstDefaultTreatment` values:

| Value | Calculation when `gstReverseCharge` is `false` |
| --- | --- |
| `intraState` | CGST + SGST; supplier and client state codes must match. |
| `interState` | IGST; supplier and client state codes must differ. |
| `exportWithPayment` | IGST. |
| `exportWithoutPayment` | No added tax. |
| `exempt` | No added tax. |

The current GST invoice validator also requires `gst` details under **both**
`from` and `client`, including for the export modes:

```json
"gst": {
  "gstin": "08AAAAA0000A1Z5",
  "state": "Rajasthan",
  "stateCode": "08"
}
```

Use each party's own details. The validator checks that GSTIN is 15 characters,
`stateCode` is two digits, and the GSTIN prefix matches the state code. The app
does not currently support a GST invoice for a client without those details.

An optional description can be added inside `taxProfile`:

```json
"gstSacDescription": "Information technology design and development services"
```

`reimbursements.gstTreatment` separately controls whether reimbursements enter
the taxable value; see [Reimbursements](#reimbursements). After editing tax
settings, generate the invoice package again to recalculate its total
and PDF. The [complete example](project-config.example.json) shows the settings
in context. These examples are JSON fragments to place inside the project
config, not the project registry.

## GSTR-1 JSON export

Use **Generate GST** and choose **Current Return Period** or **Previous Return
Period**. The selected month is the GSTR-1 filing period. The app finds the
already-generated invoice dated in that month and writes
`<invoice number> GSTR-1 - <filing period>.json` beside its PDF, even when that
invoice is stored under the preceding service/work month.

The export uses the GST Returns Offline Tool 3.2.4 JSON envelope and contains
B2B, HSN B2B, and Documents Issued data. It currently supports regular
intra-state and inter-state GST invoices only. Invoices with reimbursements are
rejected, and cancelled documents are not represented.
The file can be checked with the official
[GST Returns Offline Tool](https://www.gst.gov.in/download/returns) before upload.

Existing configs remain compatible: a missing `type` is treated as `"gst"`,
and the old fields `defaultTreatment`, `sacCode`, `sacDescription`, `ratePercent`,
and `reverseCharge` are accepted as aliases for their `gst`-prefixed names.
Use the new names for new configs. Supplying both names with conflicting values
is an error. The app does not automatically rewrite existing project configs.

### QRMP and IFF

The GST dashboard includes a quarter-specific **Filing preference** control.
Choose **QRMP**, enable **Use IFF in the first two months**, and save it for the
applicable quarter. Later quarters inherit the latest saved preference; earlier
quarters retain their historical setting. A quarter's preference becomes
read-only after an IFF or GSTR-1 JSON has been generated or marked filed.

Project configuration can still provide the default used before any dashboard
preference has been saved:

```json
"gstFiling": {
  "scheme": "qrmp",
  "iff": "enabled"
}
```

Open **GST Dashboard** from the menu-bar app to select a filing period, review
invoice count, taxable value, output tax and total invoice value, and perform
the applicable IFF or GSTR-1 action. After the GST portal confirms a filing,
mark it filed in the dashboard. Filed periods are read-only, and filed IFF B2B
rows are excluded from the quarterly GSTR-1; an IFF that was merely generated
remains included.

IFF JSON contains only the supported B2B invoice section. Quarterly GSTR-1
includes B2B rows not already marked as filed through IFF, while its HSN summary
and Documents Issued section cover all generated invoices in the quarter.

The equivalent CLI commands are:

```sh
ruby src/time_log.rb generate-iff "October 2026"
ruby src/time_log.rb mark-iff-filed "October 2026"
ruby src/time_log.rb generate-gst "December 2026"
ruby src/time_log.rb mark-gstr1-filed "December 2026"
ruby src/time_log.rb gst-dashboard
ruby src/time_log.rb set-gst-preference "October 2026" qrmp enabled
```

The dashboard records local generation and user-confirmed portal filing. It
does not upload to the GST portal, verify portal status, calculate PMT-06 after
ITC, or file GSTR-3B.

For monthly filing, omit `gstFiling` or use `scheme: "monthly"` with
`iff: "disabled"`.

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
entries are stored in that month's `reimbursements.json`; totals are calculated
from these entries when requested or generated.

Build products, dependencies, caches, and editor metadata are ignored. Before
every release, review staged files with:

```sh
git status --short
git diff --cached
```

## Tests

```sh
ruby test/test_generate_invoice.rb
ruby test/test_document_locale.rb
ruby test/test_generate_timesheet.rb
ruby test/test_reimbursements.rb
ruby test/test_invoice_store.rb
ruby test/test_invoice_snapshot.rb
ruby test/test_jira_support.rb
ruby -c src/time_log.rb
ruby -c src/generate_month.rb
cd macos-timer && swift build
```

After installing the renderer, run the end-to-end generation test:

```sh
ruby test/test_generation_integration.rb
```

To verify the packaged backend after building the app:

```sh
INVOICE_TEST_BACKEND="$PWD/macos-timer/build/InvoiceTimer.app/Contents/Resources/Backend" ruby test/test_generation_integration.rb
```

The integration test uses synthetic project data and temporary storage. For the
packaged backend it clears installed-gem paths and blocks Python commands,
then exercises timer actions, monthly generation, and both standalone document
commands. Migration baselines in `test/fixtures` preserve the original invoice
results and spreadsheet XML. Invoice totals are shared between summaries,
reimbursements, and document generation; document-specific validation remains
required when rendering an invoice.

Storage tests cover legacy migration, read-only configs, unfinished timers,
duplicate/conflicting data, interrupted allocation, and concurrent numbering.

## License

No open-source license has been selected yet. Add a license before inviting
external contributors or reuse.
