test_that("create_cohort_table + delete_cohort round-trip works", {
  # Cohort tests need a writable copy with a separate write schema.
  db <- get_test_db_write()
  on.exit(cleanup_test_db(db))

  # Create cohort table
  result <- create_cohort_table(db$con, cohort_schema = NULL)
  expect_true(result)

  # Second call should return FALSE (already exists)
  result2 <- create_cohort_table(db$con, cohort_schema = NULL)
  expect_false(result2)

  # Insert a row manually
  DBI::dbExecute(db$con,
    "INSERT INTO cohort VALUES (99, 1, '2000-01-01', '2020-12-31')")

  # Verify via cohort_summary
  summary <- cohort_summary(db$con, cohort_id = 99)
  expect_equal(summary$n_entries, 1)
  expect_equal(summary$n_persons, 1)

  # Delete
  n_del <- delete_cohort(db$con, cohort_id = 99)
  expect_equal(n_del, 1)
})
