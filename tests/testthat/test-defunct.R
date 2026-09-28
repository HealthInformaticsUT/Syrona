# Removed functions stop with a message that explains how the task works now

test_that("insert_cohort() is defunct and points to reading an existing cohort", {
  err <- expect_error(insert_cohort(), class = "rlang_error")
  msg <- conditionMessage(err)
  expect_match(msg, "removed in syrona 0.3.0")
  expect_match(msg, "extract_all")
  expect_match(msg, "cohort_schema")
  expect_match(msg, "cohort_table")
  # Old 0.2.1 calls with arguments hit the same message, nothing is written
  expect_error(insert_cohort(NULL, data.frame(), name = "person"), "removed in syrona 0.3.0")
})

test_that("create_caresite_cohort() is defunct and points to extract_all(care_site_id = )", {
  err <- expect_error(create_caresite_cohort(), class = "rlang_error")
  msg <- conditionMessage(err)
  expect_match(msg, "removed in syrona 0.3.0")
  expect_match(msg, "care_site_id")
  expect_match(msg, "list_care_sites")
  expect_error(create_caresite_cohort(NULL, care_site_id = 101, cohort_id = 1, cdm_schema = "main"),
               "removed in syrona 0.3.0")
})

test_that("delete_cohort() is defunct and says there is nothing of Syrona's to delete", {
  err <- expect_error(delete_cohort(), class = "rlang_error")
  msg <- conditionMessage(err)
  expect_match(msg, "removed in syrona 0.3.0")
  expect_match(msg, "creates no cohort tables")
  expect_match(msg, "care_site_id")
  expect_error(delete_cohort(NULL, cohort_id = 1, cohort_schema = "results"), "removed in syrona 0.3.0")
})
