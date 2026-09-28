# Read-only cohort and care-site helpers

add_results_cohort <- function(con) {
  DBI::dbExecute(con, "CREATE SCHEMA results")
  DBI::dbExecute(con, "CREATE TABLE results.cohort (cohort_definition_id INTEGER, subject_id INTEGER,
                        cohort_start_date DATE, cohort_end_date DATE)")
  DBI::dbExecute(con, "INSERT INTO results.cohort VALUES
                        (99, 1, '2000-01-01', '2005-12-31'), (99, 1, '2010-01-01', '2012-12-31'),
                        (99, 2, '2001-01-01', '2020-12-31'), (98, 3, '2000-01-01', '2020-12-31'),
                        (97, 5, '2000-01-01', '2005-01-01'), (97, 5, '2004-01-01', '2006-01-01'),
                        (96, 6, '2003-01-01', '2004-01-01'), (96, 6, '2003-01-01', '2008-01-01')")
  # Cohort 97 has overlapping entries, cohort 96 two entries on the same start date
  DBI::dbExecute(con, "CREATE TABLE results.bad (cohort_definition_id INTEGER, subject_id INTEGER,
                        cohort_start_date DATE)")
  DBI::dbExecute(con, "INSERT INTO results.bad VALUES (99, 1, '2000-01-01')")
  # A cohort table with another name (3 persons), and an unrelated table "cohort" in main (500 persons)
  DBI::dbExecute(con, "CREATE TABLE results.my_cohorts AS
                        SELECT 7 AS cohort_definition_id, person_id AS subject_id,
                               DATE '1900-01-01' AS cohort_start_date, DATE '2100-12-31' AS cohort_end_date
                        FROM person ORDER BY person_id LIMIT 3")
  add_unrelated_cohort(con)
}

add_unrelated_cohort <- function(con) {
  DBI::dbExecute(con, "CREATE TABLE main.cohort AS
                        SELECT 7 AS cohort_definition_id, person_id AS subject_id,
                               DATE '1900-01-01' AS cohort_start_date, DATE '2100-12-31' AS cohort_end_date
                        FROM person ORDER BY person_id LIMIT 500")
  DBI::dbExecute(con, "UPDATE main.cohort SET cohort_definition_id = 1 WHERE subject_id IN
                        (SELECT subject_id FROM main.cohort ORDER BY subject_id LIMIT 250)")
}

n_persons <- function(db) as.numeric(db$cdm$person |> dplyr::tally() |> dplyr::pull(n))

test_that("cohort_summary() counts entries and persons of one cohort, read-only", {
  db <- get_test_db(prepare = add_results_cohort)
  on.exit(cleanup_test_db(db))

  s <- cohort_summary(db$con, cohort_id = 99, cohort_schema = "results")
  expect_equal(s$n_entries, 3)
  expect_equal(s$n_persons, 2)
  expect_equal(as.character(s$min_start), "2000-01-01")
  expect_equal(as.character(s$max_end), "2020-12-31")
})

test_that("list_care_sites() lists care sites with their patient counts", {
  db <- get_test_db(prepare = add_visit_link_fixture)
  on.exit(cleanup_test_db(db))

  sites <- list_care_sites(db$con, cdm_schema = "main", min_patients = 1)
  expect_equal(sites$care_site_id, c(101, 102))
  expect_equal(as.numeric(sites$n_patients), c(600, 291))
  expect_equal(nrow(list_care_sites(db$con, cdm_schema = "main", min_patients = 300)), 1)
})

test_that("cohort_schema alone reads <schema>.cohort, also on DuckDB", {
  db <- get_test_db(prepare = add_results_cohort)
  on.exit(cleanup_test_db(db))
  rows_before <- DBI::dbGetQuery(db$con, "SELECT count(*) AS n FROM results.cohort")$n

  expect_equal(n_persons(apply_cohort_filter(db, 99, cohort_schema = "results")), 2)
  expect_equal(n_persons(apply_cohort_filter(db, 99, cohort_schema = "results", cohort_table = "cohort")), 2)
  tables <- suppressMessages(extract_all("Cohort_99", db, domains = "conditions", cohort_id = 99,
                                         cohort_schema = "results", save = FALSE))
  expect_true("condition_prevalence" %in% names(tables))
  expect_equal(DBI::dbGetQuery(db$con, "SELECT count(*) AS n FROM results.cohort")$n, rows_before)
})

test_that("cohort_schema + cohort_table reads that table, not another table called cohort", {
  db <- get_test_db(prepare = add_results_cohort)
  on.exit(cleanup_test_db(db))

  # main.cohort also has cohort 7, with 500 persons
  expect_equal(n_persons(apply_cohort_filter(db, 7, cohort_schema = "results", cohort_table = "my_cohorts")), 3)
})

test_that("cohort_table alone reads a cohort in the cdm reference", {
  db <- get_test_db_write(prepare = add_unrelated_cohort)
  on.exit(cleanup_test_db(db))
  my_list <- db$cdm$person |> dplyr::select(subject_id = "person_id") |> dplyr::collect() |>
    utils::head(3) |>
    dplyr::mutate(cohort_definition_id = 1L, cohort_start_date = as.Date("1900-01-01"),
                  cohort_end_date = as.Date("2100-12-31"))
  db$cdm <- CDMConnector::insertTable(db$cdm, name = "my_list", table = my_list)

  # main.cohort also has cohort 1, with 250 persons
  expect_equal(n_persons(apply_cohort_filter(db, 1, cohort_table = "my_list")), 3)
  # Its database name has the prefix: named with the schema it is not found, and the message says why
  expect_error(apply_cohort_filter(db, 1, cohort_schema = "results", cohort_table = "my_list"), "cdm reference")
})

test_that("a cohort must be named: without cohort_schema or cohort_table Syrona stops", {
  db <- get_test_db(prepare = add_results_cohort)
  on.exit(cleanup_test_db(db))

  # main.cohort exists, but it is not read without being named
  expect_error(apply_cohort_filter(db, 7), "cohort_schema")
  err <- expect_error(extract_all("X", db, cohort_id = 7, save = FALSE), "cohort_schema")
  expect_identical(as.character(err$call[[1]]), "extract_all")
  expect_error(extract_all("X", db, cohort_schema = "results", save = FALSE), "cohort_id")
})

test_that("a cohort that cannot be used stops with a clear message before extraction", {
  db <- get_test_db(prepare = add_results_cohort)
  on.exit(cleanup_test_db(db))

  expect_error(apply_cohort_filter(db, 99, cohort_schema = "results", cohort_table = "nope"), "not found")
  expect_error(apply_cohort_filter(db, 99, cohort_schema = "results", cohort_table = "bad"), "cohort_end_date")
  expect_error(apply_cohort_filter(db, 12345, cohort_schema = "results"), "no entries")
  expect_error(apply_cohort_filter(db, 97, cohort_schema = "results"), "overlapping")
  expect_error(apply_cohort_filter(db, 96, cohort_schema = "results"), "overlapping")
  expect_error(apply_cohort_filter(db, 1, cohort_table = "not_in_cdm"), "not_in_cdm")
  expect_error(extract_all("X", db, cohort_id = 99, care_site_id = 101, save = FALSE), "either")
})

test_that("cohort_summary() reads a named cohort table and needs its schema", {
  db <- get_test_db(prepare = add_results_cohort)
  on.exit(cleanup_test_db(db))

  s <- cohort_summary(db$con, cohort_id = 7, cohort_schema = "results", cohort_table = "my_cohorts")
  expect_equal(as.numeric(s$n_persons), 3)
  expect_error(cohort_summary(db$con, cohort_id = 7), "cohort_schema")
  expect_error(cohort_summary(db$con, cohort_id = 7, cohort_schema = "results", cohort_table = "nope"), "not found")
})

test_that("a cohort in a Postgres schema table gives exactly its persons", {
  db <- get_test_pg("owner")
  s <- pg_settings("owner")
  tab <- paste0("syrona_test_cohort_", basename(tempfile("")))
  on.exit({
    try(DBI::dbExecute(db$con, sprintf("DROP TABLE IF EXISTS %s.%s", s$write_schema, tab)), silent = TRUE)
    syrona_disconnect(db)
  })
  DBI::dbExecute(db$con, sprintf(
    "CREATE TABLE %s.%s AS SELECT 3 AS cohort_definition_id, person_id AS subject_id,
       DATE '1900-01-01' AS cohort_start_date, DATE '2100-12-31' AS cohort_end_date
     FROM %s.person ORDER BY person_id LIMIT 3", s$write_schema, tab, s$cdm_schema))

  expect_equal(n_persons(apply_cohort_filter(db, 3, cohort_schema = s$write_schema, cohort_table = tab)), 3)
})

test_that("the cohort used is recorded in _metadata.csv, only when a cohort is used", {
  db <- get_test_db(prepare = add_results_cohort)
  on.exit(cleanup_test_db(db))
  base <- file.path(tempdir(), "cohort_meta")
  old <- options(syrona.data_dir = base)
  on.exit({ options(old); unlink(base, recursive = TRUE) }, add = TRUE)

  # main.cohort: cohort 7 has 250 persons, one entry each
  suppressMessages(extract_all("With_cohort", db, domains = "conditions", cohort_id = 7, cohort_schema = "main"))
  suppressMessages(extract_all("Without_cohort", db, domains = "conditions"))

  with_cohort <- utils::read.csv(file.path(base, "data", "sources", "With_cohort", "_metadata.csv"))
  without_cohort <- utils::read.csv(file.path(base, "data", "sources", "Without_cohort", "_metadata.csv"))
  expect_equal(with_cohort$cohort_id, 7)
  expect_equal(with_cohort$cohort_schema, "main")
  expect_equal(with_cohort$cohort_table, "cohort")
  expect_equal(with_cohort$cohort_entries, 250)
  expect_equal(with_cohort$cohort_persons, 250)
  expect_false(any(grepl("^cohort_", names(without_cohort))))
})
