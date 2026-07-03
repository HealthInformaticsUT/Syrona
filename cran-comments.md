## Submission

This is a new submission.

## Test environments

* local: macOS (aarch64), R 4.6.0
* win-builder: R-devel
* R-hub: (linux, windows, macos)

## R CMD check results

0 errors | 0 warnings | 1 note

* checking CRAN incoming feasibility ... NOTE
  Maintainer: 'Maarja Pajusalu <maarja.pajusalu@ut.ee>'
  New submission

The note is the standard new-submission note.

## Notes for reviewers

* Examples that require a Shiny app launch are wrapped in \dontrun{}; the
  worked comparison example on compare_all() runs under \donttest{} using the
  bundled demo dataset in inst/extdata/demo (no database required).
* Database-dependent tests are skipped on CRAN (skip_on_cran()); they require a
  local OMOP CDM which is not available on the check machines.
