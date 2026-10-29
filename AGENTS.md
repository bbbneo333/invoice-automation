# Repository instructions

## Testing

- Do not run Chrome/Chromium or PDF-generation end-to-end tests for changes
  that do not affect invoice rendering.
- Test calculation, configuration, and invoice-date changes by calling the
  relevant Ruby script or module directly and by running focused unit tests.
- Invoice PDF generation is not required to validate non-rendering changes.
