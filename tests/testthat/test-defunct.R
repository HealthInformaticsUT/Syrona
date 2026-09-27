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
