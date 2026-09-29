# ── Source data extraction ────────────────────────────────────────────────────
#
# Functions that pull data out of an OMOP CDM database
# using CDMConnector + dplyr. Each `extract_*` function maps to one table in
# the Syrona schema (see docs/technical/SCHEMA.md).
#
# All extractors take a CDM reference (from `cdmFromCon`) as their first
# argument so they compose with the rest of the pipeline.
#
# Where an extractor mirrors an ACHILLES analysis, the analysis_id is noted
# inline near the relevant code.

# ── Cohort filtering ────────────────────────────────────────────────────────

# The cohort table as a lazy table, read where it is (see apply_cohort_filter)
.read_cohort_table <- function(db, cohort_schema, cohort_table, call) {
  if (is.null(cohort_schema) && is.null(cohort_table)) {
    cli::cli_abort(c(
      "Name where the cohort is: {.arg cohort_schema}, {.arg cohort_table} or both.",
      "i" = "A cohort generated in ATLAS: {.code cohort_schema = \"results\"} (reads {.val results.cohort}).",
      "i" = "A cohort in the cdm reference: {.code cohort_table = \"my_cohort\"}."
    ), call = call)
  }
  if (is.null(cohort_schema)) {
    if (is.null(db$cdm[[cohort_table]])) {
      cli::cli_abort(c(
        "{.val {cohort_table}} is not in the cdm reference.",
        "i" = "For a table in a database schema add {.arg cohort_schema}."
      ), call = call)
    }
    return(db$cdm[[cohort_table]])
  }
  table_named <- !is.null(cohort_table)
  cohort_table <- cohort_table %||% "cohort"
  ref <- CDMConnector::inSchema(cohort_schema, cohort_table, dbms = CDMConnector::dbms(db$con))
  where <- paste0(cohort_schema, ".", cohort_table)
  if (!DBI::dbExistsTable(db$con, ref)) {
    hint <- if (table_named) {
      c("i" = "Check {.arg cohort_schema} and {.arg cohort_table}.",
        "i" = "A cohort in the cdm reference (for example generated with CDMConnector) is read with {.arg cohort_table} alone.")
    } else {
      c("i" = "Check {.arg cohort_schema}: the schema where ATLAS writes its cohorts, not the CDM schema.")
    }
    cli::cli_abort(c("Cohort table {.val {where}} not found.", hint), call = call)
  }
  tryCatch(
    dplyr::tbl(db$con, ref),
    error = function(e) cli::cli_abort("Cohort table {.val {where}} cannot be read.", parent = e, call = call)
  )
}

#' Apply OHDSI cohort filtering to CDM table references.
#'
#' Modifies \code{db$cdm} table references to filter by a standard OHDSI
#' cohort table. Filters person, observation_period, death, and event tables
#' to cohort members and their cohort windows.
#'
#' The cohort is read where it is, nothing is written:
#' \itemize{
#'   \item \code{cohort_schema} and \code{cohort_table}: that table.
#'   \item \code{cohort_schema} only: the table \code{cohort} in that schema
#'     (where ATLAS and CohortGenerator write their cohorts).
#'   \item \code{cohort_table} only: that cohort in the cdm reference, for
#'     example one generated with \code{CDMConnector::generateCohortSet()}.
#' }
#' The cohort must have the four OHDSI columns, entries for \code{cohort_id},
#' and no overlapping entries for a person.
#'
#' @param db Connection list (from \code{syrona_connect}).
#' @param cohort_id Integer \code{cohort_definition_id} to filter by.
#' @param cohort_schema Schema containing the cohort table.
#' @param cohort_table Name of the cohort table. With \code{cohort_schema}
#'   the table in that schema (default \code{"cohort"}), without it a cohort
#'   in the cdm reference.
#' @return Modified \code{db} list with filtered CDM table references.
#' @export
apply_cohort_filter <- function(db, cohort_id, cohort_schema = NULL, cohort_table = NULL) {
  .apply_cohort_filter(db, cohort_id, cohort_schema, cohort_table, call = rlang::current_env())
}

# The filter itself. `call` is the user-facing function named in errors.
.apply_cohort_filter <- function(db, cohort_id, cohort_schema, cohort_table, call) {
  cohort_tbl <- .read_cohort_table(db, cohort_schema, cohort_table, call)
  where <- if (is.null(cohort_schema)) cohort_table else paste0(cohort_schema, ".", cohort_table %||% "cohort")

  missing_cols <- setdiff(c("cohort_definition_id", "subject_id", "cohort_start_date", "cohort_end_date"),
                          colnames(cohort_tbl))
  if (length(missing_cols) > 0) {
    cli::cli_abort(c(
      "{.val {where}} is not an OHDSI cohort table.",
      "x" = "Missing column{?s}: {.field {missing_cols}}."
    ), call = call)
  }

  cohort_tbl <- cohort_tbl |>
    dplyr::filter(.data$cohort_definition_id == !!cohort_id)

  n_cohort <- cohort_tbl |> dplyr::tally() |> dplyr::pull(n)
  if (n_cohort == 0) {
    cli::cli_abort(c(
      "Cohort {.val {cohort_id}} has no entries in {.val {where}}.",
      "i" = "Check {.arg cohort_id} and where the cohort table is."
    ), call = call)
  }

  # An entry that ends on or after the next entry's start overlaps it
  n_overlap <- cohort_tbl |>
    dplyr::group_by(.data$subject_id) |>
    dbplyr::window_order(.data$cohort_start_date, .data$cohort_end_date) |>
    dplyr::mutate(next_start = dplyr::lead(.data$cohort_start_date)) |>
    dplyr::ungroup() |>
    dplyr::filter(.data$cohort_end_date >= .data$next_start) |>
    dplyr::summarise(n = dplyr::n_distinct(.data$subject_id)) |>
    dplyr::pull(n)
  if (n_overlap > 0) {
    cli::cli_abort(c(
      "Cohort {.val {cohort_id}} has overlapping entries for {n_overlap} person{?s}.",
      "i" = "Each person's entries must not overlap. Merge overlapping entries into one before extracting. Cohorts generated in ATLAS never overlap."
    ), call = call)
  }
  n_persons <- cohort_tbl |>
    dplyr::summarise(n = dplyr::n_distinct(.data$subject_id, na.rm = TRUE)) |>
    dplyr::pull(n)
  cli::cli_alert_info("Cohort {.val {cohort_id}}: {n_cohort} person-entries found.")

  cohort_dates <- cohort_tbl |>
    dplyr::select("subject_id", "cohort_start_date", "cohort_end_date")

  # Person: filter to cohort members
  db$cdm$person <- db$cdm$person |>
    dplyr::semi_join(cohort_tbl, by = c("person_id" = "subject_id"))

  # Observation period: clip to cohort window
  db$cdm$observation_period <- db$cdm$observation_period |>
    dplyr::inner_join(cohort_dates, by = c("person_id" = "subject_id")) |>
    dplyr::mutate(
      observation_period_start_date = dplyr::if_else(
        .data$observation_period_start_date > .data$cohort_start_date,
        .data$observation_period_start_date,
        .data$cohort_start_date
      ),
      observation_period_end_date = dplyr::if_else(
        .data$observation_period_end_date < .data$cohort_end_date,
        .data$observation_period_end_date,
        .data$cohort_end_date
      )
    ) |>
    dplyr::filter(.data$observation_period_start_date <= .data$observation_period_end_date)

  # Death: within cohort window
  db$cdm$death <- db$cdm$death |>
    dplyr::inner_join(cohort_dates, by = c("person_id" = "subject_id")) |>
    dplyr::filter(
      .data$death_date >= .data$cohort_start_date,
      .data$death_date <= .data$cohort_end_date
    )

  # Event tables: within cohort window
  db$cdm$condition_occurrence <- db$cdm$condition_occurrence |>
    dplyr::inner_join(cohort_dates, by = c("person_id" = "subject_id")) |>
    dplyr::filter(
      .data$condition_start_date >= .data$cohort_start_date,
      .data$condition_start_date <= .data$cohort_end_date
    )

  db$cdm$procedure_occurrence <- db$cdm$procedure_occurrence |>
    dplyr::inner_join(cohort_dates, by = c("person_id" = "subject_id")) |>
    dplyr::filter(
      .data$procedure_date >= .data$cohort_start_date,
      .data$procedure_date <= .data$cohort_end_date
    )

  db$cdm$drug_exposure <- db$cdm$drug_exposure |>
    dplyr::inner_join(cohort_dates, by = c("person_id" = "subject_id")) |>
    dplyr::filter(
      .data$drug_exposure_start_date >= .data$cohort_start_date,
      .data$drug_exposure_start_date <= .data$cohort_end_date
    )

  # Which cohort was used, for _metadata.csv
  attr(db, "cohort_used") <- list(
    cohort_id = cohort_id,
    cohort_schema = cohort_schema %||% NA_character_,
    cohort_table = if (is.null(cohort_schema)) cohort_table else cohort_table %||% "cohort",
    cohort_entries = as.numeric(n_cohort),
    cohort_persons = as.numeric(n_persons)
  )
  db
}

# ── Care-site filtering ─────────────────────────────────────────────────────

