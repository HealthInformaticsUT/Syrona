test_that("extract_all runs on GiBleed and produces expected tables", {
  db <- get_test_db()
  on.exit(cleanup_test_db(db))

  # Run extraction for conditions only (GiBleed has conditions + drugs)
  tables <- extract_all(
    dataset_name = "GiBleed_test",
    db = db,
    domains = "conditions",
    save = FALSE
  )

  # Should have shared tables
  expect_true("demographics" %in% names(tables))
  expect_true("death_counts" %in% names(tables))
  expect_true("denominator" %in% names(tables))

  # Should have condition tables
  expect_true("condition_prevalence" %in% names(tables))
  expect_true("condition_info" %in% names(tables))
  expect_true("condition_chapters" %in% names(tables))
  expect_true("condition_attributes" %in% names(tables))

  # Should NOT have procedure/drug tables
  expect_null(tables$procedure_info)
  expect_null(tables$drug_info)

  # Demographics should have the right columns
  expect_true(all(c("sex", "birth_year", "patient_count") %in% names(tables$demographics)))

  # Condition prevalence should have correct columns
  prev_cols <- c("concept_id", "year", "sex", "age_group",
                 "patient_count", "record_count", "denominator", "prevalence")
  expect_true(all(prev_cols %in% names(tables$condition_prevalence)))

  # Condition info should have correct columns
  info_cols <- c("concept_id", "concept_name", "concept_code",
                 "vocabulary_id", "n_patients_total")
  expect_true(all(info_cols %in% names(tables$condition_info)))

  # Prevalence values should be between 0 and 1
  expect_true(all(tables$condition_prevalence$prevalence > 0, na.rm = TRUE))
  expect_true(all(tables$condition_prevalence$prevalence <= 1, na.rm = TRUE))

  # Known answers: row counts of every returned table (helper-setup.R)
  expect_known_gibleed(tables)
})

test_that("extract_all runs drugs domain on GiBleed", {
  db <- get_test_db()
  on.exit(cleanup_test_db(db))

  tables <- extract_all(
    dataset_name = "GiBleed_drugs",
    db = db,
    domains = "drugs",
    save = FALSE
  )

  expect_true("drug_prevalence" %in% names(tables))
  expect_true("drug_info" %in% names(tables))
  expect_true("drug_chapters" %in% names(tables))

  # Drug info should have ingredient-level concepts
  expect_true(all(tables$drug_info$concept_class_id == "Ingredient"))

  # Known answers: row counts of every returned table (helper-setup.R)
  expect_known_gibleed(tables)
})

test_that("extract_all gives the known answers on PostgreSQL and writes nothing", {
  db <- get_test_pg("reader")
  on.exit(syrona_disconnect(db))
  s <- pg_settings("reader")

  cdm_before <- snapshot_schema(db$con, s$cdm_schema)
  results_before <- snapshot_schema(db$con, s$write_schema)

  tables <- extract_all(
    dataset_name = "GiBleed_pg",
    db = db,
    save = FALSE
  )

  # Same known answers as on DuckDB, all three domains
  expect_known_gibleed(tables)

  # Read-only: no table added or changed in the CDM or the write schema
  expect_identical(snapshot_schema(db$con, s$cdm_schema), cdm_before)
  expect_identical(snapshot_schema(db$con, s$write_schema), results_before)
})

test_that("extract_denominators produces valid output", {
  db <- get_test_db()
  on.exit(cleanup_test_db(db))

  denom <- extract_denominators(db$cdm)

  expect_true(all(c("year", "sex", "age_group", "denominator") %in% names(denom)))
  expect_gt(nrow(denom), 0)
  expect_true(all(denom$sex %in% c("F", "M")))
  expect_true(all(denom$denominator > 0))
})
