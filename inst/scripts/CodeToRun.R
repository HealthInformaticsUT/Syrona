# Syrona: compare two OMOP CDM datasets
#
# Fill in block 0, then run the blocks in order. Each step is explained in
# the vignettes: vignette("a00_get_started", package = "syrona").

library(syrona)

# ---- 0. Settings: the only part to change ------------------------------------

# PostgreSQL server (the password is read from DB_PASSWORD in ~/.Renviron)
host   <- "localhost"   # localhost through an SSH tunnel
port   <- 5432          # with a tunnel: its local port
dbname <- "omop"
user   <- "your_user"

# The CDM schema of each dataset (the same schema for two populations of one database)
cdm_schema_a <- "cdm"
cdm_schema_b <- "cdm"

# The schema where ATLAS writes its cohorts (only for option B below)
cohort_schema <- "results"

# Where the results are saved: Syrona creates data/sources/ and data/comparisons/ here.
# Default: your working directory. For another place: data_dir <- "path/to/folder"
data_dir <- getwd()

# FALSE: stop if a dataset or comparison with the same name was saved before.
# TRUE: replace it.
overwrite <- FALSE

options(syrona.data_dir = data_dir)

# ---- 1. Connect (read-only) ---------------------------------------------------

db_a <- syrona_connect_pg(host = host, port = port, dbname = dbname, user = user,
                          password = Sys.getenv("DB_PASSWORD"), cdm_schema = cdm_schema_a)
db_b <- syrona_connect_pg(host = host, port = port, dbname = dbname, user = user,
                          password = Sys.getenv("DB_PASSWORD"), cdm_schema = cdm_schema_b)

# DuckDB files instead:
# db_a <- syrona_connect("path/to/database_a.duckdb")
# db_b <- syrona_connect("path/to/database_b.duckdb")

# Check: the number of persons in each dataset
db_a$cdm$person |> dplyr::tally()
db_b$cdm$person |> dplyr::tally()

# ---- 2. Extract ---------------------------------------------------------------
# For each dataset keep one line: A everyone, B a cohort from ATLAS, C a hospital.
# More ways (ATLAS JSON, a list of patients): vignette("a03_cohorts", package = "syrona")

extract_all("Dataset_A", db_a, overwrite = overwrite)                                                  # A
# extract_all("Dataset_A", db_a, cohort_id = 1, cohort_schema = cohort_schema, overwrite = overwrite)  # B
# extract_all("Dataset_A", db_a, care_site_id = 101, overwrite = overwrite)                            # C

extract_all("Dataset_B", db_b, overwrite = overwrite)                                                  # A
# extract_all("Dataset_B", db_b, cohort_id = 2, cohort_schema = cohort_schema, overwrite = overwrite)  # B
# extract_all("Dataset_B", db_b, care_site_id = 102, overwrite = overwrite)                            # C

# ---- 3. Compare ---------------------------------------------------------------

compare_all("Dataset_A", "Dataset_B", overwrite = overwrite)

# ---- 4. Explore ---------------------------------------------------------------

run_app(data_dir = data_dir)

# ---- 5. Disconnect ------------------------------------------------------------

syrona_disconnect(db_a)
syrona_disconnect(db_b)
