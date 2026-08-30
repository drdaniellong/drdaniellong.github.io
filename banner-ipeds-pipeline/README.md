---
title: IPEDS 12-Month Enrollment (E1D) — Banner SQL Extracts
---

# IPEDS 12-Month Enrollment (E1D) — Banner SQL Extracts

Two SQL\*Plus / SQLcl scripts that query an Ellucian Banner (Oracle) database
and spool two CSV files matching the format required by
`IPEDSuploadables::produce_e1d_report()`:

https://alisonlanski.github.io/IPEDSuploadables/articles/setup_for_12monthenrollment.html

New to this project? Start with the [plain-language overview](OVERVIEW.md)
instead of this technical README.

| Script | Output | Grain |
|---|---|---|
| [`01_e1d_enrollment_extract.sql`](01_e1d_enrollment_extract.sql) | `e1d_enrollment.csv` | One row per student |
| [`02_e1d_instructional_activity.sql`](02_e1d_instructional_activity.sql) | `e1d_instructional_activity.csv` | One row total |

## All files in this project

| File | What it is |
|---|---|
| [`OVERVIEW.md`](OVERVIEW.md) | Plain-language explanation for non-technical readers |
| [`00_code_discovery.sql`](00_code_discovery.sql) | Run first — pulls your institution's real Banner validation-table codes |
| [`01_e1d_enrollment_extract.sql`](01_e1d_enrollment_extract.sql) | Main enrollment extract (SQL\*Plus / SQLcl version) |
| [`02_e1d_instructional_activity.sql`](02_e1d_instructional_activity.sql) | Main instructional-activity extract (SQL\*Plus / SQLcl version) |
| [`03_e1d_enrollment_ARGOS.sql`](03_e1d_enrollment_ARGOS.sql) | Same enrollment extract, rewritten for an Argos DataBlock |
| [`04_e1d_instructional_activity_ARGOS.sql`](04_e1d_instructional_activity_ARGOS.sql) | Same instructional-activity extract, rewritten for an Argos DataBlock |
| [`05_generate_test_data.sql`](05_generate_test_data.sql) | Builds a fake Banner schema + 100 test students to run everything against locally |
| [`README_ARGOS.md`](README_ARGOS.md) | Step-by-step guide to running the extracts through Argos |
| [`IPEDS_E1D_Test_Workflow_Summary.docx`](IPEDS_E1D_Test_Workflow_Summary.docx) | Full narrative of how this was built and tested end-to-end |
| [`CCSU_Argos_Real_Data_QC_Plan.docx`](CCSU_Argos_Real_Data_QC_Plan.docx) | Quality-control checklist for running this against real institutional data |

## Before you run these

Banner installations vary a lot in which validation-table codes they use.
Every place that needs a school-specific value is marked `>>> CUSTOMIZE`
in the SQL. At minimum, review and adjust:

- **Unitid, reporting period, output directory** — top of each script (`DEFINE` block). Keep the period identical across both scripts.
- **"Registered" status codes** (`SFRSTCR_STST_CODE`) — which registration statuses count as enrolled vs. dropped/cancelled.
- **Level codes** (`SCBCRSE_LEVL_CODE` / `SGBSTDN_LEVL_CODE`) — your codes for Undergraduate, Graduate, and Doctoral/Professional-practice (check `STVLEVL`).
- **Student type codes** (`SGBSTDN_STYP_CODE`) — used here as a stand-in for first-time, transfer, degree/certificate-seeking, high school, and dual-enrollment flags (check `STVSTYP`). Many schools track these more precisely via admissions tables (`SARADAP`) or a dedicated IPEDS cohort field — swap in your source of truth if `STYP_CODE` isn't reliable for these distinctions at your institution.
- **Race/ethnicity codes** (`SPBPERS_ETHN_CDE`, `SPBPERS_CITZ_IND`, `GORPRAC_RACE_CDE`) — check `STVETHN` / `STVRACE` for your actual code values.
- **Distance education indicator** (`SSBSECT_INSM_CODE`) — the code(s) your registrar's office uses to flag fully online/distance sections.
- **Full-time credit-hour thresholds** — defaults are 12 (UG) / 9 (Grad) per term; confirm against your catalog.
- **Clock hours** — most Banner installs don't store these in a standard table. The script stubs this at 0; replace with your actual source if you have clock-hour programs.
- **Doctoral/professional FTE factor** — the part-time FTE conversion factor is a placeholder (`0.34`); use whatever your institution already uses for FTE reporting.

## Business-rule judgment calls

A few things are genuine IPEDS methodology decisions, not just code mapping,
and your institutional research office should sign off on the choices baked
into the SQL:

- **Full/part-time status when a student enrolled in more than one term during the period** — this version uses the student's single highest-credit term. Some schools instead use status as of a specific census date, or "full-time if full-time in any term."
- **Which academic-record snapshot drives level/degree-seeking/student-type** — this version uses the student's most recent `SGBSTDN` record as of their last enrolled term in the period. If a student's classification changed mid-year (e.g., non-degree → degree-seeking), confirm this matches how your school wants that captured.
- **DocFTE formula** — IPEDS lets institutions apply their own standard FTE formula; make sure the one here matches what you use elsewhere (e.g., your Fall FTE calculation).

## Running the scripts

```bash
sqlplus banner_read_user/password@BANPROD @01_e1d_enrollment_extract.sql
sqlplus banner_read_user/password@BANPROD @02_e1d_instructional_activity.sql
```

(or `sql` in place of `sqlplus` if you're using SQLcl). Each script uses
`SET MARKUP CSV ON` so the spooled file comes out already comma-delimited,
quoted, and headered — no post-processing needed before handing the two
CSVs to `produce_e1d_report()`.

## After extraction

Feed the two CSVs straight into the R package:

```r
library(IPEDSuploadables)

enrollment  <- readr::read_csv("e1d_enrollment.csv")
instruction <- readr::read_csv("e1d_instructional_activity.csv")

produce_e1d_report(enrollment, instruction)
```
