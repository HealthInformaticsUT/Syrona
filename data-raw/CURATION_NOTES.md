# Syrona demo fixture — curation notes (A1)

Created 2026-07-03. This folder (`data-raw/`) is `.Rbuildignore`d — nothing here ships to CRAN
directly. It holds the **design** of the demo fixture and the **script that builds it**.

## What this is

A small, curated **subset of the real Syrona source data** (not synthetic) that ships as the
package's runnable demo: a user (or CRAN reviewer) can load the shipped demo sources and run the
**actual comparison workflow** (`compare_all()` → dashboard) DB-free.

- `curation_matrix.csv` — the 32-concept master list (which concepts, and why).
- `subset_sources.R` — collects the real source files and filters them to exactly these concepts,
  writing the demo sources (and, optionally, the precomputed comparison).

## Concept-selection strategy — F + I spine, + E coverage, + mammography

Chosen with the ICD-10 **F** (mental/behavioural) and **I** (circulatory) chapters as the backbone,
because — validated against the real comparison data — they deliver every fixture role *and*
Syrona's signature **cross-domain triangulation** for free:

- **F (mental)** → the flagship **under-represented cluster** (opioid dependence, intellectual
  disability, alcohol dependence — the real "addiction / severe mental illness" cluster from
  Case Study 1), plus over-represented "worried-well" (depression, ADHD) and concordant (autism).
- **I (circulatory)** → a high-baseline **concordant anchor** (hypertensive heart disease ~12%),
  the **discordant coding trio** (arrhythmia I48/I49, angina I20 — ratio-significant, small
  absolute), and over-represented cardiac conditions.
- **Interconnection (the payoff):** cardiac *conditions* carry signal while cardiac *procedures*
  (echo, Holter, cardioversion) and *drugs* (ATC-C, folds ≈1.0–1.2) stay concordant → reproduces the
  **diagnosis→procedure/drug dissociation** (coding artifact vs true burden) in one comparison.
  F interconnects with ATC-N psychotropics.

Two deliberate extensions beyond F+I:
1. **Mammography procedure pair** (general 71651007 / screening 24623002) — the coding-change
   demonstrator (Case Study 3), plus a female / age-50–69 specific view. Outside F/I but essential.
2. **E (endocrine) coverage** — type-2 diabetes (E11, concordant common), hypothyroidism (E03),
   lipid disorder (E78, links to statins) — so the per-chapter faceted overview shows ≥3 chapters.

Roles covered: concordant, over-/under-represented, discordant, sparse, coding-change pair, and
**high-heterogeneity** (the one role with no natural real exemplar — engineered by design; see below).

## Direction & folds

Demo pair = `demo_population` (from Est-Health-30, d1) vs `demo_selected` (from EstBB, d2);
`fold = d2/d1` (>1 = higher in the selected/biobank set). Folds are the **real** Est-Health-30 vs
EstBB values for these concepts (100% of the 32 are present in that comparison — verified). The
cardiac-coding folds in the notes column (arrhythmia trio, echo 2.02) are from the **NERH-vs-UTH**
hospital comparison (paper Case Study 2) — that discordance is a within-dataset phenomenon and only
reproduces if the NERH/UTH subset is also shipped (see demo-pair options).

## One engineered role

**High heterogeneity** (I²~80%): real F/I concepts are all I²≈0 (stable). Because we ship a real
subset rather than generating data, there is no dial to force this. Options: (a) accept the fixture
has no high-I² exemplar and demonstrate heterogeneity separately, or (b) if we later add a synthetic
perturbation step, flip one concept's effect by age/sex. Flagged, not yet resolved.

## ⚠️ Governance decision (must confirm before shipping)

This ships a **curated subset of real Estonian aggregate data**, which *reverses* the original CRAN
plan's "fully synthetic, do not reverse-engineer real data" decision. Considerations:

- The **full** aggregate source/comparison data is **already public** on the Syrona GitHub repo
  (released by the author under existing ethics scope), so the shipped subset is a *subset of
  already-public data* — the strongest argument that this is acceptable.
- **EstBB is the only biobank source** (Human Genes Research Act). Est-Health-30 / NERH / UTH are
  health-insurance-derived, less sensitive.
- The subset is tiny (32 concepts) and the pipeline already applies **k=5 suppression**.

**Demo-pair options (pick one):**
- **A. EH30-vs-EstBB subset (recommended for completeness):** 100% concept coverage, all three
  domains, the selection + mammography stories. Includes EstBB (biobank) — needs PI sign-off.
- **B. NERH-vs-UTH subset (biobank-free):** hospital cohorts, carries the cardiac-coding +
  mammography stories, but only ~16 drugs and no under-rep cluster.
- **C. Ship both** (A + B) → the dashboard's comparison selector shows both cross-dataset and
  within-dataset scenarios (matches the paper's two settings). Richest; still tiny.

Fallback if biobank data must not ship at all: use option B, or add light count-jitter to option A so
it becomes "realistic-synthetic."

## Build / next steps

1. Confirm the demo-pair option + governance sign-off above.
2. Run `subset_sources.R` (writes to `data-raw/demo_build/` by default; flip `GOVERNANCE_CONFIRMED`
   to write to `inst/extdata/demo/` for shipping).
3. Wire the app/examples to the shipped demo (point `options(syrona.data_dir=...)` at
   `system.file("extdata/demo", package="syrona")`); add `@examples` running `compare_all()` on it.
4. Downsize `icd10_lookup` + vocabulary lookups to these 32 concept_ids (separate step).

## Local testing (dev only — NOT shipped, NOT for end users)

The shipped `RUN_DEMO.html` tells end users to install from CRAN/GitHub. Until 0.2.0 is pushed,
those routes serve the old April 0.1.0 commit, so to test the *current* tree install from this local
folder instead. This machine-specific recipe stays here (build-excluded) and must never go into the
user-facing HTML.

```r
# In RStudio: Session ▸ Restart R FIRST (can't reinstall a loaded package -> leaves a 00LOCK dir)
remotes::install_local("/Users/maarjapajusalu/claude-workspace/_Art3_Syrona/syrona_CRAN",
                       force = TRUE, upgrade = "never")

library(syrona)
base <- tempdir()
file.copy(system.file("extdata", "demo", package = "syrona"), base, recursive = TRUE)
dir <- file.path(base, "demo")
options(syrona.data_dir = dir)
compare_all("demo_population", "demo_selected")
run_app(data_dir = dir)   # Demographics tab shows the "not in demo" message
```

Gotchas:
- **`install.packages("syrona")` fails** ("not available for this version of R") — expected; it's
  not on CRAN yet. Use `install_local` (above) or, once pushed, `remotes::install_github(...)`.
- **`00LOCK-syrona` lock error** — a prior install collided with a loaded package. Fix:
  `unlink("/Library/Frameworks/R.framework/Versions/4.6/Resources/library/00LOCK-syrona", recursive=TRUE)`
  (or install from a shell where `syrona` isn't loaded), then reinstall. Restart R before reinstalling.
