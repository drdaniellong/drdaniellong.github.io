# Running the E1D Extracts Through Argos

Argos (Evisions) is a report-writer front end that sits on top of your
Banner Oracle database. It runs plain SQL, not SQL\*Plus scripts, so the
`SPOOL` / `SET MARKUP CSV` / `DEFINE` versions won't work as-is inside Argos.
Use `03_e1d_enrollment_ARGOS.sql` and `04_e1d_instructional_activity_ARGOS.sql`
instead — same logic, rewritten as plain `SELECT` statements with Oracle bind
variables (`:unitid`, `:period_start`, etc.) that Argos turns into parameters
automatically.

Two building blocks in Argos matter here:

- **DataBlock** — holds the SQL query itself.
- **Extract** — an output object attached to a DataBlock that can write CSV
  (also Excel, text, XML). This is what you actually run/schedule to
  produce the file. (A "Report" object in Argos is for formatted/printed
  output — not what you want for a flat CSV feed into IPEDSuploadables.)

## Step-by-step

1. **Find your data source.** In the Argos client, in the left-hand
   folder tree, confirm you have (or your Argos admin has set up) a Data
   Source connection pointing at the Banner production/reporting database
   you need — usually already exists as something like "Banner - PROD" or
   similar for your institution.

2. **Discover your local codes first.** Before building the real
   extract, run `00_code_discovery.sql` (via SQL\*Plus/SQLcl, or paste it
   into a throwaway Argos DataBlock) so you have your actual `STVSTYP`,
   `STVLEVL`, `STVETHN`, `STVRACE`, `STVCITZ`, `STVRSTS`, `GTVINSM`, and
   `STVASTY` values in hand. Update every `>>> CUSTOMIZE` line in the
   Argos SQL files with those values before proceeding.

3. **Create the enrollment DataBlock.**
   - Right-click the folder where you want it → **New → DataBlock**.
   - Pick your Banner data source.
   - Choose **Direct SQL** (sometimes called "SQL Editor" depending on
     your Argos version) rather than the drag-and-drop query builder —
     this extract is too complex for the visual builder.
   - Paste in the contents of `03_e1d_enrollment_ARGOS.sql`.
   - Save. Argos will scan the SQL, find the `:unitid`, `:period_start`,
     `:period_end`, `:ft_threshold_ug`, `:ft_threshold_gr` bind variables,
     and prompt you to define each as a **DataBlock Variable**:
     - Set the correct data type (NUMBER for unitid/thresholds, DATE for
       the two period variables).
     - Give each a default value (your real Unitid, `07/01/2025`,
       `06/30/2026`, `12`, `9`, etc.).
     - Check "Hidden" for variables you don't want a user to be prompted
       for at run time (typically all of them, once you've set correct
       defaults) — or leave them visible/prompted if you want to reuse
       this DataBlock for other reporting periods without editing SQL.
   - Run/preview the DataBlock to confirm it returns rows without errors.

4. **Create the instructional-activity DataBlock** the same way, using
   `04_e1d_instructional_activity_ARGOS.sql`. Make sure `:period_start`
   and `:period_end` (and `:unitid`) are set to the *same* values as the
   enrollment DataBlock for a given reporting cycle.

5. **Build the Extract objects.**
   - Right-click each DataBlock → **New → Extract** (naming convention
     e.g. `E1D_Enrollment_Extract`, `E1D_InstructionalActivity_Extract`).
   - In the Extract Wizard, add all fields from the DataBlock in the
     column order shown in the IPEDSuploadables spec (order doesn't
     strictly matter since it reads by column name, but matching it
     makes review easier).
   - Set the output format to **CSV** (comma-delimited, headers
     included — Argos includes a "Include Column Headers" checkbox; turn
     it on) and choose delimiter `,` with text qualifier `"` if your
     Argos version offers that option, matching the format the R package
     expects.
   - Set the output filename, e.g. `e1d_enrollment.csv` and
     `e1d_instructional_activity.csv`.

6. **Run it.**
   - Manually: right-click the Extract → **Run Extract**, confirm/adjust
     any visible parameters, and Argos will generate the CSV to your
     chosen destination (local download, network share, or FTP/email
     depending on how your Argos server is configured).
   - On a schedule: right-click the Extract → **Schedule**, set the
     cadence (IPEDS 12-month collection typically runs once a year in
     the fall for the prior July 1–June 30 period), and set the
     destination (shared drive, email attachment, etc.) so it's ready
     when your IR office needs it.

7. **Verify before uploading.** Open both CSVs and confirm:
   - Column headers exactly match `Unitid, StudentId, RaceEthnicity, Sex,
     GenderDetail, IsFullTime, IsFirstTime, IsTransfer,
     IsDegreeCertSeeking, StudentLevel, IsHighSchool, IsDual,
     DistanceEdAll, DistanceEdSome` (enrollment file) and `Unitid,
     CreditHoursUG, ClockHoursUG, CreditHoursGR, DocFTE` (instructional
     activity file).
   - One row per student in the enrollment file, one row total in the
     instructional activity file.
   - Then feed both into `IPEDSuploadables::produce_e1d_report()` as
     shown in the main README.

## Common Argos gotchas

- **CTEs (`WITH ... AS (...)`)**: modern Argos versions pass SQL straight
  through to Oracle, so `WITH` clauses work fine. If your Argos version
  is old enough to choke on them, the query can be flattened into nested
  inline views instead — say the word and I can rewrite it that way.
- **Bind variable data types**: if Argos treats `:period_start` /
  `:period_end` as strings instead of dates, either set the DataBlock
  variable type explicitly to Date in the variable properties, or wrap
  the comparisons in `TO_DATE(:period_start,'MM/DD/YYYY')` to force it.
- **Long-running query**: this touches `SFRSTCR` across a full year of
  terms institution-wide; if it times out in the Argos UI, ask your DBA
  about running it as a scheduled Extract (which typically has a longer
  timeout) rather than an interactive preview.
