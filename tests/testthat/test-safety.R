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

# Permanent tables with the names Syrona once used for its temporary tables
SYRONA_LIKE_NAMES <- c("syrona_years", "syrona_cond_ids", "syrona_cond_ids_attr",
                       "syrona_proc_ids", "syrona_proc_ids_attr", "syrona_drug_ids")
add_syrona_like_tables <- function(con) {
  for (t in SYRONA_LIKE_NAMES) DBI::dbExecute(con, sprintf("CREATE TABLE main.%s AS SELECT 1 AS mine", t))
}

test_that("extract_all() on a writable connection leaves same-name permanent tables untouched", {
  db <- get_test_db_write(prepare = add_syrona_like_tables)
  on.exit(cleanup_test_db(db))

  tables <- suppressMessages(extract_all("Writable", db, save = FALSE))

  expect_known_gibleed(tables)
  for (t in SYRONA_LIKE_NAMES) {
    expect_equal(DBI::dbGetQuery(db$con, sprintf("SELECT count(*) AS n FROM main.%s", t))$n, 1, label = t)
  }
})

test_that("extract_all() works read-only when same-name permanent tables exist", {
  db <- get_test_db(prepare = add_syrona_like_tables)
  on.exit(cleanup_test_db(db))

  tables <- suppressMessages(extract_all("Read_only", db, save = FALSE))

  expect_known_gibleed(tables)
})

test_that("extract_all() leaves no temporary tables behind", {
  db <- get_test_db()
  on.exit(cleanup_test_db(db))

  suppressMessages(extract_all("Temp_cleanup", db, save = FALSE))

  left <- DBI::dbGetQuery(db$con, "SELECT table_name FROM information_schema.tables
                                   WHERE table_name LIKE 'syrona%'")$table_name
  expect_length(left, 0)
})
