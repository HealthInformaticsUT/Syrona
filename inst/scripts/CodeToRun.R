# Syrona: compare two OMOP CDM datasets
#
# Fill in block 0, then run the blocks in order. Each step is explained in
# the vignettes: vignette("a00_get_started", package = "syrona").

library(syrona)

# ---- 0. Settings: the only part to change ------------------------------------

# PostgreSQL server
host     <- "localhost"   # localhost through an SSH tunnel
port     <- 5432          # with a tunnel: its local port
dbname   <- "omop"
user     <- "your_user"
password <- Sys.getenv("DB_PASSWORD")   # from ~/.Renviron, never the password itself

# The CDM schema of each dataset (the same schema for two populations of one database)
cdm_schema_a <- "cdm"
cdm_schema_b <- "cdm"

# The schema where ATLAS writes its cohorts (only for option B below). It is not the
# CDM schema. To find it: vignette("a03_cohorts", package = "syrona"), "A cohort generated in ATLAS"
cohort_schema <- "results"

# Where the results are saved: Syrona creates data/sources/ and data/comparisons/ here.
# Default: your working directory. For another place: data_dir <- "path/to/folder"
data_dir <- getwd()

# overwrite is about the result files Syrona saves in data_dir, never the database.
# It only matters when result files with the same name are already saved:
# FALSE stops before they are replaced, TRUE replaces them. New names are never affected.
overwrite <- FALSE

options(syrona.data_dir = data_dir)

# ---- 1. Connect (read-only) ---------------------------------------------------

db_a <- syrona_connect_pg(
  host       = host,
  port       = port,
  dbname     = dbname,
  user       = user,
  password   = password,
  cdm_schema = cdm_schema_a
)
db_b <- syrona_connect_pg(
  host       = host,
  port       = port,
  dbname     = dbname,
  user       = user,
  password   = password,
  cdm_schema = cdm_schema_b
)

# DuckDB files instead. The path is on the machine where R runs. For a file on a
# remote server, run this script in R on that server:
# db_a <- syrona_connect("path/to/database_a.duckdb")
# db_b <- syrona_connect("path/to/database_b.duckdb")

# Check: the number of persons in each dataset
db_a$cdm$person |> dplyr::tally()
db_b$cdm$person |> dplyr::tally()

# ---- 2. Extract ---------------------------------------------------------------
# For each dataset, keep ONE of the options A, B or C: remove the "#" in front of
# the line you want, and put a "#" in front of the others.
# More ways (ATLAS JSON, a list of patients): vignette("a03_cohorts", package = "syrona")

# Dataset A
# A. Everyone in the database
extract_all("Dataset_A", db_a, overwrite = overwrite)
# B. A cohort generated in ATLAS (cohort_id = the ATLAS cohort id, see cohort_schema above)
# extract_all("Dataset_A", db_a, cohort_id = 1, cohort_schema = cohort_schema, overwrite = overwrite)
# C. One hospital (care_site_id from list_care_sites(db_a$con, cdm_schema_a))
# extract_all("Dataset_A", db_a, care_site_id = 101, overwrite = overwrite)

# Dataset B
# A. Everyone in the database
extract_all("Dataset_B", db_b, overwrite = overwrite)
# B. A cohort generated in ATLAS
# extract_all("Dataset_B", db_b, cohort_id = 2, cohort_schema = cohort_schema, overwrite = overwrite)
# C. One hospital
# extract_all("Dataset_B", db_b, care_site_id = 102, overwrite = overwrite)

# ---- 3. Compare ---------------------------------------------------------------

compare_all("Dataset_A", "Dataset_B", overwrite = overwrite)

# ---- 4. Explore ---------------------------------------------------------------

run_app(data_dir = data_dir)

# ---- 5. Disconnect ------------------------------------------------------------

syrona_disconnect(db_a)
syrona_disconnect(db_b)
