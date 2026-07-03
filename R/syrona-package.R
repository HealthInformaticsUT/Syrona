#' syrona: Stratified prevalence comparison across OMOP CDM datasets
#'
#' Derives stratified prevalence tables from the condition, procedure, and drug
#' records in OMOP CDM databases, computes log2 prevalence ratios between
#' paired datasets, and synthesizes them via random-effects meta-analysis
#' at multiple aggregation levels (year, age group, sex).
#'
#' @keywords internal
#' @importFrom rlang .data
#' @importFrom rlang `%||%`
"_PACKAGE"

# Non-standard-evaluation symbols flagged by R CMD check:
#   n    - dplyr summarise(n = ...) result column
#   year - dbplyr SQL translation (resolved at query time, not an R function)
utils::globalVariables(c("n", "year"))
