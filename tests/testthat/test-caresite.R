# extract_all(care_site_id = ): persons with at least one visit at the care
# site, and only their events linked (visit_occurrence_id) to a visit at that
# care site, over their whole observation period.

event_tables <- c("condition_occurrence", "procedure_occurrence", "drug_exposure")

test_that("the care-site filter keeps exactly the events recorded at that care site", {
  db <- get_test_db(prepare = add_visit_link_fixture)
  on.exit(cleanup_test_db(db))
  mixed <- fixture_mixed_person(db$con)
  events_at <- function(site) DBI::dbGetQuery(db$con, sprintf(
    "SELECT count(*) AS n FROM condition_occurrence c JOIN visit_occurrence v USING (visit_occurrence_id)
      WHERE c.person_id = %d AND v.care_site_id = %d", mixed, site))$n

  for (site in c(101, 102)) {
    filtered <- suppressMessages(apply_care_site_filter(db, site, domains = "conditions"))

    kept <- filtered$cdm$condition_occurrence |>
      dplyr::filter(.data$person_id == !!mixed) |> dplyr::tally() |> dplyr::pull(n)
    expect_equal(as.numeric(kept), as.numeric(events_at(site)))

    for (t in event_tables) {
      elsewhere <- filtered$cdm[[t]] |>
        dplyr::left_join(db$cdm$visit_occurrence |> dplyr::select("visit_occurrence_id", "care_site_id"),
                         by = "visit_occurrence_id") |>
        dplyr::filter(is.na(.data$care_site_id) | .data$care_site_id != !!site) |>
        dplyr::tally() |> dplyr::pull(n)
      expect_equal(as.numeric(elsewhere), 0, label = paste(t, "events not recorded at care site", site))
    }
  }
})

test_that("extract_all(care_site_id = ) equals the published care-site method applied by hand", {
  db <- get_test_db(prepare = add_visit_link_fixture)
  on.exit(cleanup_test_db(db))

  built_in <- suppressMessages(extract_all("Site_101", db, care_site_id = 101, save = FALSE))

  site_visits <- db$cdm$visit_occurrence |>
    dplyr::filter(.data$care_site_id == 101) |>
    dplyr::select("visit_occurrence_id", "person_id")
  by_hand <- db
  for (t in c("person", "observation_period", "death")) {
    by_hand$cdm[[t]] <- by_hand$cdm[[t]] |>
      dplyr::semi_join(site_visits |> dplyr::distinct(.data$person_id), by = "person_id")
  }
  for (t in event_tables) {
    by_hand$cdm[[t]] <- by_hand$cdm[[t]] |>
      dplyr::semi_join(site_visits |> dplyr::select("visit_occurrence_id"), by = "visit_occurrence_id")
  }
  reference <- suppressMessages(extract_all("Site_101", by_hand, save = FALSE))

  expect_identical(table_fingerprints(built_in), table_fingerprints(reference))
  expect_gt(nrow(built_in$condition_prevalence), 0)
})

test_that("extract_all(care_site_id = ) writes nothing to the database", {
  db <- get_test_db(prepare = add_visit_link_fixture)
  on.exit(cleanup_test_db(db))
  before <- snapshot_schema(db$con, "main")

  suppressMessages(extract_all("Site_101", db, care_site_id = 101, save = FALSE))

  expect_identical(snapshot_schema(db$con, "main"), before)
})

test_that("a domain with no events linked to the care site gives empty tables and a note", {
  db <- get_test_db(prepare = add_visit_link_fixture)
  on.exit(cleanup_test_db(db))

  msgs <- capture_messages(
    tables <- extract_all("Site_102", db, care_site_id = 102, domains = "drugs", save = FALSE)
  )
  expect_equal(nrow(tables$drug_prevalence), 0)
  # The note is shown when the filter runs and again as the last line of the summary
  expect_equal(sum(grepl("No drug events are linked", msgs)), 2)
  expect_match(msgs[length(msgs)], "No drug events are linked")
})

test_that("care_site_id is checked before anything is read", {
  # A path that does not exist: an error about the argument proves nothing was opened
  for (bad in list(c(101, 102), "101", 1.5, NA_real_)) {
    expect_error(extract_all("X", db = "no_such_file.duckdb", care_site_id = bad), "must be one whole number")
  }
  expect_error(
    extract_all("X", db = "no_such_file.duckdb", cohort_id = 1, cohort_schema = "results", care_site_id = 101),
    "either"
  )
})

test_that("an unknown care site stops with a clear message", {
  db <- get_test_db(prepare = add_visit_link_fixture)
  on.exit(cleanup_test_db(db))
  err <- expect_error(suppressMessages(extract_all("X", db, care_site_id = 999, save = FALSE)),
                      "Care site 999 has no visits")
  expect_identical(as.character(err$call[[1]]), "extract_all")
  expect_match(conditionMessage(err), "list_care_sites(db$con", fixed = TRUE)
})

test_that("care_site_id is recorded in _metadata.csv only when it is used", {
  db <- get_test_db(prepare = add_visit_link_fixture)
  on.exit(cleanup_test_db(db))
  base <- file.path(tempdir(), "caresite_meta")
  old <- options(syrona.data_dir = base)
  on.exit({ options(old); unlink(base, recursive = TRUE) }, add = TRUE)

  suppressMessages(extract_all("With_site", db, care_site_id = 101, domains = "conditions"))
  suppressMessages(extract_all("Without_site", db, domains = "conditions"))

  with_site <- utils::read.csv(file.path(base, "data", "sources", "With_site", "_metadata.csv"))
  without_site <- utils::read.csv(file.path(base, "data", "sources", "Without_site", "_metadata.csv"))
  expect_equal(with_site$care_site_id, 101)
  expect_false("care_site_id" %in% names(without_site))
})

test_that("a care-site extraction does not change the db object", {
  db <- get_test_db(prepare = add_visit_link_fixture)
  on.exit(cleanup_test_db(db))

  suppressMessages(extract_all("Site_101", db, care_site_id = 101, save = FALSE))
  tables <- suppressMessages(extract_all("Everyone", db, save = FALSE))

  expect_known_gibleed(tables)
})
