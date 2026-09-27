# ── Test helpers: Eunomia GiBleed on DuckDB and PostgreSQL ────────────────────
#
# Every database test connects through Syrona's own connect functions. Each
# DuckDB test works on a temporary copy of GiBleed.
#
#   get_test_db()        read-only DuckDB copy, for extraction tests
#   get_test_db_write()  writable DuckDB copy with a "results" schema, for cohort tests
#   get_test_pg()        PostgreSQL as "reader" (read-only CDM) or "owner" (all rights)
#   snapshot_schema()    every table in a schema with its row count
#   add_caresite_fixture()  care sites 101 and 102 on a writable copy
#   KNOWN_GIBLEED        known answers for extract_all() on GiBleed
#
# Database tests are skipped on CRAN and when no test database is configured.
# Locally, set SYRONA_TEST_DB (DuckDB) and SYRONA_TEST_PG_* (PostgreSQL) in
# ~/.Renviron.

# Path to a known GiBleed DuckDB
EUNOMIA_PATHS <- c(
  Sys.getenv("SYRONA_TEST_DB"),
  file.path(Sys.getenv("EUNOMIA_DATA_FOLDER"), "GiBleed_5.3_1.4.duckdb")
)

find_eunomia <- function() {
  for (p in EUNOMIA_PATHS) {
    if (nchar(p) > 0 && file.exists(p)) return(path.expand(p))
  }
  NULL
}

# Copy GiBleed to a temporary file and return its path
copy_gibleed <- function() {
  skip_on_cran()
  skip_if_not_installed("duckdb")
  src <- find_eunomia()
  if (is.null(src)) {
    skip("No GiBleed DuckDB found. Set SYRONA_TEST_DB in ~/.Renviron.")
  }
  tmp_path <- tempfile(fileext = ".duckdb")
  file.copy(src, tmp_path)
  tmp_path
}

# ── Connection settings in one place ─────────────────────────────────────────
# Read-only, without a write schema.
READ_ONLY_ARGS <- list(read_only = TRUE, write_schema = NULL)

#' Read-only DuckDB copy of GiBleed, connected with syrona_connect().
#' Returns a list with con, cdm, tmp_path.
#' `prepare` is an optional function(con) run on a writable copy first
#' (for example add_visit_link_fixture); the copy is then opened read-only.
get_test_db <- function(prepare = NULL) {
  tmp_path <- copy_gibleed()
  if (!is.null(prepare)) {
    con <- DBI::dbConnect(duckdb::duckdb(), dbdir = tmp_path)
    prepare(con)
    DBI::dbDisconnect(con, shutdown = TRUE)
  }
  db <- do.call(syrona_connect, c(list(db_path = tmp_path), READ_ONLY_ARGS))
  db$tmp_path <- tmp_path
  db
}

#' Writable DuckDB copy of GiBleed with a separate "results" schema,
#' connected with syrona_connect(). For cohort tests.
#' `prepare` is an optional function(con) run on the copy before connecting
#' (for example add_caresite_fixture).
get_test_db_write <- function(prepare = NULL) {
  tmp_path <- copy_gibleed()
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = tmp_path)
  DBI::dbExecute(con, "CREATE SCHEMA results")
  if (!is.null(prepare)) prepare(con)
  DBI::dbDisconnect(con, shutdown = TRUE)

  db <- syrona_connect(tmp_path, read_only = FALSE, write_schema = "results")
  db$tmp_path <- tmp_path
  db
}

#' Close a DuckDB test connection and delete its copy.
cleanup_test_db <- function(db) {
  try(DBI::dbDisconnect(db$con, shutdown = TRUE), silent = TRUE)
  try(unlink(db$tmp_path), silent = TRUE)
}

# ── PostgreSQL (a local test server with GiBleed in schema "cdm") ─────────────

