# syrona (development version)

## Breaking changes

* Connections are read-only by default: no write schema, and DuckDB files are opened read-only.
* `insert_cohort()`, `create_caresite_cohort()` and `delete_cohort()` are removed. Use a cohort in the database, or `extract_all(care_site_id = )`.
* A cohort is read only where you name it (`cohort_schema`, `cohort_table`), and a cohort with overlapping entries is refused.
* A saved dataset or comparison is only replaced with `overwrite = TRUE`.

## New

* `extract_all(care_site_id = )` call made easier.
* `cohort_table` reads any OHDSI cohort table, including cohorts generated from ATLAS JSON.
* `CodeToRun.R` runs the whole path as one script.
* Vignettes written clearer.

## Fixes

* Cohorts in a database schema can be read on DuckDB.
* A dataset with only women can be compared.
* Temporary tables cannot replace a table of yours with the same name.
* The dashboard's packages are installed with Syrona.

# syrona 0.2.1

## CRAN review fixes
* Removed single quotes around the OMOP CDM acronym in Title and Description.
* Documented the return value of `load_syrona_theme()`, `run_app()` and
  `syrona_disconnect()`.
* Replaced the `\dontrun{}` example on `run_app()` with an `if (interactive())`
  block.
* `run_app()` now restores the user's `syrona.data_dir` option on exit, and the
  examples reset any option they set.

# syrona 0.2.0

## New features
* Added a bundled demo dataset (`inst/extdata/demo`): a curated 32-concept subset
  (conditions, procedures, drugs) that runs the full comparison workflow with no
  database. See `RUN_DEMO.html` or `?compare_all` for a runnable example.
* `compare_all()` now ships a runnable `\donttest` example driven by the demo data.

## Improvements
* Shipped standard-vocabulary lookups in `inst/extdata/` so a fresh install has a
  working conditions chapter map and procedure device/site/morphology enrichment
  (`icd10_lookup.csv` and `vocabulary/*.csv`, resolved via `syrona_extdata()`).
* Dashboard "About" panel now documents all four procedure attribute filters
  (site, method, device, morphology) and corrects the Sex/Age filter behavior
  (display-only; the meta-analysis is precomputed).
* Population pyramids degrade gracefully with an explanatory message when a
  dataset has no demographics table (e.g. the demo).
* DESCRIPTION metadata polished for CRAN (Paule-Mandel
  reference DOI, `Depends: R (>= 4.1.0)`).

## Bug fixes
* Corrected the fold-threshold glossary wording (similarity boundary, not a
  clinical-relevance boundary).
