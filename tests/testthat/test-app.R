# Every package the dashboard code uses must be in Imports, so installing
# syrona installs it. The app files are read as R code, not as text: every
# library() / require() / requireNamespace() argument and every pkg:: prefix.

packages_used <- function(e) {
  if (!is.call(e)) return(character(0))
  fn <- e[[1]]
  if (identical(fn, as.name("::")) || identical(fn, as.name(":::"))) {
    return(as.character(e[[2]]))
  }
  own <- if (is.name(fn) && as.character(fn) %in% c("library", "require", "requireNamespace")) {
    as.character(e[[2]])
  }
  c(own, unlist(lapply(as.list(e), packages_used)))
}

test_that("every package the dashboard uses is in Imports", {
  app_files <- list.files(system.file("shiny", package = "syrona"), pattern = "\\.R$", full.names = TRUE)
  used <- unique(unlist(lapply(app_files, function(f) unlist(lapply(parse(f), packages_used)))))
  used <- setdiff(used, "syrona")
  expect_gt(length(used), 0)

  desc <- read.dcf(system.file("DESCRIPTION", package = "syrona"), fields = "Imports")
  imports <- trimws(sub("\\s*\\(.*", "", strsplit(desc[1, "Imports"], ",")[[1]]))

  expect_equal(setdiff(used, imports), character(0))
})
