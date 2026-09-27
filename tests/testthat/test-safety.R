# ── Safety tests: Syrona must never damage the CDM or other users' data ──────
#
# Each test is added together with the change it protects, one commit each.
# Database tests use the helpers in helper-setup.R (temporary DuckDB copies,
# the local PostgreSQL test server) and must run with 0 skipped before a release.
#
# Planned tests:
#   T1   insert_cohort() refuses an OMOP table name before writing
#   T2   cohort-building functions stop with a clear message without a write schema
#   T3   before/after snapshot of every table: only syrona_* tables are new
#   T4   care-site helpers require a cohort schema that is not the CDM schema
#   T5   a 3-person cohort from insert_cohort() gives exactly 3 persons, also
#        when an old table called "cohort" exists
#   T5b  care-site cohort = the same persons as hand-written SQL, foreign
#        cohort tables untouched
#   T5c  cohort_summary() is right for every cohort source
#   T5d  a named cohort table (ATLAS results / CohortGenerator) is read, not changed
#   T5e  missing columns, unknown cohort id, overlapping entries, equal start
#        dates: a clear stop before extraction
#   T6   a female-only sex column loads as character, compare_all() runs
#   T7   re-running a care-site cohort does not double it
#   T8   a failed insert keeps the previous cohort (transaction)
#   T9   schema names with capitals work on PostgreSQL (quoted identifiers)
#   T10  overlapping visits do not double record counts
#   T11  an existing dataset folder is not overwritten without overwrite = TRUE,
#        and a user's own file in it is kept
#   T12  no count below k = 5 in any saved table, compare_all() unchanged
#   T13  a permanent table named like a temporary helper table survives
#   T14  dataset names that point outside the data folder are rejected
#   T15  two runs give byte-identical CSV files
#   T16  an unwritable write schema gives a Syrona message
#   T17  every saved CSV of GiBleed and Synthea: no count below 5
#   T18  the default connection is read-only and leaves the database file unchanged
#   T19  options(syrona.data_dir) is used by run_app()
#   PG1-PG8  the PostgreSQL versions: read-only reader, clear messages, foreign
#        tables untouched, exact cohort counts, same CSVs as DuckDB,
#        transactions, CDM unchanged as owner
