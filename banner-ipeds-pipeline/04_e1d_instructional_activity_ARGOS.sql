/* =============================================================================
   IPEDS 12-MONTH ENROLLMENT (E1D) -- INSTRUCTIONAL ACTIVITY EXTRACT
   ARGOS DATABLOCK VERSION (plain SELECT + Oracle bind parameters)
   =============================================================================
   Recommended parameter setup in Argos:
     :unitid            NUMBER  hidden
     :period_start      DATE    hidden or prompted
     :period_end        DATE    hidden or prompted
     :doc_pt_fte_factor NUMBER  default 0.34, hidden

   Must use the SAME :period_start / :period_end values as the enrollment
   DataBlock (03_e1d_enrollment_ARGOS.sql) for a given reporting cycle.
   ============================================================================= */

WITH

relevant_terms AS (
    SELECT stvterm_code AS term_code
    FROM   stvterm
    WHERE  stvterm_start_date <= :period_end
    AND    stvterm_end_date   >= :period_start
),

credit_activity AS (
    SELECT
        sc.scbcrse_levl_code AS levl_code,
        SUM(s.sfrstcr_credit_hr) AS total_credit_hrs
    FROM   sfrstcr s
    JOIN   scbcrse sc
           ON  sc.scbcrse_subj_code = s.sfrstcr_subj_code
           AND sc.scbcrse_crse_numb = s.sfrstcr_crse_numb
    WHERE  s.sfrstcr_term_code IN (SELECT term_code FROM relevant_terms)
    AND    s.sfrstcr_rsts_code IN ('RE')            -- >>> CUSTOMIZE
    GROUP BY sc.scbcrse_levl_code
),

credit_hours_ug AS (
    SELECT NVL(SUM(total_credit_hrs),0) AS hrs
    FROM   credit_activity
    WHERE  levl_code = 'UG'                          -- >>> CUSTOMIZE
),

credit_hours_gr AS (
    SELECT NVL(SUM(total_credit_hrs),0) AS hrs
    FROM   credit_activity
    WHERE  levl_code = 'GR'                          -- >>> CUSTOMIZE
),

clock_hours_ug AS (
    SELECT 0 AS hrs FROM dual                        -- >>> CUSTOMIZE if CCSU has clock-hour programs
),

doc_term_credit AS (
    SELECT
        s.sfrstcr_pidm      AS pidm,
        s.sfrstcr_term_code AS term_code,
        SUM(s.sfrstcr_credit_hr) AS term_credit_hrs
    FROM   sfrstcr s
    WHERE  s.sfrstcr_term_code IN (SELECT term_code FROM relevant_terms)
    AND    s.sfrstcr_rsts_code IN ('RE')            -- >>> CUSTOMIZE
    GROUP BY s.sfrstcr_pidm, s.sfrstcr_term_code
),
doc_students AS (
    SELECT DISTINCT sgbstdn_pidm AS pidm
    FROM   sgbstdn
    WHERE  sgbstdn_levl_code = 'DR'                  -- >>> CUSTOMIZE doctoral/professional level code
    AND    sgbstdn_term_code_eff IN (SELECT term_code FROM relevant_terms)
),
doc_max_credit AS (
    SELECT ds.pidm, MAX(dtc.term_credit_hrs) AS max_hrs
    FROM   doc_students ds
    JOIN   doc_term_credit dtc ON dtc.pidm = ds.pidm
    GROUP BY ds.pidm
),
doc_fte AS (
    SELECT SUM(CASE WHEN max_hrs >= 9 THEN 1 ELSE :doc_pt_fte_factor END) AS fte_total  -- >>> CUSTOMIZE FT threshold
    FROM   doc_max_credit
)

SELECT
    :unitid                            AS "Unitid",
    (SELECT hrs FROM credit_hours_ug)  AS "CreditHoursUG",
    (SELECT hrs FROM clock_hours_ug)   AS "ClockHoursUG",
    (SELECT hrs FROM credit_hours_gr)  AS "CreditHoursGR",
    ROUND(NVL((SELECT fte_total FROM doc_fte),0), 2) AS "DocFTE"
FROM dual