#' Restrict CDM table references to one care site.
#'
#' Keeps persons with at least one visit at the care site, their whole
#' observation period and death records, and only the events whose
#' \code{visit_occurrence_id} is a visit at that care site. Events with no
#' visit link are dropped. All filtering runs in the database.
#'
#' @param db Connection list (from \code{syrona_connect}).
#' @param care_site_id One \code{care_site_id}.
#' @param domains Domains that will be extracted. A note is shown for each one
#'   with no events linked to the care site.
#' @param call The user-facing function named in errors.
#' @return Modified \code{db} list with filtered CDM table references. Its
#'   attribute \code{empty_domains} names the requested domains with no events
#'   linked to the care site.
#' @keywords internal
apply_care_site_filter <- function(db, care_site_id,
                                   domains = c("conditions", "procedures", "drugs"),
                                   call = rlang::caller_env()) {
  # An integer compares directly with the id column in SQL
  if (abs(care_site_id) <= .Machine$integer.max) care_site_id <- as.integer(care_site_id)

  site_visits <- db$cdm$visit_occurrence |>
    dplyr::filter(.data$care_site_id == !!care_site_id) |>
    dplyr::select("visit_occurrence_id", "person_id")
  site_persons <- site_visits |> dplyr::distinct(.data$person_id)

  n_visits <- as.numeric(site_visits |> dplyr::tally() |> dplyr::pull(n))
  if (n_visits == 0) {
    cli::cli_abort(c(
      "Care site {care_site_id} has no visits.",
      "i" = "{.code list_care_sites(db$con, cdm_schema = \"...\")} lists the care sites and their patient counts. Use the same {.arg cdm_schema} as when connecting."
    ), call = call)
  }
  n_persons <- as.numeric(site_persons |> dplyr::tally() |> dplyr::pull(n))
  cli::cli_alert_info("Care site {care_site_id}: {n_visits} visits, {n_persons} persons.")

  for (t in c("person", "observation_period", "death")) {
    db$cdm[[t]] <- db$cdm[[t]] |>
      dplyr::semi_join(site_persons, by = "person_id")
  }

  event_tables <- c(conditions = "condition_occurrence",
                    procedures = "procedure_occurrence",
                    drugs      = "drug_exposure")
  event_labels <- c(conditions = "condition", procedures = "procedure", drugs = "drug")
  empty_domains <- character(0)
  for (d in names(event_tables)) {
    t <- event_tables[[d]]
    db$cdm[[t]] <- db$cdm[[t]] |>
      dplyr::semi_join(site_visits |> dplyr::select("visit_occurrence_id"),
                       by = "visit_occurrence_id")
    if (d %in% domains) {
      n_events <- as.numeric(db$cdm[[t]] |> dplyr::tally() |> dplyr::pull(n))
      if (n_events == 0) {
        empty_domains <- c(empty_domains, d)
        cli::cli_alert_warning(
          "No {event_labels[[d]]} events are linked to visits at care site {care_site_id}, so the {d} tables are empty."
        )
      }
    }
  }

  attr(db, "empty_domains") <- empty_domains
  db
}

# ── Temporary tables ────────────────────────────────────────────────────────

# Small lookup lists (years, concept ids) are copied into temporary tables so
# the joins run in the database. Each name is unique to the call, so no
# existing table can be replaced, and only that table is removed afterwards.
# tempfile() gives the unique part without touching the random number seed.
.temp_table_name <- function(label) {
  paste0("syrona_tmp_", label, "_", basename(tempfile("")))
}

# ── Shared extractors ───────────────────────────────────────────────────────

#' Extract the ACHILLES-116 denominator: persons observed per year x sex x age group.
#' @param cdm CDM reference object.
#' @return tibble with columns: year, sex, age_group, denominator
#' @keywords internal
extract_denominators <- function(cdm) {
  year_range <- cdm$observation_period |>
    dplyr::summarise(
      min_year = min(year(.data$observation_period_start_date), na.rm = TRUE),
      max_year = max(year(.data$observation_period_end_date), na.rm = TRUE)
    ) |>
    dplyr::collect()

  years_df <- tibble::tibble(obs_year = seq(year_range$min_year, year_range$max_year))
  con <- CDMConnector::cdmCon(cdm)
  tmp_name <- .temp_table_name("years")
  years_tbl <- dplyr::copy_to(con, years_df, name = tmp_name, temporary = TRUE)

  denom <- cdm$observation_period |>
    dplyr::inner_join(cdm$person, by = "person_id") |>
    dplyr::cross_join(years_tbl) |>
    dplyr::filter(
      year(.data$observation_period_start_date) <= .data$obs_year,
      year(.data$observation_period_end_date)   >= .data$obs_year,
      .data$gender_concept_id %in% c(8532L, 8507L)
    ) |>
    dplyr::mutate(
      sex = dplyr::if_else(.data$gender_concept_id == 8532L, "F", "M"),
      age_decade = floor((.data$obs_year - .data$year_of_birth) / 10) * 10,
      age_decade = dplyr::case_when(
        .data$age_decade < 0  ~ 0,
        .data$age_decade > AGE_CLAMP_MAX ~ AGE_CLAMP_MAX,
        TRUE ~ .data$age_decade
      )
    ) |>
    dplyr::group_by(.data$obs_year, .data$sex, .data$age_decade) |>
    dplyr::summarise(denominator = dplyr::n_distinct(.data$person_id), .groups = "drop") |>
    dplyr::collect() |>
    dplyr::mutate(
      age_group = dplyr::if_else(
        .data$age_decade == AGE_CLAMP_MAX,
        paste0(AGE_CLAMP_MAX, "+"),
        paste0(.data$age_decade, "-", .data$age_decade + 9)
      ),
      year = as.integer(.data$obs_year)
    ) |>
    dplyr::select("year", "sex", "age_group", "denominator")

  try(DBI::dbRemoveTable(con, tmp_name), silent = TRUE)
  denom
}

#' Extract demographics (birth year x sex).
#' @param cdm CDM reference object.
#' @return tibble with columns: sex, birth_year, patient_count
#' @keywords internal
extract_demographics <- function(cdm) {
  cdm$person |>
    dplyr::filter(.data$gender_concept_id %in% c(8532L, 8507L)) |>
    dplyr::mutate(sex = dplyr::if_else(.data$gender_concept_id == 8532L, "F", "M")) |>
    dplyr::group_by(.data$sex, .data$year_of_birth) |>
    dplyr::summarise(patient_count = dplyr::n(), .groups = "drop") |>
    dplyr::collect() |>
    dplyr::rename(birth_year = "year_of_birth") |>
    dplyr::arrange(.data$sex, .data$birth_year)
}

#' Extract death counts by year x sex x age group (ACHILLES-504 pattern).
#' @param cdm CDM reference object.
#' @param denom_df Pre-computed denominator tibble.
#' @return tibble with columns: year, sex, age_group, death_count, denominator, mortality_rate
#' @keywords internal
extract_death_counts <- function(cdm, denom_df) {
  n_deaths <- cdm$death |> dplyr::tally() |> dplyr::pull(n)
  if (n_deaths == 0) {
    cli::cli_alert_info("Death table is empty - returning empty death_counts.")
    return(tibble::tibble(
      year = integer(), sex = character(), age_group = character(),
      death_count = integer(), denominator = integer(), mortality_rate = numeric()
    ))
  }

  deaths <- cdm$death |>
    dplyr::inner_join(cdm$person, by = "person_id") |>
    dplyr::inner_join(cdm$observation_period, by = "person_id") |>
    dplyr::filter(
      .data$death_date >= .data$observation_period_start_date,
      .data$death_date <= .data$observation_period_end_date,
      .data$gender_concept_id %in% c(8532L, 8507L)
    ) |>
    dplyr::mutate(
      death_year = year(.data$death_date),
      sex = dplyr::if_else(.data$gender_concept_id == 8532L, "F", "M"),
      age_decade = floor((.data$death_year - .data$year_of_birth) / 10) * 10,
      age_decade = dplyr::case_when(
        .data$age_decade < 0  ~ 0,
        .data$age_decade > AGE_CLAMP_MAX ~ AGE_CLAMP_MAX,
        TRUE ~ .data$age_decade
      )
    ) |>
    dplyr::group_by(.data$death_year, .data$sex, .data$age_decade) |>
    dplyr::summarise(death_count = dplyr::n_distinct(.data$person_id), .groups = "drop") |>
    dplyr::collect() |>
    dplyr::mutate(
      age_group = dplyr::if_else(
        .data$age_decade == AGE_CLAMP_MAX,
        paste0(AGE_CLAMP_MAX, "+"),
        paste0(.data$age_decade, "-", .data$age_decade + 9)
      ),
      year = as.integer(.data$death_year)
    ) |>
    dplyr::select("year", "sex", "age_group", "death_count")

  deaths |>
    dplyr::left_join(denom_df, by = c("year", "sex", "age_group")) |>
    dplyr::mutate(mortality_rate = .data$death_count / .data$denominator) |>
    dplyr::arrange(.data$year, .data$sex, .data$age_group)
}

# ── Condition extractors ────────────────────────────────────────────────────

