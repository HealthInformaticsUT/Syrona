# Every R code chunk in the vignettes, and CodeToRun.R, must be valid R code.
# The vignette chunks are not run when the vignettes are built (eval = FALSE).

# The R chunks of an R Markdown file, as a list of code strings
r_chunks <- function(file) {
  lines <- readLines(file, warn = FALSE)
  starts <- grep("^```\\{r", lines)
  ends <- grep("^```\\s*$", lines)
  lapply(starts, function(s) {
    e <- ends[ends > s][1]
    paste(lines[seq_len(e - s - 1) + s], collapse = "\n")
  })
}

vignette_files <- function() {
  src <- test_path("..", "..", "vignettes")
  dir <- if (dir.exists(src)) src else system.file("doc", package = "syrona")
  list.files(dir, pattern = "\\.Rmd$", full.names = TRUE)
}

test_that("every R chunk in every vignette is valid R code", {
  files <- vignette_files()
  skip_if(length(files) == 0, "Vignette sources not available.")
  for (f in files) {
    chunks <- r_chunks(f)
    for (i in seq_along(chunks)) {
      expect_no_error(parse(text = chunks[[i]]), message = sprintf("%s, R chunk %d", basename(f), i))
    }
  }
})

test_that("CodeToRun.R is valid R code", {
  src <- test_path("..", "..", "inst", "scripts", "CodeToRun.R")
  file <- if (file.exists(src)) src else system.file("scripts", "CodeToRun.R", package = "syrona")
  expect_true(file.exists(file))
  expect_no_error(parse(file))
})
