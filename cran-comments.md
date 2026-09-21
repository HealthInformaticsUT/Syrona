## Submission

This is a bug-fix update (0.2.1 -> 0.2.2), sent sooner than usual after the
0.2.1 release of 2026-09-04 because the documented way to connect to a local
database fails in 0.2.1.

`syrona_connect()` defaulted to `read_only = TRUE`, but CDMConnector validates
a CDM by writing a probe table, so the default always errored. This also
broke `extract_all()` when given a DuckDB file path. The default is now
`FALSE`, and the README and vignettes that showed the failing call are
corrected. There are no other functional changes.

## Test environments

* local: macOS (aarch64), R 4.6.0
* win-builder: R-devel (2026-09-21)

## R CMD check results

0 errors | 0 warnings | 0 notes

## Notes for reviewers

* run_app() launches a Shiny dashboard and blocks until the browser session
  ends, so its example is wrapped in if (interactive()) {} (as accepted in
  0.2.1).
* Database-dependent tests are skipped on CRAN (skip_on_cran()); they require a
  local OMOP CDM which is not available on the check machines.
