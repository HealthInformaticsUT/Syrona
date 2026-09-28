# ── Defunct functions ─────────────────────────────────────────────────────────
#
# Functions removed in syrona 0.3.0. Each stops with a message that explains
# how the task works now.

#' Defunct functions in syrona
#'
#' These functions were removed in syrona 0.3.0. Calling one stops with a
#' message that explains what to use instead.
#'
#' \itemize{
#'   \item \code{insert_cohort()}: use a cohort that already exists in the
#'     database, e.g. one generated in ATLAS:
#'     \code{extract_all(name, db, cohort_id = , cohort_schema = )}.
#'   \item \code{create_caresite_cohort()}: extract one care site with
#'     \code{extract_all(name, db, care_site_id = )}.
#'   \item \code{delete_cohort()}: Syrona creates no cohort tables, so there is
#'     nothing of its own to delete.
#' }
#'
#' @param ... Ignored.
#' @return None, these functions always stop with an error.
#' @name syrona-defunct
#' @keywords internal
NULL

#' @rdname syrona-defunct
#' @export
insert_cohort <- function(...) {
  cli::cli_abort(c(
    "{.fn insert_cohort} was removed in syrona 0.3.0.",
    "i" = "Use a cohort that already exists in the database, for example one generated in ATLAS:",
    " " = "{.code extract_all(\"My_cohort\", db, cohort_id = 2031, cohort_schema = \"results\")}",
    " " = "This reads the table {.val cohort} in the schema {.val results}. For another table name add {.code cohort_table = \"my_table\"}.",
    "i" = "A cohort computed in R can be written to your own schema with CDMConnector first, then read with {.arg cohort_table}."
  ))
}

#' @rdname syrona-defunct
#' @export
create_caresite_cohort <- function(...) {
  cli::cli_abort(c(
    "{.fn create_caresite_cohort} was removed in syrona 0.3.0.",
    "i" = "Care-site (hospital) extraction is built into {.fn extract_all}:",
    " " = "{.code extract_all(\"Hospital_A\", db, care_site_id = 101)}",
    " " = "It keeps persons with at least one visit at the care site and only their events recorded at that care site (linked through {.field visit_occurrence_id}), over their whole observation period, the method of the published analysis. Nothing is written to the database.",
    "i" = "Find {.arg care_site_id} values with {.fn list_care_sites}.",
    "i" = "Results differ from 0.2.1 care-site cohorts, which counted all events between the first and last visit."
  ))
}

#' @rdname syrona-defunct
#' @export
delete_cohort <- function(...) {
  cli::cli_abort(c(
    "{.fn delete_cohort} was removed in syrona 0.3.0.",
    "i" = "Syrona creates no cohort tables, so there is nothing of its own to delete.",
    "i" = "Hospitals: {.code extract_all(..., care_site_id = )} leaves nothing to clean up.",
    "i" = "Tables made with 0.2.1 stay in your schema. Remove them with your database tools if not needed, and check first that it is not ATLAS's own cohort table."
  ))
}
