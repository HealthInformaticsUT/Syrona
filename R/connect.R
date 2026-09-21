# ── CDM connection helpers ────────────────────────────────────────────────────
#
# `write_schema` is exposed as a first-class argument because production
# OMOP CDMs are typically read-only; cohort and temp tables must be written
# to a separate results schema.

#' Connect to a DuckDB OMOP CDM.
#'
#' Opens a DuckDB file and creates a CDMConnector reference. The file is
#' opened writable, because CDMConnector validates a CDM by writing a small
#' probe table, so a read-only DuckDB connection cannot create a CDM reference.
#' Syrona only writes temporary and cohort tables; your OMOP data is not
#' modified.
#'
#' @param db_path Path to the DuckDB file.
#' @param cdm_schema Schema containing OMOP CDM tables (default \code{"main"}).
#' @param write_schema Schema for writing temp/cohort tables.
#'   Defaults to \code{cdm_schema}. Set to a different schema if the CDM
#'   schema is read-only (common in production setups).
#' @param read_only Logical. Open DuckDB in read-only mode? Default
#'   \code{FALSE}. Setting it to \code{TRUE} makes the connection fail,
#'   because CDMConnector needs to write a probe table.
#' @return A list with components:
#'   \describe{
#'     \item{con}{DBI connection object.}
#'     \item{cdm}{CDMConnector CDM reference (\code{cdm_reference}).}
#'   }
#' @export
syrona_connect <- function(db_path,
                           cdm_schema = "main",
                           write_schema = cdm_schema,
                           read_only = FALSE) {
  rlang::check_installed("duckdb", reason = "to connect to DuckDB databases")
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = read_only)
  cdm <- CDMConnector::cdmFromCon(
    con = con,
    cdmSchema = cdm_schema,
    writeSchema = write_schema
  )
  list(con = con, cdm = cdm)
}

#' Connect to a PostgreSQL OMOP CDM.
#'
#' For remote databases, typically accessed via SSH tunnel:
#' \code{ssh -L 5432:localhost:5432 user@@server}.
#'
#' @param host Hostname (default \code{"localhost"} for SSH tunnel).
#' @param port Port number (default \code{5432}).
#' @param dbname Database name.
#' @param user PostgreSQL username.
#' @param password Password. If \code{NULL}, uses \code{.pgpass} or
#'   \code{PGPASSWORD} env var.
#' @param cdm_schema Schema with OMOP CDM tables (e.g. \code{"cdm"}).
#' @param write_schema Schema for cohort/temp tables (e.g. \code{"results_maarja"}).
#' @return Same structure as \code{syrona_connect}.
#' @export
syrona_connect_pg <- function(host = "localhost",
                              port = 5432,
                              dbname,
                              user,
                              password = NULL,
                              cdm_schema = "public",
                              write_schema = cdm_schema) {
  rlang::check_installed("RPostgres", reason = "to connect to PostgreSQL databases")
  args <- list(
    drv = RPostgres::Postgres(),
    host = host, port = port,
    dbname = dbname, user = user
  )
  if (!is.null(password)) args$password <- password
  con <- do.call(DBI::dbConnect, args)
  cdm <- CDMConnector::cdmFromCon(
    con = con,
    cdmSchema = cdm_schema,
    writeSchema = write_schema
  )
  list(con = con, cdm = cdm)
}

#' Disconnect from an OMOP CDM database.
#'
#' @param db Connection list returned by \code{syrona_connect} or
#'   \code{syrona_connect_pg}.
#' @return No return value, called for its side effect of closing the database
#'   connection.
#' @export
syrona_disconnect <- function(db) {
  DBI::dbDisconnect(db$con)
  invisible(NULL)
}
