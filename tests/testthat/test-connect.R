test_that("syrona_connect opens a read-only CDM reference and leaves the file unchanged", {
  tmp_path <- copy_gibleed()
  on.exit(unlink(tmp_path))
  md5_before <- unname(tools::md5sum(tmp_path))

  db <- do.call(syrona_connect, c(list(db_path = tmp_path), READ_ONLY_ARGS))

  expect_true(inherits(db$con, "duckdb_connection"))
  expect_true(inherits(db$cdm, "cdm_reference"))

  # CDM should have standard OMOP tables
  expect_true("person" %in% names(db$cdm))
  expect_true("observation_period" %in% names(db$cdm))
  expect_true("condition_occurrence" %in% names(db$cdm))

  # Known answer: GiBleed has 2,694 persons
  n_persons <- db$cdm$person |> dplyr::tally() |> dplyr::pull(n)
  expect_equal(as.numeric(n_persons), 2694)

  syrona_disconnect(db)
  expect_identical(unname(tools::md5sum(tmp_path)), md5_before)
})

test_that("syrona_disconnect works cleanly", {
  db <- get_test_db()
  syrona_disconnect(db)

  # Connection should be closed
  expect_error(DBI::dbGetQuery(db$con, "SELECT 1"))
  unlink(db$tmp_path)
})
