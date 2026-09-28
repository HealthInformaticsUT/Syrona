# Saving a dataset: an existing dataset folder is only replaced when asked,
# and only the files Syrona writes are removed.

new_data_dir <- function() file.path(tempdir(), paste0("save_", basename(tempfile(""))))

dataset_files <- function(base, name) sort(list.files(file.path(base, "data", "sources", name)))

test_that("extracting into an existing dataset stops before any work, and changes nothing", {
  db <- get_test_db()
  base <- new_data_dir()
  old <- options(syrona.data_dir = base)
  on.exit({ cleanup_test_db(db); options(old); unlink(base, recursive = TRUE) })
  suppressMessages(extract_all("Site", db, domains = "conditions"))
  md5_before <- tools::md5sum(list.files(file.path(base, "data", "sources", "Site"), full.names = TRUE))

  msgs <- character(0)
  expect_error(
    withCallingHandlers(extract_all("Site", db, domains = "conditions"),
                        message = function(m) { msgs <<- c(msgs, conditionMessage(m)); invokeRestart("muffleMessage") }),
    "overwrite = TRUE"
  )
  expect_false(any(grepl("Extracting", msgs)))
  expect_identical(tools::md5sum(names(md5_before)), md5_before)
})

test_that("overwrite = TRUE replaces Syrona's files only: no old domain files, user files kept", {
  db <- get_test_db()
  base <- new_data_dir()
  old <- options(syrona.data_dir = base)
  on.exit({ cleanup_test_db(db); options(old); unlink(base, recursive = TRUE) })
  suppressMessages(extract_all("Site", db, domains = c("conditions", "drugs")))
  writeLines("my notes", file.path(base, "data", "sources", "Site", "notes.txt"))

  suppressMessages(extract_all("Site", db, domains = "conditions", overwrite = TRUE))

  files <- dataset_files(base, "Site")
  expect_false(any(grepl("^drug_", files)))
  expect_true("condition_prevalence.csv" %in% files)
  expect_true("notes.txt" %in% files)
  expect_null(suppressMessages(load_dataset("Site"))$drug_prevalence)
})

test_that("save = FALSE needs no overwrite, and a new name is saved as before", {
  db <- get_test_db()
  base <- new_data_dir()
  old <- options(syrona.data_dir = base)
  on.exit({ cleanup_test_db(db); options(old); unlink(base, recursive = TRUE) })
  suppressMessages(extract_all("Site", db, domains = "conditions"))

  expect_no_error(suppressMessages(extract_all("Site", db, domains = "conditions", save = FALSE)))
  suppressMessages(extract_all("Other_site", db, domains = "conditions"))
  expect_true("condition_prevalence.csv" %in% dataset_files(base, "Other_site"))
})

# Comparisons: the demo datasets shipped with the package, no database needed
demo_data_dir <- function() {
  base <- new_data_dir()
  dir.create(base, recursive = TRUE)
  file.copy(system.file("extdata", "demo", "data", package = "syrona"), base, recursive = TRUE)
  base
}
comparison_files <- function(base) sort(list.files(file.path(base, "data", "comparisons",
                                                             "demo_population_vs_demo_selected")))

test_that("comparing into an existing comparison stops before any work, and changes nothing", {
  base <- demo_data_dir()
  old <- options(syrona.data_dir = base)
  on.exit({ options(old); unlink(base, recursive = TRUE) })
  suppressMessages(compare_all("demo_population", "demo_selected", domains = "conditions"))
  dir <- file.path(base, "data", "comparisons", "demo_population_vs_demo_selected")
  md5_before <- tools::md5sum(list.files(dir, full.names = TRUE))

  expect_error(suppressMessages(compare_all("demo_population", "demo_selected", domains = "conditions")),
               "overwrite = TRUE")
  expect_identical(tools::md5sum(names(md5_before)), md5_before)
})

test_that("compare_all(overwrite = TRUE) replaces Syrona's files only", {
  base <- demo_data_dir()
  old <- options(syrona.data_dir = base)
  on.exit({ options(old); unlink(base, recursive = TRUE) })
  suppressMessages(compare_all("demo_population", "demo_selected", domains = c("conditions", "drugs")))
  dir <- file.path(base, "data", "comparisons", "demo_population_vs_demo_selected")
  writeLines("my notes", file.path(dir, "notes.txt"))

  suppressMessages(compare_all("demo_population", "demo_selected", domains = "conditions", overwrite = TRUE))

  files <- comparison_files(base)
  expect_false(any(grepl("^drug_", files)))
  expect_true("condition_meta_summary.csv" %in% files)
  expect_true("notes.txt" %in% files)
  expect_null(suppressMessages(load_comparison("demo_population", "demo_selected"))$drug_meta_summary)
})
