## Submission

This is a minor release (0.2.1 -> 0.3.0). Syrona now only reads the database:
connections are read-only by default, and the functions that wrote cohort
tables are removed. The removed functions are kept as defunct stubs whose
error message says what to use instead. Details are in NEWS.md.

There are no reverse dependencies on CRAN.

## Test environments

* local: macOS (aarch64), R 4.6.0 (filled in at the release gate)
* win-builder: R-devel (filled in at the release gate)

## R CMD check results

0 errors | 0 warnings | 0 notes (filled in at the release gate)

## Notes for reviewers

* run_app() launches a Shiny dashboard and blocks until the browser session
  ends, so its example is wrapped in if (interactive()) {} (as accepted in
  0.2.1).
* Database-dependent tests are skipped on CRAN (skip_on_cran()); they require a
  local OMOP CDM, which is not available on the check machines.
* The vignette code is not evaluated (eval = FALSE) for the same reason. It is
  checked outside CRAN against test databases.
