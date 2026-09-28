# ── Safety tests: Syrona must never damage the CDM or other users' data ──────
#
# Database tests use the helpers in helper-setup.R (temporary DuckDB copies,
# the local PostgreSQL test server).

test_that("syrona_connect_pg() with its defaults connects a read-only user and writes nothing", {
  skip_on_cran()
  skip_if_not_installed("RPostgres")
  s <- pg_settings("reader")

  # No write_schema: the reader has no write right on the CDM schema
  db <- syrona_connect_pg(host = s$host, dbname = s$dbname, user = s$user,
                          password = s$password, cdm_schema = s$cdm_schema)
  on.exit(syrona_disconnect(db))
  cdm_before <- snapshot_schema(db$con, s$cdm_schema)
  results_before <- snapshot_schema(db$con, s$write_schema)

  tables <- suppressMessages(extract_all("Defaults_pg", db, save = FALSE))

  expect_known_gibleed(tables)
  expect_identical(snapshot_schema(db$con, s$cdm_schema), cdm_before)
  expect_identical(snapshot_schema(db$con, s$write_schema), results_before)
})

test_that("tables written through the cdm go only to the write schema, with the syrona_ prefix", {
  db <- get_test_db_write()
  on.exit(cleanup_test_db(db))
  main_before <- snapshot_schema(db$con, "main")

  db$cdm <- CDMConnector::insertTable(db$cdm, name = "my_table", table = data.frame(a = 1:3))

  results_tables <- snapshot_schema(db$con, "results")$table
  expect_true("syrona_my_table" %in% results_tables)
  expect_false("my_table" %in% results_tables)
  expect_identical(snapshot_schema(db$con, "main"), main_before)
})
