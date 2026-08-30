/* =============================================================================
   IPEDS 12-MONTH ENROLLMENT (E1D) -- INSTRUCTIONAL ACTIVITY EXTRACT
   =============================================================================
   Purpose : Produce the ONE-ROW summary of institution-wide instructional
             activity for the 12-month reporting period, in the exact
             column layout required by IPEDSuploadables::produce_e1d_report():

   https://alisonlanski.github.io/IPEDSuploadables/articles/setup_for_12monthenrollment.html

   Required output columns:
     Unitid, CreditHoursUG, ClockHoursUG, CreditHoursGR, DocFTE

   Platform  : Ellucian Banner (Oracle), run via SQL*Plus or SQLcl
   -----------------------------------------------------------------------------
   NOTES
   -----------------------------------------------------------------------------
   - CreditHoursUG / CreditHoursGR come straight from registered credit hours
     (SFRSTCR), split by course level, for the same set of terms used in the
     companion enrollment extract (01_e1d_enrollment_extract.sql). Keep the
     term-selection window IDENTICAL between the two scripts.
   - CreditHoursGR must EXCLUDE doctoral/professional-practice credit hours
     per IPEDS instructions -- those students' activity is captured instead
     via DocFTE. >>> CUSTOMIZE the doctoral/professional level code(s).
   - ClockHoursUG only applies if your institution reports any programs on
     the clock-hour system. If you don't, leave it at 0. If you do, you must
     pull clock hours from wherever your clock-hour programs are tracked
     (this is NOT a standard SFRSTCR field in most Banner installs --
     commonly a custom table, a validation extension, or an outside system).
   - DocFTE: IPEDS defines this using your institution's standard FTE
     formula for doctoral/professional-practice students. A common
     approach is full-time doctoral/professional headcount x 1.0, plus
     part-time headcount x your standard part-time FTE factor. Adjust the
     factor below to match what your institution reports elsewhere (e.g.
     the same factor used for Fall FTE / 12-month FTE calculations).
   ============================================================================= */

WHENEVER SQLERROR EXIT SQL.SQLCODE
SET VERIFY OFF
SET ECHO OFF
SET FEEDBACK OFF
SET TRIMSPOOL ON
SET LINESIZE 32767
SET PAGESIZE 0
SET TERMOUT OFF
SET SERVEROUTPUT OFF
-- Without this, SQL*Plus/SQLcl treats a BLANK LINE inside a multi-line SQL
-- statement as an implicit statement terminator (its default behavior),
-- which would cut the WITH clause below off after its first CTE. Turning
-- this ON lets blank lines be used freely for readability between CTEs.
SET SQLBLANKLINES ON

/* ---------------------------------------------------------------------------
   1. PARAMETERS -- MUST MATCH 01_e1d_enrollment_extract.sql
   --------------------------------------------------------------------------- */
-- >>> CUSTOMIZE: same Unitid as enrollment file
DEFINE unitid          = 123456
-- >>> CUSTOMIZE: same period as enrollment file
DEFINE period_start    = '01-JUL-2025'
-- >>> CUSTOMIZE: same period as enrollment file
DEFINE period_end      = '30-JUN-2026'
-- >>> CUSTOMIZE
DEFINE output_dir      = '/Users/yourname/ipeds-test'

-- Part-time FTE factor for doctoral/professional-practice students.
-- >>> CUSTOMIZE to your institution's standard FTE conversion factor.
DEFINE doc_pt_fte_factor = 0.34

SPOOL &output_dir/e1d_instructional_activity.csv
SET MARKUP CSV ON DELIMITER , QUOTE ON

WITH

relevant_terms AS (
    SELECT stvterm_code AS term_code
    FROM   stvterm
    WHERE  stvterm_start_date <= TO_DATE('&period_end','DD-MON-YYYY')
    AND    stvterm_end_date   >= TO_DATE('&period_start','DD-MON-YYYY')
),

/* ---------------------------------------------------------------------------
   2. REGISTERED CREDIT HOURS BY COURSE LEVEL
      >>> CUSTOMIZE: SCBCRSE_LEVL_CODE values for UG / Graduate / Doctoral-
          professional at your institution (commonly 'UG', 'GR', 'DR' or
          similar -- check STVLEVL).
      >>> CUSTOMIZE: SFRSTCR_STST_CODE values counted as registered.
   --------------------------------------------------------------------------- */
