# syrona

Stratified prevalence comparison across OMOP CDM datasets.

Syrona derives stratified prevalence tables from the condition, procedure, and drug records in OMOP CDM databases, computes log2 prevalence ratios between paired datasets, and synthesizes them via random-effects meta-analysis at multiple aggregation levels.

## Choose your starting point

Pick the scenario that matches you - each links to the relevant vignette.

### A. I just want to see the dashboard with demo data

Install from CRAN. The demo data ships inside the package, so no clone is
needed:

```r
install.packages("syrona")
library(syrona)

dir <- file.path(tempdir(), "demo")
file.copy(system.file("extdata", "demo", package = "syrona"), tempdir(), recursive = TRUE)
options(syrona.data_dir = dir)
compare_all("demo_population", "demo_selected")
run_app(data_dir = dir)
```

### B. I have my own OMOP CDM and want to compare two cohorts

Install the package and follow the end-to-end walkthrough:

```r
install.packages("syrona")
```

Then read [`vignette("a04_walkthrough", package = "syrona")`](vignettes/a04_walkthrough.Rmd)
which takes you from "I have a remote OMOP CDM" to "the dashboard is
showing my comparison" with verification at every step.

### C. I already have extracted syrona data

Install the package, point at your data directory, launch:

```r
install.packages("syrona")
library(syrona)
options(syrona.data_dir = "/path/to/your/syrona/data")
run_app()
```

Your data directory must contain `sources/` (extracted datasets) and
optionally `comparisons/` (pre-computed comparison results).

### Development version

The latest version from GitHub:

```r
# install.packages("remotes")
remotes::install_github("HealthInformaticsUT/Syrona")
```

If this fails with `HTTP error 401 / Bad credentials`, an expired
`GITHUB_PAT` in your `.Renviron` is being sent to GitHub. The repository is
public and needs no token: run `usethis::edit_r_environ()`, delete the
`GITHUB_PAT=...` line, save, and restart R.

## Quick reference

```r
library(syrona)

# 1. Connect to an OMOP CDM database
db <- syrona_connect("path/to/omop.duckdb")           # local DuckDB
# or
db <- syrona_connect_pg(host = "localhost", ...)       # PostgreSQL via SSH tunnel

# 2. Extract stratified prevalence tables
extract_all("Dataset_A", db = db)
extract_all("Dataset_B", db = db)
syrona_disconnect(db)

# 3. Compare
compare_all("Dataset_A", "Dataset_B")

# 4. Explore in the dashboard
run_app()
```

## What it does

1. **Extract** (Phase 1) - query an OMOP CDM via CDMConnector + dplyr to produce prevalence by concept x year x sex x age group, concept metadata, chapter assignments, and SNOMED attributes. k-anonymity suppression applied automatically.

2. **Compare** (Phase 2) - pair two datasets, match strata, compute log2 prevalence ratios with confidence intervals.

3. **Meta-analyze** (Phase 3) - synthesize per-stratum estimates via random-effects meta-analysis (Paule-Mandel tau) across years, age groups, and sexes.

## Domains

- **Conditions** - SNOMED concepts, chapters via body system / disease category / ICD-10
- **Procedures** - SNOMED concepts, chapters by method / by site
- **Drugs** - rolled up to Ingredient level, ATC 1st level chapters

## OHDSI cohort support

Extract subpopulations using standard OHDSI cohort tables:

```r
# Create a care-site cohort
create_caresite_cohort(con, care_site_id = 101, cohort_id = 1,
                       cohort_schema = "results", cdm_schema = "cdm")

# Extract only that cohort
extract_all("Hospital_A", db = db, cohort_id = 1, cohort_schema = "results")
```

## Dependencies

- [CDMConnector](https://CRAN.R-project.org/package=CDMConnector) (>= 2.0.0)
- [omopgenerics](https://CRAN.R-project.org/package=omopgenerics) (>= 1.3.0)
- [meta](https://CRAN.R-project.org/package=meta) (for meta-analysis)
- [duckdb](https://CRAN.R-project.org/package=duckdb) (for local databases)
