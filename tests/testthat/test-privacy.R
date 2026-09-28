# Outputs are safe to share: no saved count below k = 5, in any file.

COUNT_COLUMNS <- c("patient_count", "record_count", "denominator", "death_count",
                   "n_patients_total", "n_records_total", "n_patients", "n_records",
                   "cohort_entries", "cohort_persons")

small_cells <- function(dir) {
  out <- character(0)
  for (f in list.files(dir, pattern = "\\.csv$", full.names = TRUE)) {
    x <- utils::read.csv(f)
    for (col in intersect(COUNT_COLUMNS, names(x))) {
      v <- suppressWarnings(as.numeric(x[[col]]))
      n <- sum(!is.na(v) & v > 0 & v < 5)
      if (n > 0) out <- c(out, sprintf("%s$%s: %d", basename(f), col, n))
    }
  }
  out
}

test_that("a saved GiBleed extraction has no count below 5 in any file", {
  db <- get_test_db()
  base <- file.path(tempdir(), paste0("privacy_", basename(tempfile(""))))
  old <- options(syrona.data_dir = base)
  on.exit({ cleanup_test_db(db); options(old); unlink(base, recursive = TRUE) })

  suppressMessages(extract_all("GiBleed_saved", db))

  expect_identical(small_cells(file.path(base, "data", "sources", "GiBleed_saved")), character(0))
})

test_that("a saved Synthea extraction (PostgreSQL) has no count below 5 in any file", {
  synthea <- Sys.getenv("SYRONA_TEST_PG_SYNTHEA_SCHEMA")
  if (!nzchar(synthea)) skip("SYRONA_TEST_PG_SYNTHEA_SCHEMA not set in ~/.Renviron.")
  db <- get_test_pg("reader", cdm_schema = synthea)
  base <- file.path(tempdir(), paste0("privacy_", basename(tempfile(""))))
  old <- options(syrona.data_dir = base)
  on.exit({ syrona_disconnect(db); options(old); unlink(base, recursive = TRUE) })

  suppressMessages(extract_all("Synthea_saved", db))

  expect_identical(small_cells(file.path(base, "data", "sources", "Synthea_saved")), character(0))
})

test_that("a cohort with fewer than 5 persons is recorded as <5 in _metadata.csv", {
  db <- get_test_db(prepare = function(con) {
    DBI::dbExecute(con, "CREATE SCHEMA results")
    DBI::dbExecute(con, "CREATE TABLE results.cohort AS
                          SELECT 1 AS cohort_definition_id, person_id AS subject_id,
                                 DATE '1900-01-01' AS cohort_start_date, DATE '2100-12-31' AS cohort_end_date
                          FROM person ORDER BY person_id LIMIT 3")
  })
  base <- file.path(tempdir(), paste0("privacy_", basename(tempfile(""))))
  old <- options(syrona.data_dir = base)
  on.exit({ cleanup_test_db(db); options(old); unlink(base, recursive = TRUE) })

  suppressMessages(extract_all("Tiny", db, domains = "conditions", cohort_id = 1, cohort_schema = "results"))

  meta <- utils::read.csv(file.path(base, "data", "sources", "Tiny", "_metadata.csv"))
  expect_equal(meta$cohort_entries, "<5")
  expect_equal(meta$cohort_persons, "<5")
})