#' Extract condition prevalence (ACHILLES-404 numerator + 116 denominator).
#' @param cdm CDM reference object.
#' @param denom_df Pre-computed denominator tibble.
#' @return tibble with columns: concept_id, year, sex, age_group,
#'   patient_count, record_count, denominator, prevalence
#' @keywords internal
extract_condition_prevalence <- function(cdm, denom_df) {
  numerator <- cdm$condition_occurrence |>
    dplyr::filter(.data$condition_concept_id != 0L) |>
    dplyr::inner_join(cdm$person, by = "person_id") |>
    dplyr::inner_join(cdm$observation_period, by = "person_id") |>
    dplyr::filter(
      .data$condition_start_date >= .data$observation_period_start_date,
      .data$condition_start_date <= .data$observation_period_end_date,
      .data$gender_concept_id %in% c(8532L, 8507L)
    ) |>
    dplyr::mutate(
      event_year = year(.data$condition_start_date),
      sex = dplyr::if_else(.data$gender_concept_id == 8532L, "F", "M"),
      age_decade = floor((.data$event_year - .data$year_of_birth) / 10) * 10,
      age_decade = dplyr::case_when(
        .data$age_decade < 0  ~ 0,
        .data$age_decade > AGE_CLAMP_MAX ~ AGE_CLAMP_MAX,
        TRUE ~ .data$age_decade
      )
    ) |>
    dplyr::group_by(.data$condition_concept_id, .data$event_year, .data$sex, .data$age_decade) |>
    dplyr::summarise(
      patient_count = dplyr::n_distinct(.data$person_id),
      record_count  = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::collect() |>
    dplyr::mutate(
      age_group = dplyr::if_else(
        .data$age_decade == AGE_CLAMP_MAX,
        paste0(AGE_CLAMP_MAX, "+"),
        paste0(.data$age_decade, "-", .data$age_decade + 9)
      ),
      year = as.integer(.data$event_year),
      concept_id = as.integer(.data$condition_concept_id)
    ) |>
    dplyr::select("concept_id", "year", "sex", "age_group", "patient_count", "record_count")

  numerator |>
    dplyr::left_join(denom_df, by = c("year", "sex", "age_group")) |>
    dplyr::mutate(prevalence = .data$patient_count / .data$denominator) |>
    dplyr::arrange(.data$concept_id, .data$year, .data$sex, .data$age_group)
}

#' Extract condition concept metadata.
#' @param cdm CDM reference object.
#' @return tibble with columns: concept_id, concept_name, concept_code,
#'   vocabulary_id, concept_class_id, n_patients_total, n_records_total
#' @keywords internal
extract_condition_info <- function(cdm) {
  counts <- cdm$condition_occurrence |>
    dplyr::filter(.data$condition_concept_id != 0L) |>
    dplyr::group_by(.data$condition_concept_id) |>
    dplyr::summarise(
      n_patients_total = dplyr::n_distinct(.data$person_id),
      n_records_total  = dplyr::n(),
      .groups = "drop"
    )

  counts |>
    dplyr::inner_join(
      cdm$concept |>
        dplyr::filter(.data$vocabulary_id == "SNOMED", .data$standard_concept == "S") |>
        dplyr::select("concept_id", "concept_name", "concept_code",
                      "vocabulary_id", "concept_class_id"),
      by = c("condition_concept_id" = "concept_id")
    ) |>
    dplyr::collect() |>
    dplyr::mutate(concept_id = as.integer(.data$condition_concept_id)) |>
    dplyr::select("concept_id", "concept_name", "concept_code", "vocabulary_id",
                  "concept_class_id", "n_patients_total", "n_records_total") |>
    dplyr::arrange(dplyr::desc(.data$n_patients_total))
}

#' Extract condition chapter and sub-chapter assignments.
#' @param cdm CDM reference object.
#' @param condition_ids Integer vector of concept_ids to assign chapters to.
#' @return tibble with columns: concept_id, chapter_type, chapter_id, chapter_name,
#'   chapter_level, parent_chapter_id
#' @keywords internal
extract_condition_chapters <- function(cdm, condition_ids) {
  con <- CDMConnector::cdmCon(cdm)

  ids_df <- tibble::tibble(concept_id = as.integer(condition_ids))
  tmp_name <- .temp_table_name("cond_ids")
  ids_tbl <- dplyr::copy_to(con, ids_df, name = tmp_name, temporary = TRUE)

  # Helper: get L1 + L2 chapter assignments for a given root
  get_chapters_for_root <- function(root_id, chapter_type, exclude_id = NULL) {
    l1_chapters <- cdm$concept_ancestor |>
      dplyr::filter(
        .data$ancestor_concept_id == root_id,
        .data$min_levels_of_separation == 1L
      ) |>
      dplyr::select(chapter_id = "descendant_concept_id")

    if (!is.null(exclude_id)) {
      l1_chapters <- l1_chapters |> dplyr::filter(.data$chapter_id != exclude_id)
    }

    l1_result <- cdm$concept_ancestor |>
      dplyr::inner_join(l1_chapters, by = c("ancestor_concept_id" = "chapter_id")) |>
      dplyr::inner_join(ids_tbl, by = c("descendant_concept_id" = "concept_id")) |>
      dplyr::select(concept_id = "descendant_concept_id", chapter_id = "ancestor_concept_id") |>
      dplyr::distinct() |>
      dplyr::inner_join(
        cdm$concept |> dplyr::select("concept_id", "concept_name"),
        by = c("chapter_id" = "concept_id")
      ) |>
      dplyr::mutate(chapter_type = chapter_type) |>
      dplyr::select("concept_id", "chapter_type", "chapter_id",
                    chapter_name = "concept_name") |>
      dplyr::collect() |>
      dplyr::mutate(chapter_level = 1L, parent_chapter_id = NA_integer_)

    l2_nodes <- cdm$concept_ancestor |>
      dplyr::inner_join(l1_chapters, by = c("ancestor_concept_id" = "chapter_id")) |>
      dplyr::filter(.data$min_levels_of_separation == 1L) |>
      dplyr::select(l2_chapter_id = "descendant_concept_id",
                    parent_chapter_id = "ancestor_concept_id")

    l2_result <- cdm$concept_ancestor |>
      dplyr::inner_join(l2_nodes, by = c("ancestor_concept_id" = "l2_chapter_id")) |>
      dplyr::inner_join(ids_tbl, by = c("descendant_concept_id" = "concept_id")) |>
      dplyr::select(concept_id = "descendant_concept_id",
                    chapter_id = "ancestor_concept_id",
                    "parent_chapter_id") |>
      dplyr::distinct() |>
      dplyr::inner_join(
        cdm$concept |> dplyr::select("concept_id", "concept_name"),
        by = c("chapter_id" = "concept_id")
      ) |>
      dplyr::mutate(chapter_type = chapter_type) |>
      dplyr::select("concept_id", "chapter_type", "chapter_id",
                    chapter_name = "concept_name", "parent_chapter_id") |>
      dplyr::collect() |>
      dplyr::mutate(chapter_level = 2L, parent_chapter_id = as.integer(.data$parent_chapter_id))

    dplyr::bind_rows(l1_result, l2_result)
  }

  # ICD-10 chapter assignments via SNOMED -> ICD-10 mapping
  get_icd10_chapters <- function() {
    chap_ranges <- tibble::tribble(
      ~range_start, ~range_end, ~chapter_roman,
      "A00", "B99", "I",    "C00", "D48", "II",   "D50", "D89", "III",
      "E00", "E90", "IV",   "F00", "F99", "V",    "G00", "G99", "VI",
      "H00", "H59", "VII",  "H60", "H95", "VIII", "I00", "I99", "IX",
      "J00", "J99", "X",    "K00", "K93", "XI",   "L00", "L99", "XII",
      "M00", "M99", "XIII", "N00", "N99", "XIV",  "O00", "O99", "XV",
      "P00", "P96", "XVI",  "Q00", "Q99", "XVII", "R00", "R99", "XVIII",
      "S00", "T98", "XIX",  "V01", "Y98", "XX",   "Z00", "Z99", "XXI",
      "U00", "U99", "XXII"
    )

    chap_concepts <- cdm$concept |>
      dplyr::filter(.data$vocabulary_id == "ICD10", .data$concept_class_id == "ICD10 Chapter") |>
      dplyr::select(chapter_id = "concept_id", chapter_code = "concept_code",
                    raw_name = "concept_name") |>
      dplyr::collect()

    chap_lookup <- chap_ranges |>
      dplyr::left_join(chap_concepts, by = c("chapter_roman" = "chapter_code")) |>
      dplyr::mutate(chapter_name = paste0(.data$range_start, "-", .data$range_end, ". ", .data$raw_name))

    snomed_to_icd10 <- cdm$concept_relationship |>
      dplyr::filter(.data$relationship_id == "Mapped from") |>
      dplyr::inner_join(ids_tbl, by = c("concept_id_1" = "concept_id")) |>
      dplyr::inner_join(
        cdm$concept |>
          dplyr::filter(.data$vocabulary_id %in% c("ICD10", "ICD10CM")) |>
          dplyr::select("concept_id", "concept_code"),
        by = c("concept_id_2" = "concept_id")
      ) |>
      dplyr::select(concept_id = "concept_id_1", icd10_concept_code = "concept_code") |>
      dplyr::distinct() |>
      dplyr::collect()

    if (nrow(snomed_to_icd10) == 0) {
      mapped <- tibble::tibble(
        concept_id = integer(), chapter_type = character(),
        chapter_id = integer(), chapter_name = character()
      )
    } else {
      snomed_to_icd10 <- snomed_to_icd10 |>
        dplyr::mutate(code3 = toupper(substr(.data$icd10_concept_code, 1, 3)))

      assign_chapter <- function(code3) {
        for (i in seq_len(nrow(chap_lookup))) {
          if (code3 >= chap_lookup$range_start[i] && code3 <= chap_lookup$range_end[i]) {
            return(i)
          }
        }
        NA_integer_
      }

      snomed_to_icd10$chap_idx <- vapply(snomed_to_icd10$code3, assign_chapter, integer(1))

      mapped <- snomed_to_icd10 |>
        dplyr::filter(!is.na(.data$chap_idx)) |>
        dplyr::mutate(
          chapter_id   = chap_lookup$chapter_id[.data$chap_idx],
          chapter_name = chap_lookup$chapter_name[.data$chap_idx]
        ) |>
        dplyr::select("concept_id", "chapter_id", "chapter_name") |>
        dplyr::distinct() |>
        dplyr::mutate(
          chapter_type = "icd10_chapter",
          chapter_level = 1L,
          parent_chapter_id = NA_integer_
        ) |>
        dplyr::select("concept_id", "chapter_type", "chapter_id", "chapter_name",
                      "chapter_level", "parent_chapter_id")
    }

    # Add "(Unmapped)" pseudo-chapter
    mapped_ids <- unique(mapped$concept_id)
    unmapped_ids <- setdiff(condition_ids, mapped_ids)
    if (length(unmapped_ids) > 0) {
      unmapped_rows <- tibble::tibble(
        concept_id        = unmapped_ids,
        chapter_type      = "icd10_chapter",
        chapter_id        = 0L,
        chapter_name      = "(Unmapped)",
        chapter_level     = 1L,
        parent_chapter_id = NA_integer_
      )
      mapped <- dplyr::bind_rows(mapped, unmapped_rows)
    }

    mapped
  }

  body_sys <- get_chapters_for_root(CHAPTER_ROOTS$body_system, "body_system")
  disease_cat <- get_chapters_for_root(
    CHAPTER_ROOTS$disease_category, "disease_category",
    exclude_id = CHAPTER_ROOTS$body_system
  )

  cli::cli_alert_info("ICD-10 chapters...")
  icd10_chap <- get_icd10_chapters()

  try(DBI::dbRemoveTable(con, tmp_name), silent = TRUE)

  coerce_ids <- function(df) {
    df |> dplyr::mutate(
      concept_id = as.integer(.data$concept_id),
      chapter_id = as.integer(.data$chapter_id),
      parent_chapter_id = as.integer(.data$parent_chapter_id)
    )
  }
  dplyr::bind_rows(coerce_ids(body_sys), coerce_ids(disease_cat), coerce_ids(icd10_chap)) |>
    dplyr::arrange(.data$chapter_type, .data$chapter_level, .data$chapter_name, .data$concept_id)
}

#' Extract condition SNOMED attributes.
#' @param cdm CDM reference object.
#' @param condition_ids Integer vector of concept_ids.
#' @return tibble with columns: concept_id, relationship, target_concept_id, target_concept_name
#' @keywords internal
extract_condition_attributes <- function(cdm, condition_ids) {
  con <- CDMConnector::cdmCon(cdm)
  ids_df <- tibble::tibble(concept_id = as.integer(condition_ids))
  tmp_name <- .temp_table_name("cond_ids_attr")
  ids_tbl <- dplyr::copy_to(con, ids_df, name = tmp_name, temporary = TRUE)

  all_attrs <- cdm$concept_relationship |>
    dplyr::inner_join(ids_tbl, by = c("concept_id_1" = "concept_id")) |>
    dplyr::filter(.data$relationship_id %in% !!unname(CONDITION_RELATIONSHIPS)) |>
    dplyr::inner_join(
      cdm$concept |> dplyr::select("concept_id", "concept_name"),
      by = c("concept_id_2" = "concept_id")
    ) |>
    dplyr::select(
      concept_id = "concept_id_1", relationship_id = "relationship_id",
      target_concept_id = "concept_id_2", target_concept_name = "concept_name"
    ) |>
    dplyr::collect()

  try(DBI::dbRemoveTable(con, tmp_name), silent = TRUE)

  rel_map <- stats::setNames(names(CONDITION_RELATIONSHIPS), unname(CONDITION_RELATIONSHIPS))

  all_attrs |>
    dplyr::mutate(
      concept_id = as.integer(.data$concept_id),
      target_concept_id = as.integer(.data$target_concept_id),
      relationship = rel_map[.data$relationship_id]
    ) |>
    dplyr::select("concept_id", "relationship", "target_concept_id", "target_concept_name") |>
    dplyr::arrange(.data$concept_id, .data$relationship, .data$target_concept_name)
}

# ── Procedure extractors ────────────────────────────────────────────────────

#' Extract procedure prevalence.
#' @param cdm CDM reference object.
#' @param denom_df Pre-computed denominator tibble.
#' @return tibble with columns: concept_id, year, sex, age_group,
#'   patient_count, record_count, denominator, prevalence
#' @keywords internal
extract_procedure_prevalence <- function(cdm, denom_df) {
  numerator <- cdm$procedure_occurrence |>
    dplyr::filter(.data$procedure_concept_id != 0L) |>
    dplyr::inner_join(cdm$person, by = "person_id") |>
    dplyr::inner_join(cdm$observation_period, by = "person_id") |>
    dplyr::filter(
      .data$procedure_date >= .data$observation_period_start_date,
      .data$procedure_date <= .data$observation_period_end_date,
      .data$gender_concept_id %in% c(8532L, 8507L)
    ) |>
    dplyr::mutate(
      event_year = year(.data$procedure_date),
      sex = dplyr::if_else(.data$gender_concept_id == 8532L, "F", "M"),
      age_decade = floor((.data$event_year - .data$year_of_birth) / 10) * 10,
      age_decade = dplyr::case_when(
        .data$age_decade < 0  ~ 0,
        .data$age_decade > AGE_CLAMP_MAX ~ AGE_CLAMP_MAX,
        TRUE ~ .data$age_decade
      )
    ) |>
    dplyr::group_by(.data$procedure_concept_id, .data$event_year, .data$sex, .data$age_decade) |>
    dplyr::summarise(
      patient_count = dplyr::n_distinct(.data$person_id),
      record_count  = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::collect() |>
    dplyr::mutate(
      age_group = dplyr::if_else(
        .data$age_decade == AGE_CLAMP_MAX,
        paste0(AGE_CLAMP_MAX, "+"),
        paste0(.data$age_decade, "-", .data$age_decade + 9)
      ),
      year = as.integer(.data$event_year),
      concept_id = as.integer(.data$procedure_concept_id)
    ) |>
    dplyr::select("concept_id", "year", "sex", "age_group", "patient_count", "record_count")

  numerator |>
    dplyr::left_join(denom_df, by = c("year", "sex", "age_group")) |>
    dplyr::mutate(prevalence = .data$patient_count / .data$denominator) |>
    dplyr::arrange(.data$concept_id, .data$year, .data$sex, .data$age_group)
}

#' Extract procedure concept metadata.
#' @param cdm CDM reference object.
#' @return tibble with same columns as extract_condition_info.
#' @keywords internal
extract_procedure_info <- function(cdm) {
  counts <- cdm$procedure_occurrence |>
    dplyr::filter(.data$procedure_concept_id != 0L) |>
    dplyr::group_by(.data$procedure_concept_id) |>
    dplyr::summarise(
      n_patients_total = dplyr::n_distinct(.data$person_id),
      n_records_total  = dplyr::n(),
      .groups = "drop"
    )

  counts |>
    dplyr::inner_join(
      cdm$concept |>
        dplyr::filter(.data$standard_concept == "S") |>
        dplyr::select("concept_id", "concept_name", "concept_code",
                      "vocabulary_id", "concept_class_id"),
      by = c("procedure_concept_id" = "concept_id")
    ) |>
    dplyr::collect() |>
    dplyr::mutate(concept_id = as.integer(.data$procedure_concept_id)) |>
    dplyr::select("concept_id", "concept_name", "concept_code", "vocabulary_id",
                  "concept_class_id", "n_patients_total", "n_records_total") |>
    dplyr::arrange(dplyr::desc(.data$n_patients_total))
}

#' Extract procedure chapter and sub-chapter assignments.
#' @param cdm CDM reference object.
#' @param procedure_ids Integer vector of concept_ids.
#' @return tibble with same columns as extract_condition_chapters.
#' @keywords internal
extract_procedure_chapters <- function(cdm, procedure_ids) {
  con <- CDMConnector::cdmCon(cdm)
  ids_df <- tibble::tibble(concept_id = as.integer(procedure_ids))
  tmp_name <- .temp_table_name("proc_ids")
  ids_tbl <- dplyr::copy_to(con, ids_df, name = tmp_name, temporary = TRUE)

  get_chapters_for_root <- function(root_id, chapter_type) {
    l1_chapters <- cdm$concept_ancestor |>
      dplyr::filter(
        .data$ancestor_concept_id == root_id,
        .data$min_levels_of_separation == 1L
      ) |>
      dplyr::select(chapter_id = "descendant_concept_id")

    l1_result <- cdm$concept_ancestor |>
      dplyr::inner_join(l1_chapters, by = c("ancestor_concept_id" = "chapter_id")) |>
      dplyr::inner_join(ids_tbl, by = c("descendant_concept_id" = "concept_id")) |>
      dplyr::select(concept_id = "descendant_concept_id",
                    chapter_id = "ancestor_concept_id") |>
      dplyr::distinct() |>
      dplyr::inner_join(
        cdm$concept |> dplyr::select("concept_id", "concept_name"),
        by = c("chapter_id" = "concept_id")
      ) |>
      dplyr::mutate(chapter_type = chapter_type) |>
      dplyr::select("concept_id", "chapter_type", "chapter_id",
                    chapter_name = "concept_name") |>
      dplyr::collect() |>
      dplyr::mutate(chapter_level = 1L, parent_chapter_id = NA_integer_)

    l2_nodes <- cdm$concept_ancestor |>
      dplyr::inner_join(l1_chapters, by = c("ancestor_concept_id" = "chapter_id")) |>
      dplyr::filter(.data$min_levels_of_separation == 1L) |>
      dplyr::select(l2_chapter_id = "descendant_concept_id",
                    parent_chapter_id = "ancestor_concept_id")

    l2_result <- cdm$concept_ancestor |>
      dplyr::inner_join(l2_nodes, by = c("ancestor_concept_id" = "l2_chapter_id")) |>
      dplyr::inner_join(ids_tbl, by = c("descendant_concept_id" = "concept_id")) |>
      dplyr::select(concept_id = "descendant_concept_id",
                    chapter_id = "ancestor_concept_id",
                    "parent_chapter_id") |>
      dplyr::distinct() |>
      dplyr::inner_join(
        cdm$concept |> dplyr::select("concept_id", "concept_name"),
        by = c("chapter_id" = "concept_id")
      ) |>
      dplyr::mutate(chapter_type = chapter_type) |>
      dplyr::select("concept_id", "chapter_type", "chapter_id",
                    chapter_name = "concept_name", "parent_chapter_id") |>
      dplyr::collect() |>
      dplyr::mutate(chapter_level = 2L, parent_chapter_id = as.integer(.data$parent_chapter_id))

    dplyr::bind_rows(l1_result, l2_result)
  }

  cli::cli_alert_info("Procedure chapters by method...")
  by_method <- get_chapters_for_root(PROCEDURE_CHAPTER_ROOTS$by_method, "by_method")

  cli::cli_alert_info("Procedure chapters by site...")
  by_site <- get_chapters_for_root(PROCEDURE_CHAPTER_ROOTS$by_site, "by_site")

  try(DBI::dbRemoveTable(con, tmp_name), silent = TRUE)

  coerce_ids <- function(df) {
    df |> dplyr::mutate(
      concept_id = as.integer(.data$concept_id),
      chapter_id = as.integer(.data$chapter_id),
      parent_chapter_id = as.integer(.data$parent_chapter_id)
    )
  }
  dplyr::bind_rows(coerce_ids(by_method), coerce_ids(by_site)) |>
    dplyr::arrange(.data$chapter_type, .data$chapter_level, .data$chapter_name, .data$concept_id)
}

#' Extract procedure SNOMED attributes.
#' @param cdm CDM reference object.
#' @param procedure_ids Integer vector of concept_ids.
#' @return tibble with same columns as extract_condition_attributes.
#' @keywords internal
extract_procedure_attributes <- function(cdm, procedure_ids) {
  con <- CDMConnector::cdmCon(cdm)
  ids_df <- tibble::tibble(concept_id = as.integer(procedure_ids))
  tmp_name <- .temp_table_name("proc_ids_attr")
  ids_tbl <- dplyr::copy_to(con, ids_df, name = tmp_name, temporary = TRUE)

  all_attrs <- cdm$concept_relationship |>
    dplyr::inner_join(ids_tbl, by = c("concept_id_1" = "concept_id")) |>
    dplyr::filter(.data$relationship_id %in% !!unname(PROCEDURE_RELATIONSHIPS)) |>
    dplyr::inner_join(
      cdm$concept |> dplyr::select("concept_id", "concept_name"),
      by = c("concept_id_2" = "concept_id")
    ) |>
    dplyr::select(
      concept_id = "concept_id_1", relationship_id = "relationship_id",
      target_concept_id = "concept_id_2", target_concept_name = "concept_name"
    ) |>
    dplyr::collect()

  try(DBI::dbRemoveTable(con, tmp_name), silent = TRUE)

  rel_map <- stats::setNames(names(PROCEDURE_RELATIONSHIPS), unname(PROCEDURE_RELATIONSHIPS))

  all_attrs |>
    dplyr::mutate(
      concept_id = as.integer(.data$concept_id),
      target_concept_id = as.integer(.data$target_concept_id),
      relationship = rel_map[.data$relationship_id]
    ) |>
    dplyr::select("concept_id", "relationship", "target_concept_id", "target_concept_name") |>
    dplyr::arrange(.data$concept_id, .data$relationship, .data$target_concept_name)
}

# ── Drug extractors ─────────────────────────────────────────────────────────

#' Extract drug prevalence at the Ingredient level.
#' @param cdm CDM reference object.
#' @param denom_df Pre-computed denominator tibble.
#' @return tibble with same columns as extract_condition_prevalence.
#' @keywords internal
extract_drug_prevalence <- function(cdm, denom_df) {
  drug_to_ingredient <- cdm$drug_exposure |>
    dplyr::filter(.data$drug_concept_id != 0L) |>
    dplyr::select("drug_concept_id") |>
    dplyr::distinct() |>
    dplyr::inner_join(
      cdm$concept_ancestor |>
        dplyr::inner_join(
          cdm$concept |>
            dplyr::filter(.data$concept_class_id == "Ingredient",
                          .data$standard_concept == "S") |>
            dplyr::select("concept_id"),
          by = c("ancestor_concept_id" = "concept_id")
        ) |>
        dplyr::select("descendant_concept_id",
                      ingredient_concept_id = "ancestor_concept_id"),
      by = c("drug_concept_id" = "descendant_concept_id")
    )

  numerator <- cdm$drug_exposure |>
    dplyr::filter(.data$drug_concept_id != 0L) |>
    dplyr::inner_join(drug_to_ingredient, by = "drug_concept_id") |>
    dplyr::inner_join(cdm$person, by = "person_id") |>
    dplyr::inner_join(cdm$observation_period, by = "person_id") |>
    dplyr::filter(
      .data$drug_exposure_start_date >= .data$observation_period_start_date,
      .data$drug_exposure_start_date <= .data$observation_period_end_date,
      .data$gender_concept_id %in% c(8532L, 8507L)
    ) |>
    dplyr::mutate(
      event_year = year(.data$drug_exposure_start_date),
      sex = dplyr::if_else(.data$gender_concept_id == 8532L, "F", "M"),
      age_decade = floor((.data$event_year - .data$year_of_birth) / 10) * 10,
      age_decade = dplyr::case_when(
        .data$age_decade < 0  ~ 0,
        .data$age_decade > AGE_CLAMP_MAX ~ AGE_CLAMP_MAX,
        TRUE ~ .data$age_decade
      )
    ) |>
    dplyr::group_by(.data$ingredient_concept_id, .data$event_year, .data$sex, .data$age_decade) |>
    dplyr::summarise(
      patient_count = dplyr::n_distinct(.data$person_id),
      record_count  = dplyr::n(),
      .groups = "drop"
    ) |>
    dplyr::collect() |>
    dplyr::mutate(
      age_group = dplyr::if_else(
        .data$age_decade == AGE_CLAMP_MAX,
        paste0(AGE_CLAMP_MAX, "+"),
        paste0(.data$age_decade, "-", .data$age_decade + 9)
      ),
      year = as.integer(.data$event_year),
      concept_id = as.integer(.data$ingredient_concept_id)
    ) |>
    dplyr::select("concept_id", "year", "sex", "age_group", "patient_count", "record_count")

  numerator |>
    dplyr::left_join(denom_df, by = c("year", "sex", "age_group")) |>
    dplyr::mutate(prevalence = .data$patient_count / .data$denominator) |>
    dplyr::arrange(.data$concept_id, .data$year, .data$sex, .data$age_group)
}

#' Extract drug (ingredient) concept metadata.
#' @param cdm CDM reference object.
#' @return tibble with same columns as extract_condition_info.
#' @keywords internal
extract_drug_info <- function(cdm) {
  drug_to_ingredient <- cdm$drug_exposure |>
    dplyr::filter(.data$drug_concept_id != 0L) |>
    dplyr::select("drug_concept_id") |>
    dplyr::distinct() |>
    dplyr::inner_join(
      cdm$concept_ancestor |>
        dplyr::inner_join(
          cdm$concept |>
            dplyr::filter(.data$concept_class_id == "Ingredient",
                          .data$standard_concept == "S") |>
            dplyr::select("concept_id"),
          by = c("ancestor_concept_id" = "concept_id")
        ) |>
        dplyr::select("descendant_concept_id",
                      ingredient_concept_id = "ancestor_concept_id"),
      by = c("drug_concept_id" = "descendant_concept_id")
    )

  counts <- cdm$drug_exposure |>
    dplyr::filter(.data$drug_concept_id != 0L) |>
    dplyr::inner_join(drug_to_ingredient, by = "drug_concept_id") |>
    dplyr::group_by(.data$ingredient_concept_id) |>
    dplyr::summarise(
      n_patients_total = dplyr::n_distinct(.data$person_id),
      n_records_total  = dplyr::n(),
      .groups = "drop"
    )

  counts |>
    dplyr::inner_join(
      cdm$concept |>
        dplyr::filter(.data$concept_class_id == "Ingredient",
                      .data$standard_concept == "S") |>
        dplyr::select("concept_id", "concept_name", "concept_code",
                      "vocabulary_id", "concept_class_id"),
      by = c("ingredient_concept_id" = "concept_id")
    ) |>
    dplyr::collect() |>
    dplyr::mutate(concept_id = as.integer(.data$ingredient_concept_id)) |>
    dplyr::select("concept_id", "concept_name", "concept_code", "vocabulary_id",
                  "concept_class_id", "n_patients_total", "n_records_total") |>
    dplyr::arrange(dplyr::desc(.data$n_patients_total))
}

#' Extract drug chapter assignments (ATC 1st level).
#' @param cdm CDM reference object.
#' @param drug_ids Integer vector of Ingredient concept_ids.
#' @return tibble with same columns as extract_condition_chapters.
#' @keywords internal
extract_drug_chapters <- function(cdm, drug_ids) {
  con <- CDMConnector::cdmCon(cdm)
  ids_df <- tibble::tibble(concept_id = as.integer(drug_ids))
  tmp_name <- .temp_table_name("drug_ids")
  ids_tbl <- dplyr::copy_to(con, ids_df, name = tmp_name, temporary = TRUE)

  atc_chapters <- cdm$concept |>
    dplyr::filter(.data$vocabulary_id == ATC_CHAPTER_VOCAB,
                  .data$concept_class_id == ATC_CHAPTER_CLASS) |>
    dplyr::select(chapter_id = "concept_id", chapter_code = "concept_code",
                  chapter_name = "concept_name")

  mapped <- cdm$concept_ancestor |>
    dplyr::inner_join(atc_chapters, by = c("ancestor_concept_id" = "chapter_id")) |>
    dplyr::inner_join(ids_tbl, by = c("descendant_concept_id" = "concept_id")) |>
    dplyr::select(concept_id = "descendant_concept_id",
                  chapter_id = "ancestor_concept_id",
                  "chapter_code", "chapter_name") |>
    dplyr::distinct() |>
    dplyr::collect() |>
    dplyr::mutate(
      chapter_type = "atc_1st",
      chapter_name = paste0(.data$chapter_code, ". ", .data$chapter_name),
      concept_id = as.integer(.data$concept_id),
      chapter_id = as.integer(.data$chapter_id),
      chapter_level = 1L,
      parent_chapter_id = NA_integer_
    ) |>
    dplyr::select("concept_id", "chapter_type", "chapter_id", "chapter_name",
                  "chapter_level", "parent_chapter_id")

  # "(Unmapped)" pseudo-chapter for ingredients without ATC ancestor
  mapped_ids <- unique(mapped$concept_id)
  unmapped_ids <- setdiff(drug_ids, mapped_ids)
  if (length(unmapped_ids) > 0) {
    unmapped_rows <- tibble::tibble(
      concept_id        = unmapped_ids,
      chapter_type      = "atc_1st",
      chapter_id        = 0L,
      chapter_name      = "(Unmapped)",
      chapter_level     = 1L,
      parent_chapter_id = NA_integer_
    )
    mapped <- dplyr::bind_rows(mapped, unmapped_rows)
  }

  try(DBI::dbRemoveTable(con, tmp_name), silent = TRUE)
  mapped |> dplyr::arrange(.data$chapter_type, .data$chapter_name, .data$concept_id)
}

# ── k-Anonymity suppression ────────────────────────────────────────────────

#' Apply k-anonymity suppression to a single domain's tables.
#' @param info Info tibble (must have concept_id, n_patients_total, n_records_total).
#' @param prevalence Prevalence tibble (must have concept_id, patient_count).
#' @param chapters Chapters tibble (can be NULL).
#' @param attributes Attributes tibble (can be NULL).
#' @param domain_label Short label for messages.
#' @param k Minimum cell count.
#' @return Named list: prevalence, info, chapters, attributes, rare.
#' @keywords internal
suppress_domain <- function(info, prevalence, chapters, attributes,
                            domain_label = "concept", k = K_ANONYMITY) {
  too_rare_ids <- info |> dplyr::filter(.data$n_patients_total < k) |> dplyr::pull("concept_id")
  n_dropped_total <- length(too_rare_ids)

  info       <- info       |> dplyr::filter(!.data$concept_id %in% too_rare_ids)
  prevalence <- prevalence |> dplyr::filter(!.data$concept_id %in% too_rare_ids)
  if (!is.null(chapters))   chapters   <- chapters   |> dplyr::filter(!.data$concept_id %in% too_rare_ids)
  if (!is.null(attributes)) attributes <- attributes |> dplyr::filter(!.data$concept_id %in% too_rare_ids)

  concepts_before <- unique(prevalence$concept_id)
  n_prev_rows_before <- nrow(prevalence)

  prevalence <- prevalence |> dplyr::filter(.data$patient_count >= k)
  n_prev_rows_after <- nrow(prevalence)

  concepts_after <- unique(prevalence$concept_id)
  fully_suppressed_ids <- setdiff(concepts_before, concepts_after)

  rare <- info |>
    dplyr::filter(.data$concept_id %in% fully_suppressed_ids, .data$n_patients_total >= k) |>
    dplyr::select("concept_id", n_patients = "n_patients_total", n_records = "n_records_total")

  surviving_ids <- union(concepts_after, rare$concept_id)
  info       <- info       |> dplyr::filter(.data$concept_id %in% surviving_ids)
  if (!is.null(chapters))   chapters   <- chapters   |> dplyr::filter(.data$concept_id %in% surviving_ids)
  if (!is.null(attributes)) attributes <- attributes |> dplyr::filter(.data$concept_id %in% surviving_ids)

  cli::cli_alert_info(
    "{domain_label}: {n_dropped_total} dropped (total < k), {n_prev_rows_before - n_prev_rows_after} prevalence rows suppressed, {nrow(rare)} rare."
  )

  list(prevalence = prevalence, info = info, chapters = chapters,
       attributes = attributes, rare = rare)
}

# Rows whose count is below k are left out
.drop_small_cells <- function(x, count_col, label, k) {
  if (is.null(x)) return(NULL)
  kept <- x[x[[count_col]] >= k, , drop = FALSE]
  n_dropped <- nrow(x) - nrow(kept)
  if (n_dropped > 0) cli::cli_alert_info("{label}: {n_dropped} row{?s} with fewer than {k} persons suppressed.")
  kept
}

#' Apply k-anonymity suppression to all extracted source tables.
#'
#' Rows with fewer than \code{k} persons are left out: concepts and prevalence
#' strata, death counts, demographics and denominator cells.
#' @param tables Named list of tibbles (before k-anonymity).
#' @param k Minimum cell count (default K_ANONYMITY = 5).
#' @return Named list of tibbles with k-anonymity applied.
#' @keywords internal
apply_k_anonymity <- function(tables, k = K_ANONYMITY) {
  cli::cli_alert_info("k-anonymity (k={k}):")
  result <- list()

  if (!is.null(tables$condition_info)) {
    cond <- suppress_domain(
      tables$condition_info, tables$condition_prevalence,
      tables$condition_chapters, tables$condition_attributes, "conditions", k
    )
    result$condition_prevalence <- cond$prevalence
    result$condition_info       <- cond$info
    result$condition_chapters   <- cond$chapters
    result$condition_attributes <- cond$attributes
    result$condition_rare       <- cond$rare
  }

  if (!is.null(tables$procedure_info)) {
    proc <- suppress_domain(
      tables$procedure_info, tables$procedure_prevalence,
      tables$procedure_chapters, tables$procedure_attributes, "procedures", k
    )
    result$procedure_prevalence <- proc$prevalence
    result$procedure_info       <- proc$info
    result$procedure_chapters   <- proc$chapters
    result$procedure_attributes <- proc$attributes
    result$procedure_rare       <- proc$rare
  }

  if (!is.null(tables$drug_info)) {
    drug <- suppress_domain(
      tables$drug_info, tables$drug_prevalence,
      tables$drug_chapters, tables$drug_attributes, "drugs", k
    )
    result$drug_prevalence <- drug$prevalence
    result$drug_info       <- drug$info
    result$drug_chapters   <- drug$chapters
    result$drug_attributes <- drug$attributes
    result$drug_rare       <- drug$rare
  }

  result$demographics <- .drop_small_cells(tables$demographics, "patient_count", "demographics", k)

  deaths <- tables$death_counts
  n_death_before <- nrow(deaths)
  deaths <- deaths |> dplyr::filter(.data$death_count >= k)
  if (n_death_before - nrow(deaths) > 0) {
    cli::cli_alert_info("deaths: {n_death_before - nrow(deaths)} rows suppressed.")
  }
  result$death_counts <- deaths
  if (!is.null(tables$denominator)) {
    result$denominator <- .drop_small_cells(tables$denominator, "denominator", "denominator", k)
  }

  result
}

# ── Save / load helpers ─────────────────────────────────────────────────────

# Read one saved CSV. readr::read_csv is ~5-10x faster than utils::read.csv on
# these files. Numeric columns come back as double, fine for dplyr joins.
# `sex` is always text: a column with only "F" would otherwise be read as FALSE.
.read_syrona_csv <- function(file) {
  header <- names(readr::read_csv(file, n_max = 0, show_col_types = FALSE, progress = FALSE))
  types <- if ("sex" %in% header) {
    readr::cols(sex = readr::col_character(), .default = readr::col_guess())
  } else {
    readr::cols(.default = readr::col_guess())
  }
  readr::read_csv(file, col_types = types, progress = FALSE)
}

# Folder of a saved dataset
.dataset_dir <- function(dataset_name) {
  file.path(getOption("syrona.data_dir", "."), SOURCES_DIR, dataset_name)
}

# Every file save_dataset() can write. Only these are ever removed.
.dataset_files <- function() {
  domain_tables <- c("prevalence", "info", "chapters", "attributes", "rare")
  paste0(c("_metadata", "demographics", "death_counts", "denominator",
           paste0(rep(c("condition", "procedure", "drug"), each = length(domain_tables)),
                  "_", domain_tables)), ".csv")
}

# Syrona's files already in a dataset folder
.existing_dataset_files <- function(dataset_name) {
  intersect(list.files(.dataset_dir(dataset_name)), .dataset_files())
}

#' Save extracted tables to CSV.
#' @param tables Named list of tibbles.
#' @param dataset_name Short label for the dataset.
#' @param db_path Database path (stored in metadata).
#' @param care_site_id The care site used, or \code{NULL} (stored in metadata when used).
#' @param overwrite If \code{TRUE}, Syrona's files already in the folder are
#'   removed first. Other files in the folder are kept.
#' @param cohort The cohort used, as a named list (\code{cohort_id}, \code{cohort_schema},
#'   \code{cohort_table}, \code{cohort_entries}, \code{cohort_persons}), or \code{NULL}.
#'   Stored in metadata when used.
#' @keywords internal
save_dataset <- function(tables, dataset_name, db_path = NA_character_,
                         care_site_id = NULL, cohort = NULL, overwrite = FALSE) {
  out_dir <- .dataset_dir(dataset_name)
  existing <- .existing_dataset_files(dataset_name)
  if (length(existing) > 0) {
    if (!overwrite) {
      cli::cli_abort("Dataset {.val {dataset_name}} already exists at {.path {out_dir}}.")
    }
    unlink(file.path(out_dir, existing))
  }
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  nrow_or <- function(name) if (!is.null(tables[[name]])) nrow(tables[[name]]) else 0L

  metadata <- tibble::tibble(
    dataset_name = dataset_name,
    db_path      = db_path,
    extracted_at = format(Sys.time(), "%Y-%m-%d %H:%M:%S"),
    n_conditions = nrow_or("condition_info"),
    n_condition_prevalence_rows = nrow_or("condition_prevalence"),
    n_rare_conditions = nrow_or("condition_rare"),
    n_procedures = nrow_or("procedure_info"),
    n_procedure_prevalence_rows = nrow_or("procedure_prevalence"),
    n_drugs = nrow_or("drug_info"),
    n_drug_prevalence_rows = nrow_or("drug_prevalence"),
    age_clamp_max = AGE_CLAMP_MAX,
    k_anonymity = K_ANONYMITY
  )
  if (!is.null(care_site_id)) metadata$care_site_id <- care_site_id
  for (nm in names(cohort)) metadata[[nm]] <- cohort[[nm]]
  # Cohort counts below k are written as "<k"
  for (nm in intersect(c("cohort_entries", "cohort_persons"), names(metadata))) {
    if (metadata[[nm]] < K_ANONYMITY) metadata[[nm]] <- paste0("<", K_ANONYMITY)
  }
  utils::write.csv(metadata, file.path(out_dir, "_metadata.csv"), row.names = FALSE)

  for (name in names(tables)) {
    utils::write.csv(tables[[name]], file.path(out_dir, paste0(name, ".csv")), row.names = FALSE)
  }

  cli::cli_alert_success("Saved {length(tables)} tables to {.path {out_dir}}/")
  invisible(out_dir)
}

#' Load a previously saved dataset from CSV.
#' @param dataset_name Short label (subfolder name under data/sources/).
#' @return Named list of tibbles.
#' @examples
#' \donttest{
#' base <- tempdir()
#' file.copy(system.file("extdata", "demo", package = "syrona"), base, recursive = TRUE)
#' old <- options(syrona.data_dir = file.path(base, "demo"))
#' d <- load_dataset("demo_population")
#' names(d)
#' options(old)
#' }
#' @export
load_dataset <- function(dataset_name) {
  base <- getOption("syrona.data_dir", ".")
  in_dir <- file.path(base, SOURCES_DIR, dataset_name)
  if (!dir.exists(in_dir)) {
    cli::cli_abort("Dataset {.val {dataset_name}} not found at {.path {in_dir}}")
  }

  col_types <- list(
    condition_prevalence = c(concept_id = "integer", year = "integer",
      sex = "character", age_group = "character", patient_count = "integer",
      record_count = "integer", denominator = "integer", prevalence = "numeric"),
    condition_attributes = c(concept_id = "integer", relationship = "character",
      target_concept_id = "integer", target_concept_name = "character"),
    condition_rare = c(concept_id = "integer", n_patients = "integer", n_records = "integer"),
    procedure_prevalence = c(concept_id = "integer", year = "integer",
      sex = "character", age_group = "character", patient_count = "integer",
      record_count = "integer", denominator = "integer", prevalence = "numeric"),
    procedure_attributes = c(concept_id = "integer", relationship = "character",
      target_concept_id = "integer", target_concept_name = "character"),
    procedure_rare = c(concept_id = "integer", n_patients = "integer", n_records = "integer"),
    drug_prevalence = c(concept_id = "integer", year = "integer",
      sex = "character", age_group = "character", patient_count = "integer",
      record_count = "integer", denominator = "integer", prevalence = "numeric"),
    drug_attributes = c(concept_id = "integer", relationship = "character",
      target_concept_id = "integer", target_concept_name = "character"),
    drug_rare = c(concept_id = "integer", n_patients = "integer", n_records = "integer"),
    condition_chapters = c(concept_id = "integer", chapter_type = "character",
      chapter_id = "integer", chapter_name = "character",
      chapter_level = "integer", parent_chapter_id = "integer"),
    procedure_chapters = c(concept_id = "integer", chapter_type = "character",
      chapter_id = "integer", chapter_name = "character",
      chapter_level = "integer", parent_chapter_id = "integer"),
    drug_chapters = c(concept_id = "integer", chapter_type = "character",
      chapter_id = "integer", chapter_name = "character",
      chapter_level = "integer", parent_chapter_id = "integer"),
    death_counts = c(year = "integer", sex = "character",
      age_group = "character", death_count = "integer",
      denominator = "integer", mortality_rate = "numeric")
  )

  csv_files <- list.files(in_dir, pattern = "\\.csv$", full.names = TRUE)
  csv_files <- csv_files[!grepl("^_", basename(csv_files))]

  tables <- list()
  for (f in csv_files) {
    name <- tools::file_path_sans_ext(basename(f))
    tbl <- .read_syrona_csv(f)
    if (nrow(tbl) == 0 && name %in% names(col_types)) {
      for (col in names(col_types[[name]])) {
        if (col %in% names(tbl)) {
          storage.mode(tbl[[col]]) <- col_types[[name]][[col]]
        }
      }
    }
    tables[[name]] <- tbl
  }

  cli::cli_alert_success("Loaded {length(tables)} tables from {.path {in_dir}}/")
  tables
}

#' List all available datasets.
#' @return Character vector of dataset names.
#' @export
list_datasets <- function() {
  base <- getOption("syrona.data_dir", ".")
  src <- file.path(base, SOURCES_DIR)
  if (!dir.exists(src)) return(character(0))
  dirs <- list.dirs(src, full.names = FALSE, recursive = FALSE)
  dirs[dirs != ""]
}

# ── Master extraction function ──────────────────────────────────────────────

#' Run the full source data extraction pipeline.
#'
#' Derives stratified prevalence tables from the records in an OMOP CDM database
#' for one or more clinical domains. Applies k-anonymity suppression and
#' optionally saves results to CSV.
#'
#' @param dataset_name Short label for the dataset (e.g. "EH30", "EstBB").
#' @param db Either a DuckDB file path (string) or an existing connection
#'   list from \code{syrona_connect} / \code{syrona_connect_pg}.
#' @param domains Character vector of domains to extract.
#'   Options: \code{"conditions"}, \code{"procedures"}, \code{"drugs"}.
#' @param cohort_id Integer \code{cohort_definition_id} to filter by.
#'   If \code{NULL} (default), extracts the full dataset.
#' @param cohort_schema Schema containing the cohort table. With
#'   \code{cohort_schema} only, the table \code{cohort} in that schema is read
#'   (where ATLAS writes its cohorts).
#' @param save If \code{TRUE} (default), saves CSV to \code{data/sources/<dataset_name>/}
#'   under \code{getOption("syrona.data_dir")} (default: the working directory).
#'   The folders are created if needed.
#' @param care_site_id One \code{care_site_id} (a hospital or clinic). If given,
#'   the dataset covers the persons with at least one visit at that care site,
#'   over their whole observation period, and only the events recorded at a
#'   visit there (linked through \code{visit_occurrence_id}). Events with no
#'   visit link are left out. Cannot be combined with \code{cohort_id}.
#'   \code{\link{list_care_sites}} lists the care sites.
#' @param cohort_table Name of the cohort table. With \code{cohort_schema} the
#'   table in that schema, without it a cohort in the cdm reference (for example
#'   one generated with \code{CDMConnector::generateCohortSet()}). See
#'   \code{\link{apply_cohort_filter}}.
#' @param overwrite If a dataset with this name was saved before: \code{FALSE}
#'   (default) stops before anything is extracted, \code{TRUE} replaces it.
#'   Only the files Syrona writes are removed, other files in the folder are
#'   kept.
#' @return Named list of tibbles matching the Syrona schema (invisible).
#' @export
extract_all <- function(dataset_name, db,
                        domains = c("conditions", "procedures", "drugs"),
                        cohort_id = NULL, cohort_schema = NULL,
                        save = TRUE, care_site_id = NULL, cohort_table = NULL,
                        overwrite = FALSE) {
  stopifnot(
    is.character(dataset_name), length(dataset_name) == 1, nchar(dataset_name) > 0,
    !grepl("[/\\\\]", dataset_name)
  )
  domains <- match.arg(domains, c("conditions", "procedures", "drugs"), several.ok = TRUE)

  if (!is.null(care_site_id)) {
    if (!is.numeric(care_site_id) || length(care_site_id) != 1 ||
        is.na(care_site_id) || care_site_id != round(care_site_id)) {
      cli::cli_abort(c(
        "{.arg care_site_id} must be one whole number.",
        "i" = "Extract one care site per call, for example {.code care_site_id = 101}."
      ))
    }
    if (!is.null(cohort_id)) {
      cli::cli_abort(c(
        "Use either {.arg cohort_id} or {.arg care_site_id}, not both.",
        "i" = "{.arg cohort_id} filters to a cohort, {.arg care_site_id} to the visits at one care site."
      ))
    }
  }

  if (!is.null(cohort_id) && is.null(cohort_schema) && is.null(cohort_table)) {
    cli::cli_abort(c(
      "Name where the cohort is: {.arg cohort_schema}, {.arg cohort_table} or both.",
      "i" = "A cohort generated in ATLAS: {.code cohort_schema = \"results\"} (reads {.val results.cohort}).",
      "i" = "A cohort in the cdm reference: {.code cohort_table = \"my_cohort\"}."
    ))
  }
  if (is.null(cohort_id) && (!is.null(cohort_schema) || !is.null(cohort_table))) {
    cli::cli_abort(c(
      "{.arg cohort_schema} and {.arg cohort_table} need a {.arg cohort_id}.",
      "i" = "For example {.code extract_all(\"My_cohort\", db, cohort_id = 2031, cohort_schema = \"results\")}."
    ))
  }

  if (save && !isTRUE(overwrite) && length(.existing_dataset_files(dataset_name)) > 0) {
    cli::cli_abort(c(
      "Dataset {.val {dataset_name}} already exists at {.path {(.dataset_dir(dataset_name))}}.",
      "i" = "Use another {.arg dataset_name}, or add {.code overwrite = TRUE} to replace it."
    ))
  }

  own_connection <- FALSE
  if (is.character(db)) {
    db_path <- db
    db <- syrona_connect(db_path)
    own_connection <- TRUE
  } else {
    db_path <- NA_character_
  }
  if (own_connection) on.exit(syrona_disconnect(db))

  if (!is.null(care_site_id)) {
    db <- apply_care_site_filter(db, care_site_id, domains)
  }

  if (!is.null(cohort_id)) {
    cli::cli_alert_info("Applying cohort filter (cohort_id = {cohort_id})...")
    db <- .apply_cohort_filter(db, cohort_id, cohort_schema, cohort_table, call = rlang::current_env())
  }

  cdm <- db$cdm

  cli::cli_h2("Extracting dataset: {dataset_name} [{paste(domains, collapse = ', ')}]")

  cli::cli_alert("Extracting denominators (ACHILLES-116)...")
  denom_df <- extract_denominators(cdm)

  cli::cli_alert("Extracting demographics...")
  demographics_df <- extract_demographics(cdm)

  cli::cli_alert("Extracting death counts (ACHILLES-504)...")
  death_df <- extract_death_counts(cdm, denom_df)

  tables_raw <- list(demographics = demographics_df, death_counts = death_df)

  if ("conditions" %in% domains) {
    cli::cli_alert("Extracting condition prevalence (ACHILLES-404)...")
    tables_raw$condition_prevalence <- extract_condition_prevalence(cdm, denom_df)
    cli::cli_alert("Extracting condition info...")
    tables_raw$condition_info <- extract_condition_info(cdm)
    condition_ids <- tables_raw$condition_info$concept_id
    cli::cli_alert("Extracting condition chapters...")
    tables_raw$condition_chapters <- extract_condition_chapters(cdm, condition_ids)
    cli::cli_alert("Extracting condition attributes...")
    tables_raw$condition_attributes <- extract_condition_attributes(cdm, condition_ids)
  }

  if ("procedures" %in% domains) {
    cli::cli_alert("Extracting procedure prevalence...")
    tables_raw$procedure_prevalence <- extract_procedure_prevalence(cdm, denom_df)
    cli::cli_alert("Extracting procedure info...")
    tables_raw$procedure_info <- extract_procedure_info(cdm)
    procedure_ids <- tables_raw$procedure_info$concept_id
    cli::cli_alert("Extracting procedure chapters...")
    tables_raw$procedure_chapters <- extract_procedure_chapters(cdm, procedure_ids)
    cli::cli_alert("Extracting procedure attributes...")
    tables_raw$procedure_attributes <- extract_procedure_attributes(cdm, procedure_ids)
  }

  if ("drugs" %in% domains) {
    cli::cli_alert("Extracting drug prevalence (ingredient level)...")
    tables_raw$drug_prevalence <- extract_drug_prevalence(cdm, denom_df)
    cli::cli_alert("Extracting drug info...")
    tables_raw$drug_info <- extract_drug_info(cdm)
    drug_ids <- tables_raw$drug_info$concept_id
    cli::cli_alert("Extracting drug chapters (ATC 1st level)...")
    tables_raw$drug_chapters <- extract_drug_chapters(cdm, drug_ids)
    tables_raw$drug_attributes <- tibble::tibble(
      concept_id = integer(), relationship = character(),
      target_concept_id = integer(), target_concept_name = character()
    )
  }

  cli::cli_alert("Applying k-anonymity suppression...")
  tables_raw$denominator <- denom_df
  tables <- apply_k_anonymity(tables_raw)

  if (save) {
    save_dataset(tables, dataset_name, db_path, care_site_id, attr(db, "cohort_used"),
                 overwrite = isTRUE(overwrite))
  }

  msgs <- sprintf("Dataset '%s':", dataset_name)
  if (!is.null(tables$condition_info))
    msgs <- c(msgs, sprintf("  conditions: %d (%d rare), %d prevalence rows",
              nrow(tables$condition_info), nrow(tables$condition_rare),
              nrow(tables$condition_prevalence)))
  if (!is.null(tables$procedure_info))
    msgs <- c(msgs, sprintf("  procedures: %d (%d rare), %d prevalence rows",
              nrow(tables$procedure_info), nrow(tables$procedure_rare),
              nrow(tables$procedure_prevalence)))
  if (!is.null(tables$drug_info))
    msgs <- c(msgs, sprintf("  drugs: %d (%d rare), %d prevalence rows",
              nrow(tables$drug_info), nrow(tables$drug_rare),
              nrow(tables$drug_prevalence)))
  cli::cli_alert_success(paste(c("Done.", msgs), collapse = "\n"))
  labels <- c(conditions = "condition", procedures = "procedure", drugs = "drug")
  for (d in attr(db, "empty_domains")) {
    cli::cli_alert_warning("No {labels[[d]]} events are linked to visits at care site {care_site_id}.")
  }
  invisible(tables)
}
