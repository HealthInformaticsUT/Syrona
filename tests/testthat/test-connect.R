test_that("syrona_connect() with its defaults is read-only and leaves the file unchanged", {
  tmp_path <- copy_gibleed()
  on.exit(unlink(tmp_path))
  md5_before <- unname(tools::md5sum(tmp_path))

  db <- syrona_connect(tmp_path)

  expect_true(inherits(db$con, "duckdb_connection"))
  expect_true(inherits(db$cdm, "cdm_reference"))
  expect_true(all(c("person", "observation_period", "condition_occurrence") %in% names(db$cdm)))
  expect_error(DBI::dbExecute(db$con, "CREATE TABLE main.probe (a INTEGER)"), "read-only")

  # Known answers: GiBleed has 2,694 persons, a full extraction gives 18 tables
  n_persons <- db$cdm$person |> dplyr::tally() |> dplyr::pull(n)
  expect_equal(as.numeric(n_persons), 2694)
  tables <- suppressMessages(extract_all("Defaults", db, save = FALSE))
  expect_length(tables, 18)
  expect_known_gibleed(tables)

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

test_that("a write schema on a read-only DuckDB connection stops with a clear message", {
  tmp_path <- copy_gibleed()
  on.exit(unlink(tmp_path))
  md5_before <- unname(tools::md5sum(tmp_path))

  expect_error(syrona_connect(tmp_path, write_schema = "main"), "read_only = FALSE")
  expect_identical(unname(tools::md5sum(tmp_path)), md5_before)
})

test_that("a failed connect closes its connection, so the file can be opened again", {
  tmp_path <- copy_gibleed()
  on.exit(unlink(tmp_path))
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = tmp_path)
  DBI::dbExecute(con, "CREATE SCHEMA results")
  DBI::dbDisconnect(con, shutdown = TRUE)

  expect_error(syrona_connect(tmp_path, cdm_schema = "no_such_schema"))

  # Same session, same file, now writable: works only if the failed connection was closed
  db <- syrona_connect(tmp_path, read_only = FALSE, write_schema = "results")
  expect_true(inherits(db$cdm, "cdm_reference"))
  syrona_disconnect(db)
})
