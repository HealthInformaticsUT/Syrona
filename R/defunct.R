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
