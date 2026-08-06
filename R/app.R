# ── Syrona Dashboard Launcher ─────────────────────────────────────────────────

#' Run the Syrona dashboard
#'
#' Launches the Shiny dashboard for exploring prevalence comparisons.
#' The app looks for \code{data/sources/} and \code{data/comparisons/}
#' relative to your current working directory. Run this from the directory
#' that contains your \code{data/} folder.
#'
#' @param data_dir Path to the directory containing \code{data/sources/} and
#'   \code{data/comparisons/}. Defaults to the current working directory.
#' @param port Port to run the app on (default: auto-select).
#' @param launch.browser Whether to open a browser window (default: TRUE).
#' @param ... Additional arguments passed to \code{\link[shiny]{runApp}}.
#' @return No return value, called for its side effect of launching the Shiny
#'   dashboard.
#' @examples
#' # Copy the bundled demo, generate the comparison, then launch the dashboard.
#' if (interactive()) {
#'   base <- tempdir()
#'   file.copy(system.file("extdata", "demo", package = "syrona"), base, recursive = TRUE)
#'   dir <- file.path(base, "demo")
#'   old <- options(syrona.data_dir = dir)
#'   compare_all("demo_population", "demo_selected")
#'   run_app(data_dir = dir)
#'   options(old)
#' }
#' @export
run_app <- function(data_dir = getwd(), port = NULL, launch.browser = TRUE, ...) {
  app_dir <- system.file("shiny", package = "syrona")
  if (app_dir == "") {
    stop("Dashboard not found. Is the syrona package installed correctly?",
         call. = FALSE)
  }

  # Store the user's data directory so global.R can find the data,
  # restoring the user's previous setting when run_app() exits.
  old_opts <- options(syrona.data_dir = normalizePath(data_dir, mustWork = TRUE))
  on.exit(options(old_opts), add = TRUE)

  args <- list(appDir = app_dir, launch.browser = launch.browser, ...)
  if (!is.null(port)) args$port <- port

  do.call(shiny::runApp, args)
}