credit_activity AS (
    SELECT
        sc.scbcrse_levl_code                         AS levl_code,
        SUM(s.sfrstcr_credit_hr)                      AS total_credit_hrs
    FROM   sfrstcr s
    JOIN   scbcrse sc
           ON  sc.scbcrse_subj_code = s.sfrstcr_subj_code
           AND sc.scbcrse_crse_numb = s.sfrstcr_crse_numb
    WHERE  s.sfrstcr_term_code IN (SELECT term_code FROM relevant_terms)
    AND    s.sfrstcr_rsts_code IN ('RE')              -- >>> CUSTOMIZE
    GROUP BY sc.scbcrse_levl_code
),

credit_hours_ug AS (
    SELECT NVL(SUM(total_credit_hrs),0) AS hrs
    FROM   credit_activity
    WHERE  levl_code = 'UG'                            -- >>> CUSTOMIZE
),

credit_hours_gr AS (
    SELECT NVL(SUM(total_credit_hrs),0) AS hrs
    FROM   credit_activity
    WHERE  levl_code = 'GR'                            -- >>> CUSTOMIZE (excludes doctoral/professional level)
),

/* ---------------------------------------------------------------------------
   3. CLOCK HOURS (UG)
      >>> CUSTOMIZE entirely: most Banner installs do not store clock hours
      in a standard core table. Replace this stub with a query against
      wherever your clock-hour program hours are tracked, or leave as a
      hard-coded 0 if your institution uses the credit-hour system only.
   --------------------------------------------------------------------------- */
clock_hours_ug AS (
    SELECT 0 AS hrs FROM dual                          -- >>> CUSTOMIZE if applicable
),

/* ---------------------------------------------------------------------------
   4. DOCTORAL / PROFESSIONAL-PRACTICE FTE
      Identifies doctoral/professional students enrolled during the period
      via SGBSTDN level code, classifies each as full/part time using the
      same threshold logic as the enrollment extract, and converts to FTE.
      >>> CUSTOMIZE: SGBSTDN_LEVL_CODE value for doctoral/professional
          (commonly 'DR', 'PR', or similar -- check STVLEVL) and the
          full-time credit-hour threshold for that level.
   --------------------------------------------------------------------------- */
doc_term_credit AS (
    SELECT
        s.sfrstcr_pidm      AS pidm,
        s.sfrstcr_term_code AS term_code,
        SUM(s.sfrstcr_credit_hr) AS term_credit_hrs
    FROM   sfrstcr s
    WHERE  s.sfrstcr_term_code IN (SELECT term_code FROM relevant_terms)
    AND    s.sfrstcr_rsts_code IN ('RE')               -- >>> CUSTOMIZE
    GROUP BY s.sfrstcr_pidm, s.sfrstcr_term_code
),
doc_students AS (
    SELECT DISTINCT sgbstdn_pidm AS pidm
    FROM   sgbstdn
    WHERE  sgbstdn_levl_code = 'DR'                    -- >>> CUSTOMIZE doctoral/professional level code
    AND    sgbstdn_term_code_eff IN (SELECT term_code FROM relevant_terms)
),
doc_max_credit AS (
    SELECT ds.pidm, MAX(dtc.term_credit_hrs) AS max_hrs
    FROM   doc_students ds
    JOIN   doc_term_credit dtc ON dtc.pidm = ds.pidm
    GROUP BY ds.pidm
),
doc_fte AS (
    SELECT
        SUM(CASE WHEN max_hrs >= 9 THEN 1                       -- >>> CUSTOMIZE FT threshold for doc/prof
                 ELSE &doc_pt_fte_factor END) AS fte_total
    FROM doc_max_credit
)

SELECT
    &unitid                          AS "Unitid",
    (SELECT hrs FROM credit_hours_ug) AS "CreditHoursUG",
    (SELECT hrs FROM clock_hours_ug)  AS "ClockHoursUG",
    (SELECT hrs FROM credit_hours_gr) AS "CreditHoursGR",
    ROUND(NVL((SELECT fte_total FROM doc_fte),0), 2) AS "DocFTE"
FROM dual;

SET MARKUP CSV OFF
SPOOL OFF

SET PAGESIZE 14
SET TERMOUT ON
SET FEEDBACK ON
PROMPT Instructional activity extract written to &output_dir/e1d_instructional_activity.csv
EXIT
