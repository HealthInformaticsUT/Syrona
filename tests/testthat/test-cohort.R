# Read-only cohort and care-site helpers

add_results_cohort <- function(con) {
  DBI::dbExecute(con, "CREATE SCHEMA results")
  DBI::dbExecute(con, "CREATE TABLE results.cohort (cohort_definition_id INTEGER, subject_id INTEGER,
                        cohort_start_date DATE, cohort_end_date DATE)")
  DBI::dbExecute(con, "INSERT INTO results.cohort VALUES
                        (99, 1, '2000-01-01', '2005-12-31'), (99, 1, '2010-01-01', '2012-12-31'),
                        (99, 2, '2001-01-01', '2020-12-31'), (98, 3, '2000-01-01', '2020-12-31')")
}

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