pg_settings <- function(role) {
  vars <- c("SYRONA_TEST_PG_HOST", "SYRONA_TEST_PG_DBNAME", "SYRONA_TEST_PG_CDM_SCHEMA",
            "SYRONA_TEST_PG_WRITE_SCHEMA",
            if (role == "owner") c("SYRONA_TEST_PG_OWNER_USER", "SYRONA_TEST_PG_OWNER_PASSWORD")
            else c("SYRONA_TEST_PG_USER", "SYRONA_TEST_PG_PASSWORD"))
  vals <- Sys.getenv(vars)
  if (any(!nzchar(vals))) {
    skip("PostgreSQL test database not configured (SYRONA_TEST_PG_* in ~/.Renviron).")
  }
  list(
    host = vals[["SYRONA_TEST_PG_HOST"]],
    dbname = vals[["SYRONA_TEST_PG_DBNAME"]],
    cdm_schema = vals[["SYRONA_TEST_PG_CDM_SCHEMA"]],
    write_schema = vals[["SYRONA_TEST_PG_WRITE_SCHEMA"]],
    user = if (role == "owner") vals[["SYRONA_TEST_PG_OWNER_USER"]] else vals[["SYRONA_TEST_PG_USER"]],
    password = if (role == "owner") vals[["SYRONA_TEST_PG_OWNER_PASSWORD"]] else vals[["SYRONA_TEST_PG_PASSWORD"]]
  )
}

#' PostgreSQL test connection through syrona_connect_pg().
#' role "reader": read-only on the CDM, no write schema.
#' role "owner":  owns every schema and table, write schema "results".
get_test_pg <- function(role = c("reader", "owner"), cdm_schema = NULL) {
  role <- match.arg(role)
  skip_on_cran()
  skip_if_not_installed("RPostgres")
  s <- pg_settings(role)
  syrona_connect_pg(
    host = s$host, dbname = s$dbname, user = s$user, password = s$password,
    cdm_schema = if (is.null(cdm_schema)) s$cdm_schema else cdm_schema,
    write_schema = if (role == "owner") s$write_schema else NULL
  )
}

# ── Snapshot: every table in a schema with its row count ─────────────────────

#' Returns a data frame (table, rows), sorted by table name. Works on DuckDB and
#' PostgreSQL.
snapshot_schema <- function(con, schema) {
  tabs <- DBI::dbGetQuery(con, sprintf(
    "SELECT table_name FROM information_schema.tables
      WHERE table_schema = %s AND table_type = 'BASE TABLE'
      ORDER BY table_name",
    DBI::dbQuoteString(con, schema)))$table_name
  rows <- vapply(tabs, function(t) {
    as.numeric(DBI::dbGetQuery(con, sprintf(
      "SELECT count(*) AS n FROM %s",
      DBI::dbQuoteIdentifier(con, DBI::Id(schema = schema, table = t))))$n)
  }, numeric(1))
  data.frame(table = tabs, rows = unname(rows))
}

