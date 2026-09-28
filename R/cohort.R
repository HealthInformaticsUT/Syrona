# ── Cohort and care-site helpers ─────────────────────────────────────────────
#
# Read-only helpers: list care sites, summarise a cohort in an OHDSI cohort
# table. All cohort tables follow the standard OHDSI 4-column schema:
#   cohort_definition_id  INTEGER
#   subject_id            INTEGER
#   cohort_start_date     DATE
#   cohort_end_date       DATE

# ── Cohort utilities ────────────────────────────────────────────────────────

#' List care sites with patient counts.
#'
#' Use it to choose a \code{care_site_id} for
#' \code{extract_all(..., care_site_id = )}.
#'
#' @param con DBI connection.
#' @param cdm_schema Schema containing the OMOP CDM tables.
#' @param min_patients Minimum number of patients to include (default 100).
#' @return A tibble with \code{care_site_id}, \code{care_site_name}, \code{n_patients}.
#' @export
list_care_sites <- function(con, cdm_schema, min_patients = 100) {
  sql <- sprintf(
    "SELECT cs.care_site_id, cs.care_site_name,
            COUNT(DISTINCT vo.person_id) AS n_patients
     FROM %s.visit_occurrence vo
     JOIN %s.care_site cs ON vo.care_site_id = cs.care_site_id
     GROUP BY cs.care_site_id, cs.care_site_name
     HAVING COUNT(DISTINCT vo.person_id) >= %d
     ORDER BY n_patients DESC",
    cdm_schema, cdm_schema, as.integer(min_patients)
  )
  DBI::dbGetQuery(con, sql) |> tibble::as_tibble()
}

#' Get summary statistics for a cohort.
#'
#' Reads the cohort table where it is, read-only. For a cohort in the cdm
#' reference use \code{CDMConnector::cohortCount()}.
#'
#' @param con DBI connection.
#' @param cohort_id Integer \code{cohort_definition_id}.
#' @param cohort_schema Schema containing the cohort table.
#' @param cohort_table Name of the cohort table (default \code{"cohort"}).
#' @return A tibble with \code{n_entries}, \code{n_persons}, \code{min_start}, \code{max_end}.
#' @export
cohort_summary <- function(con, cohort_id, cohort_schema = NULL, cohort_table = "cohort") {
  if (is.null(cohort_schema)) {
    cli::cli_abort(c(
      "Name the schema of the cohort table with {.arg cohort_schema}.",
      "i" = "A cohort generated in ATLAS: {.code cohort_schema = \"results\"}."
    ))
  }
  .read_cohort_table(list(con = con), cohort_schema, cohort_table, call = rlang::current_env()) |>
    dplyr::filter(.data$cohort_definition_id == !!cohort_id) |>
    dplyr::group_by(.data$cohort_definition_id) |>
    dplyr::summarise(
      n_entries = dplyr::n(),
      n_persons = dplyr::n_distinct(.data$subject_id, na.rm = TRUE),
      min_start = min(.data$cohort_start_date, na.rm = TRUE),
      max_end   = max(.data$cohort_end_date, na.rm = TRUE),
      .groups = "drop"
    ) |>
    dplyr::collect()
}
