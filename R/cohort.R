# ── Cohort and care-site helpers ─────────────────────────────────────────────
#
# Read-only helpers: list care sites, summarise a cohort in an OHDSI cohort
# table. All cohort tables follow the standard OHDSI 4-column schema:
#   cohort_definition_id  INTEGER
#   subject_id            INTEGER
#   cohort_start_date     DATE
#   cohort_end_date       DATE

# ── Internal helpers ────────────────────────────────────────────────────────

.qualify_table <- function(schema = NULL, table) {
  if (is.null(schema) || identical(schema, "") || identical(schema, "main")) {
    table
  } else {
    paste0(schema, ".", table)
  }
}

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
#' @param con DBI connection.
#' @param cohort_id Integer \code{cohort_definition_id}.
#' @param cohort_schema Schema containing the cohort table (\code{NULL} = default).
#' @return A tibble with \code{n_entries}, \code{n_persons}, \code{min_start}, \code{max_end}.
#' @export
cohort_summary <- function(con, cohort_id, cohort_schema = NULL) {
  cohort_table <- .qualify_table(cohort_schema, "cohort")
  sql <- sprintf(
    "SELECT cohort_definition_id,
            COUNT(*)                   AS n_entries,
            COUNT(DISTINCT subject_id) AS n_persons,
            MIN(cohort_start_date)     AS min_start,
            MAX(cohort_end_date)       AS max_end
     FROM %s
     WHERE cohort_definition_id = %d
     GROUP BY cohort_definition_id",
    cohort_table, as.integer(cohort_id)
  )
  DBI::dbGetQuery(con, sql) |> tibble::as_tibble()
}
