# InvoiceTimer

Tiny macOS menu bar timer for the invoice automation tool.

The app is a UI shell around bundled Ruby commands. On launch and after
every action it calls:

```bash
ruby time_log.rb status
```

from `Contents/Resources/Backend` in a packaged app. Development runs fall back
to the checkout or `INVOICE_AUTOMATION_HOME`. Ruby owns the active project, current month,
invoice folder bootstrap, time-log file format, and config sync.

The project registry lives under macOS Application Support. Each registry entry
retains the selected external project `configPath`. `Open Config JSON` opens the
active project config, and the `Project` submenu switches projects or registers
an existing config file.

## Run During Development

```bash
swift run InvoiceTimer
```

## Build App Bundle

```bash
./bundle_app.sh
```

The app bundle is written to:

```text
macos-timer/build/InvoiceTimer.app
```