# ── Care-site fixture ────────────────────────────────────────────────────────
# GiBleed has no care sites. This adds site 101 (61 persons, 77 visits) and
# site 102 (30 persons). Use as get_test_db_write(prepare = add_caresite_fixture).
add_caresite_fixture <- function(con) {
  DBI::dbExecute(con, "INSERT INTO care_site (care_site_id, care_site_name) VALUES (101, 'Site A'), (102, 'Site B')")
  DBI::dbExecute(con, "UPDATE visit_occurrence SET care_site_id = 101 WHERE person_id IN
                        (SELECT DISTINCT person_id FROM visit_occurrence ORDER BY person_id LIMIT 60)")
  DBI::dbExecute(con, "UPDATE visit_occurrence SET care_site_id = 102 WHERE person_id IN
                        (SELECT DISTINCT person_id FROM visit_occurrence ORDER BY person_id LIMIT 30 OFFSET 60)")
  DBI::dbExecute(con, "UPDATE visit_occurrence SET care_site_id = 101 WHERE person_id = 2894")
  invisible(TRUE)
}

# ── Known answers: extract_all() on GiBleed, save = FALSE ────────────────────
# Rows per returned table, recorded with syrona 0.2.1 on DuckDB and PostgreSQL.
KNOWN_GIBLEED <- list(
  condition_prevalence = 2926, condition_info = 78, condition_chapters = 78,
  condition_attributes = 0, condition_rare = 38,
  procedure_prevalence = 720, procedure_info = 47, procedure_chapters = 1,
  procedure_attributes = 0, procedure_rare = 27,
  drug_prevalence = 3073, drug_info = 81, drug_chapters = 81,
  drug_attributes = 0, drug_rare = 42,
  demographics = 151, death_counts = 0, denominator = 1203
)

#' Check every table of an extract_all() result against KNOWN_GIBLEED.
expect_known_gibleed <- function(tables) {
  for (nm in names(tables)) {
    expect_equal(nrow(tables[[nm]]), KNOWN_GIBLEED[[nm]], label = paste("rows in", nm))
  }
}

# ── Visit-link fixture for care-site tests ───────────────────────────────────
# GiBleed has no care sites, and most of its event visit ids point to no visit.
# 890 persons have visits. This adds care site 101 (visits of the first 600 of
# them by person_id) and 102 (the other 290), plus one person with a visit at each site and condition events linked
# to both: odd condition_occurrence_id -> the visit at 101, even -> the visit
# at 102, the smallest id -> no visit. Drug events of site 102's persons get no
# visit link, so site 102 has no linked drug events.
add_visit_link_fixture <- function(con) {
  DBI::dbExecute(con, "INSERT INTO care_site (care_site_id, care_site_name) VALUES (101, 'Hospital A'), (102, 'Hospital B')")
  DBI::dbExecute(con, "UPDATE visit_occurrence SET care_site_id = 101 WHERE person_id IN
                        (SELECT DISTINCT person_id FROM visit_occurrence ORDER BY person_id LIMIT 600)")
  DBI::dbExecute(con, "UPDATE visit_occurrence SET care_site_id = 102 WHERE person_id IN
                        (SELECT DISTINCT person_id FROM visit_occurrence ORDER BY person_id OFFSET 600)")
  mixed <- DBI::dbGetQuery(con, "SELECT v.person_id FROM visit_occurrence v GROUP BY 1 HAVING count(*) >= 2
                                 ORDER BY (SELECT count(*) FROM condition_occurrence c WHERE c.person_id = v.person_id) DESC,
                                          v.person_id LIMIT 1")$person_id
  visits <- DBI::dbGetQuery(con, sprintf("SELECT visit_occurrence_id FROM visit_occurrence
                                          WHERE person_id = %d ORDER BY visit_start_date, visit_occurrence_id LIMIT 2", mixed))$visit_occurrence_id
  DBI::dbExecute(con, sprintf("UPDATE visit_occurrence SET care_site_id = 101 WHERE visit_occurrence_id = %d", visits[1]))
  DBI::dbExecute(con, sprintf("UPDATE visit_occurrence SET care_site_id = 102 WHERE visit_occurrence_id = %d", visits[2]))
  DBI::dbExecute(con, sprintf("UPDATE condition_occurrence SET visit_occurrence_id =
                                 CASE WHEN condition_occurrence_id %% 2 = 1 THEN %d ELSE %d END WHERE person_id = %d",
                              visits[1], visits[2], mixed))
  DBI::dbExecute(con, sprintf("UPDATE condition_occurrence SET visit_occurrence_id = NULL WHERE condition_occurrence_id =
                                 (SELECT min(condition_occurrence_id) FROM condition_occurrence WHERE person_id = %d)", mixed))
  DBI::dbExecute(con, "UPDATE drug_exposure SET visit_occurrence_id = NULL WHERE person_id IN
                        (SELECT person_id FROM visit_occurrence WHERE care_site_id = 102)")
  invisible(mixed)
}

#' The one person with visits at both fixture sites.
fixture_mixed_person <- function(con) {
  DBI::dbGetQuery(con, "SELECT person_id FROM visit_occurrence WHERE care_site_id = 101
                        INTERSECT SELECT person_id FROM visit_occurrence WHERE care_site_id = 102")$person_id
}

# ── Table fingerprints ───────────────────────────────────────────────────────
# One fingerprint per table: rows, column names, and an md5 of the table's
# content sorted by all columns (numbers rounded to 8 significant digits).
table_fingerprints <- function(tables) {
  lapply(tables[order(names(tables))], function(t) {
    df <- as.data.frame(t)
    df[] <- lapply(df, function(v) {
      if (inherits(v, "integer64")) v <- as.numeric(v)
      if (is.numeric(v)) signif(v, 8) else as.character(v)
    })
    if (nrow(df) > 0) df <- df[do.call(order, unname(df)), , drop = FALSE]
    path <- tempfile(fileext = ".csv")
    on.exit(unlink(path))
    utils::write.csv(df, path, row.names = FALSE)
    list(rows = nrow(df), columns = names(df), md5 = unname(tools::md5sum(path)))
  })
}
