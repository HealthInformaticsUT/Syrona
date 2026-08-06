## Submission

This is a resubmission of a new submission (0.2.0 -> 0.2.1), addressing the
points raised in the CRAN review of 2026-08-06.

## Test environments

* local: macOS (aarch64), R 4.6.0
* win-builder: R Under development (unstable) (2026-07-26 r90304 ucrt)

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE
  Maintainer: 'Maarja Pajusalu <maarja.pajusalu@ut.ee>'
  New submission

The note is the standard new-submission note.

## Notes for reviewers

* All four review points are addressed: single quotes removed from the OMOP CDM
  acronym in Title and Description; \value added to load_syrona_theme(),
  run_app() and syrona_disconnect(); \dontrun{} removed; and the user's options
  are restored.
* run_app() launches a Shiny dashboard and blocks until the browser session
  ends, so its example cannot run unattended under \donttest{}. Following the
  CRAN cookbook, the example is now wrapped in if (interactive()) {} instead of
  \dontrun{}.
* run_app() sets options(syrona.data_dir = ...) so the bundled app's global.R
  can locate the data; the previous value is captured and restored with an
  immediate on.exit() call. Every example that sets an option resets it.
* The worked comparison example on compare_all() runs under \donttest{} using
  the bundled demo dataset in inst/extdata/demo (no database required).
* Database-dependent tests are skipped on CRAN (skip_on_cran()); they require a
  local OMOP CDM which is not available on the check machines.
