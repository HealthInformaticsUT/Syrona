# ── CDM connection helpers ────────────────────────────────────────────────────
#
# Connections are read-only by default: no write schema, and DuckDB files are
# opened read-only. A write schema is only needed by tools that write through
# the cdm reference (for example CDMConnector::generateCohortSet()), and every
# table written there gets the prefix "syrona_".

# CDMConnector's writeSchema argument: NULL, or the schema with the prefix
.write_schema_arg <- function(write_schema) {
  if (is.null(write_schema)) NULL else c(schema = write_schema, prefix = "syrona_")
}

# Create the CDM reference. If that fails, the connection is closed before the
# error is passed on, so the database is not left open in the R session.
.cdm_or_disconnect <- function(con, cdm_schema, write_schema, shutdown = FALSE) {
  tryCatch(
    CDMConnector::cdmFromCon(
      con = con,
      cdmSchema = cdm_schema,
      writeSchema = .write_schema_arg(write_schema)
    ),
    error = function(e) {
      if (shutdown) DBI::dbDisconnect(con, shutdown = TRUE) else DBI::dbDisconnect(con)
      stop(e)
    }
  )
}

#' Connect to a DuckDB OMOP CDM.
#'
#' Opens a DuckDB file and creates a CDMConnector reference. By default the
#' file is opened read-only and nothing is written to it.
#'
#' @param db_path Path to the DuckDB file.
#' @param cdm_schema Schema containing OMOP CDM tables (default \code{"main"}).
#' @param write_schema Schema where tables written through the cdm reference
#'   go, for example cohorts generated from ATLAS JSON with
#'   \code{CDMConnector::generateCohortSet()}. Default \code{NULL}: no write
#'   schema, nothing can be written. Every table written there gets the prefix
#'   \code{"syrona_"}. Extraction with \code{extract_all()} never needs it.
#' @param read_only Logical. Open the DuckDB file read-only? Default
#'   \code{TRUE}. Set to \code{FALSE} only together with a
#'   \code{write_schema}.
#' @return A list with components:
#'   \describe{
#'     \item{con}{DBI connection object.}
#'     \item{cdm}{CDMConnector CDM reference (\code{cdm_reference}).}
#'   }
#' @export
syrona_connect <- function(db_path,
                           cdm_schema = "main",
                           write_schema = NULL,
                           read_only = TRUE) {
  rlang::check_installed("duckdb", reason = "to connect to DuckDB databases")
  if (!is.null(write_schema) && isTRUE(read_only)) {
    cli::cli_abort(c(
      "A {.arg write_schema} needs a writable file.",
      "i" = "Add {.code read_only = FALSE}: {.code syrona_connect(db_path, write_schema = \"{write_schema}\", read_only = FALSE)}.",
      "i" = "Extraction with {.fn extract_all} needs no write schema."
    ))
  }
  con <- DBI::dbConnect(duckdb::duckdb(), dbdir = db_path, read_only = read_only)
  cdm <- .cdm_or_disconnect(con, cdm_schema, write_schema, shutdown = TRUE)
  list(con = con, cdm = cdm)
}

#' Connect to a PostgreSQL OMOP CDM.
#'
#' For remote databases, typically accessed via SSH tunnel:
#' \code{ssh -L 5432:localhost:5432 user@@server}. Read access to the CDM
#' schema and the right to create temporary tables are enough.
#'
#' @param host Hostname (default \code{"localhost"} for SSH tunnel).
#' @param port Port number (default \code{5432}).
#' @param dbname Database name.
#' @param user PostgreSQL username.
#' @param password Password. If \code{NULL}, uses \code{.pgpass} or
#'   \code{PGPASSWORD} env var.
#' @param cdm_schema Schema with OMOP CDM tables (e.g. \code{"cdm"}).
#' @param write_schema Schema where tables written through the cdm reference
#'   go (e.g. \code{"results"}). Default \code{NULL}: no write schema. Every
#'   table written there gets the prefix \code{"syrona_"}. Extraction with
#'   \code{extract_all()} never needs it.
#' @return Same structure as \code{syrona_connect}.
#' @export
syrona_connect_pg <- function(host = "localhost",
                              port = 5432,
                              dbname,
                              user,
                              password = NULL,
                              cdm_schema = "public",
                              write_schema = NULL) {
  rlang::check_installed("RPostgres", reason = "to connect to PostgreSQL databases")
  args <- list(
    drv = RPostgres::Postgres(),
    host = host, port = port,
    dbname = dbname, user = user
  )
  if (!is.null(password)) args$password <- password
  con <- do.call(DBI::dbConnect, args)
  cdm <- .cdm_or_disconnect(con, cdm_schema, write_schema)
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
