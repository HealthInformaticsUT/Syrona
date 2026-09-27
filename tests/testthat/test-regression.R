# Value snapshots of extract_all() results. A snapshot is stored in
# tests/testthat/_snaps/regression.md the first time a test runs, and every
# later run must reproduce it exactly.

test_that("extract_all() on GiBleed reproduces its value snapshot", {
  db <- get_test_db()
  on.exit(cleanup_test_db(db))

  tables <- suppressMessages(extract_all("GiBleed_snapshot", db = db, save = FALSE))

  expect_snapshot_value(table_fingerprints(tables), style = "json2")
})

test_that("extract_all() with a cohort from a schema table reproduces its value snapshot", {
  db <- get_test_pg("reader")
  on.exit(syrona_disconnect(db))

  # atlas_results.cohort on the test server: cohort 1403 = persons with an even person_id
  tables <- suppressMessages(extract_all(
    "Cohort_snapshot", db = db,
    cohort_id = 1403, cohort_schema = "atlas_results",
    save = FALSE
  ))

  expect_snapshot_value(table_fingerprints(tables), style = "json2")
})
