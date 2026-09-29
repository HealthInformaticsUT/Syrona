# Syrona

Stratified prevalence comparison across OMOP CDM datasets.

Syrona derives stratified prevalence tables from the condition, procedure, and drug records in OMOP CDM databases, computes log2 prevalence ratios between paired datasets, and synthesizes them via random-effects meta-analysis at multiple aggregation levels.

## Choose your starting point

Pick the scenario that matches you - each links to the relevant vignette.

### A. I just want to see the dashboard with demo data

Install from CRAN. The demo data ships inside the package, so no clone is needed:

``` r
install.packages("syrona")
library(syrona)

dir <- file.path(tempdir(), "demo")
file.copy(system.file("extdata", "demo", package = "syrona"), tempdir(), recursive = TRUE)
options(syrona.data_dir = dir)
compare_all("demo_population", "demo_selected", overwrite = TRUE)  # overwrite: run it again
run_app(data_dir = dir)
```

### B. I have my own OMOP CDM and want to compare two cohorts

Install the package and start with the whole path in one page:

``` r
install.packages("syrona")
```

Then read [`vignette("a00_get_started", package = "syrona")`](vignettes/a00_get_started.Rmd): connect, extract, compare and explore, each step in its own vignette after that.

Or start from the ready script with the whole path and all options:

``` r
file.copy(system.file("scripts", "CodeToRun.R", package = "syrona"), "path/to/my_folder")
```

### C. I already have data extracted with Syrona

Point the dashboard at the folder that contains `data/` (see "Where the results are saved"):

``` r
install.packages("syrona")
library(syrona)
run_app(data_dir = "path/to/syrona_output")
```

### From GitHub

The latest release from GitHub (the main branch: the same as CRAN, or newer
while a release waits for CRAN):

``` r
# install.packages("remotes")
remotes::install_github("HealthInformaticsUT/Syrona")
```

If this fails with `HTTP error 401 / Bad credentials`, an expired `GITHUB_PAT` in your `.Renviron` is being sent to GitHub. The repository is public and needs no token: run `usethis::edit_r_environ()`, delete the `GITHUB_PAT=...` line, save, and restart R.

## Quick reference

``` r
library(syrona)
data_dir <- getwd()   # results are saved here: the working directory, or another folder
options(syrona.data_dir = data_dir)

# 1. Connect to an OMOP CDM database (read-only)
db <- syrona_connect_pg(
  host       = "localhost",
  dbname     = "omop",
  user       = "your_user",
  password   = Sys.getenv("DB_PASSWORD"),
  cdm_schema = "cdm"
)
# or a local DuckDB file
db <- syrona_connect("path/to/omop.duckdb")

# 2. Extract stratified prevalence tables
extract_all("Dataset_A", db = db)
extract_all("Dataset_B", db = db)
syrona_disconnect(db)

# 3. Compare
compare_all("Dataset_A", "Dataset_B")

# 4. Explore in the dashboard
run_app(data_dir = data_dir)
```

## Where the results are saved

Syrona creates the folders itself, under the folder set with `options(syrona.data_dir = ...)` (default: the working directory). Nothing has to exist in advance:

```         
<data_dir>/                            by default your working directory
  data/
    sources/Dataset_A/                 created by extract_all()
    comparisons/Dataset_A_vs_Dataset_B/  created by compare_all()
```

Only if you received extracted or compared files from elsewhere, put them into this structure yourself, then open them with `run_app(data_dir = "path/to/syrona_output")`.

## What it does

1.  **Extract** (Phase 1) - query an OMOP CDM via CDMConnector + dplyr to produce prevalence by concept x year x sex x age group, concept metadata, chapter assignments, and SNOMED attributes. k-anonymity suppression applied automatically.

2.  **Compare** (Phase 2) - pair two datasets, match strata, compute log2 prevalence ratios with confidence intervals.

3.  **Meta-analyze** (Phase 3) - synthesize per-stratum estimates via random-effects meta-analysis (Paule-Mandel tau) across years, age groups, and sexes.

## Domains

-   **Conditions** - SNOMED concepts, dashboard filtering: chapters via body system / disease category / ICD-10
-   **Procedures** - SNOMED concepts, dashboard filtering: chapters by method / by site
-   **Drugs** - rolled up to Ingredient level, dashboard filtering: ATC 1st level chapters

## Cohorts and hospitals

Extract a subpopulation instead of the whole database:

``` r
# One hospital (care site): persons with a visit there, events recorded there
extract_all("Hospital_A", db = db, care_site_id = 101)

# A cohort generated in ATLAS, read from the results schema
extract_all("My_cohort", db = db, cohort_id = 2031, cohort_schema = "results")
```

`list_care_sites(db$con, cdm_schema = "cdm")` lists the care sites. See `vignette("a03_cohorts", package = "syrona")`.
