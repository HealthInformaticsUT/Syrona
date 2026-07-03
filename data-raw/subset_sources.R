# ── Build the Syrona demo fixture by subsetting REAL source data ──────────────
#
# Collects the existing extracted source files (data/sources/<name>/) and filters
# them to ONLY the curated concepts in curation_matrix.csv, producing small demo
# source datasets that reproduce the real comparison workflow DB-free.
#
# This is a one-time build script (data-raw/ is .Rbuildignore'd). Deterministic:
# it only filters/copies, it does not generate or perturb counts.
#
# See CURATION_NOTES.md for the design + the GOVERNANCE decision this script gates.
#
# Usage (from the package root):
#   Rscript data-raw/subset_sources.R
# then inspect data-raw/demo_build/. To ship, set GOVERNANCE_CONFIRMED <- TRUE.

suppressWarnings(suppressMessages({
  have_readr <- requireNamespace("readr", quietly = TRUE)
}))

`%||%` <- function(a, b) if (is.null(a)) b else a

# ── Config ───────────────────────────────────────────────────────────────────

# Resolve the package root: run from the package root, or from data-raw/.
PKG_ROOT <- getwd()
if (!dir.exists(file.path(PKG_ROOT, "data", "sources")) &&
    dir.exists(file.path(PKG_ROOT, "..", "data", "sources"))) {
  PKG_ROOT <- normalizePath(file.path(PKG_ROOT, ".."))
}
if (!dir.exists(file.path(PKG_ROOT, "data", "sources"))) {
  stop("Run from the package root (or data-raw/). Could not find data/sources under ", PKG_ROOT)
}

# Real source dataset  ->  demo dataset name to write.
# Default = the complete cross-dataset pair (option A). Add NERH/UTH for option C.
SRC_MAP <- c(
  "Est-Health-30" = "demo_population",
  "EstBB"         = "demo_selected"
  # "NERH" = "demo_nerh",
  # "UTH"  = "demo_uth"
)

# Governance gate (see CURATION_NOTES.md §Governance).
#   FALSE -> write to data-raw/demo_build/ (NOT shipped) for review.
#   TRUE  -> write to inst/extdata/demo/  (shipped on CRAN).
# Confirmed 2026-07-03: curated subset of already-public aggregate data, k>=5, tiny. Ship it.
GOVERNANCE_CONFIRMED <- TRUE

# Also precompute the comparison? Decision: SHIP SOURCES ONLY — the user runs
# compare_all() themselves (that IS the demo workflow). Keep FALSE for shipping;
# set TRUE only for a local validation build.
RUN_COMPARE <- FALSE

# ── Paths ────────────────────────────────────────────────────────────────────

OUT_BASE <- if (GOVERNANCE_CONFIRMED) {
  file.path(PKG_ROOT, "inst", "extdata", "demo")
} else {
  file.path(PKG_ROOT, "data-raw", "demo_build")
}
SRC_BASE <- file.path(PKG_ROOT, "data", "sources")
matrix_path <- file.path(PKG_ROOT, "data-raw", "curation_matrix.csv")

read_csv_any  <- function(f) if (have_readr) readr::read_csv(f, show_col_types = FALSE, progress = FALSE) else utils::read.csv(f, stringsAsFactors = FALSE, check.names = FALSE)
write_csv_any <- function(x, f) if (have_readr) readr::write_csv(x, f) else utils::write.csv(x, f, row.names = FALSE)

# ── Curated concept_id set (union across domains; simple + safe) ──────────────

stopifnot(file.exists(matrix_path))
mat <- read_csv_any(matrix_path)
curated_ids <- unique(as.integer(mat$concept_id))
message(sprintf("Curated concepts: %d (conditions=%d, procedures=%d, drugs=%d)",
                length(curated_ids), sum(mat$domain == "condition"),
                sum(mat$domain == "procedure"), sum(mat$domain == "drug")))

# ── Subset one source dataset ────────────────────────────────────────────────
# A file is concept-level iff it has a `concept_id` column -> filter to curated.
# Dataset-level files (denominator, demographics, death_counts, _metadata) -> copy.

subset_one <- function(src_name, demo_name) {
  in_dir  <- file.path(SRC_BASE, src_name)
  out_dir <- file.path(OUT_BASE, "data", "sources", demo_name)
  if (!dir.exists(in_dir)) stop("Source not found: ", in_dir)
  dir.create(out_dir, recursive = TRUE, showWarnings = FALSE)

  K_MIN <- 5L
  # demographics.csv is a birth-year x sex table that is NOT k=5-suppressed by the
  # extraction (single-person cells for extreme birth years) and is not needed for
  # the comparison — drop it from the demo. Real DB extraction still produces it
  # (extract_demographics()); the dashboard shows a "not in demo" message instead.
  # _metadata.csv carries the real dataset name + full-dataset counts (stale for the
  # curated demo, and not loaded by the app), so drop it too.
  DROP_FOR_DEMO <- c("demographics.csv", "_metadata.csv")

  files <- list.files(in_dir, pattern = "\\.csv$", full.names = TRUE)
  for (f in files) {
    bn <- basename(f)
    if (bn %in% DROP_FOR_DEMO) {
      message(sprintf("  %-28s DROPPED from demo (not k=5-suppressed; pyramid-only)", bn))
      next
    }
    df <- read_csv_any(f)
    if ("concept_id" %in% names(df)) {
      before <- nrow(df)
      df <- df[as.integer(df$concept_id) %in% curated_ids, , drop = FALSE]
      message(sprintf("  %-28s %6d -> %5d rows", bn, before, nrow(df)))
    } else if (bn == "denominator.csv") {
      # k-anonymity: drop sub-5 strata. Safe — a stratum with <5 observed persons
      # cannot carry a k=5-suppressed concept cell, so no prevalence row references it.
      before <- nrow(df)
      df <- df[as.integer(df$denominator) >= K_MIN, , drop = FALSE]
      message(sprintf("  %-28s %6d -> %5d rows (k>=%d)", bn, before, nrow(df), K_MIN))
    } else {
      message(sprintf("  %-28s (dataset-level, copied)", bn))
    }
    write_csv_any(df, file.path(out_dir, bn))
  }
  invisible(out_dir)
}

# ── Run ──────────────────────────────────────────────────────────────────────

message("\nWriting demo sources to: ", OUT_BASE,
        if (!GOVERNANCE_CONFIRMED) "  (NOT shipped — governance gate is FALSE)" else "")
for (i in seq_along(SRC_MAP)) {
  src <- names(SRC_MAP)[i]; demo <- SRC_MAP[[i]]
  message("\n[", src, " -> ", demo, "]")
  subset_one(src, demo)
}

if (RUN_COMPARE && requireNamespace("dplyr", quietly = TRUE)) {
  message("\nPrecomputing demo comparison via compare_all()...")
  # Load the package's own functions and point the data_dir at the demo base.
  if (requireNamespace("pkgload", quietly = TRUE)) pkgload::load_all(PKG_ROOT, quiet = TRUE)
  old <- getOption("syrona.data_dir")
  options(syrona.data_dir = OUT_BASE)
  on.exit(options(syrona.data_dir = old), add = TRUE)
  demo_names <- unname(SRC_MAP)
  compare_all(demo_names[1], demo_names[2], save = TRUE)
  message("Comparison written under ", file.path(OUT_BASE, "data", "comparisons"))
}

message("\nDone. Inspect the output, then (after governance sign-off) set ",
        "GOVERNANCE_CONFIRMED <- TRUE to write into inst/extdata/demo/ for shipping.")
