/* =============================================================================
   IPEDS 12-MONTH ENROLLMENT (E1D) -- STUDENT ENROLLMENT EXTRACT
   =============================================================================
   Purpose : Produce ONE ROW PER STUDENT for the IPEDS 12-month reporting
             period, in the exact column layout required by the
             IPEDSuploadables R package's produce_e1d_report() function:

   https://alisonlanski.github.io/IPEDSuploadables/articles/setup_for_12monthenrollment.html

   Required output columns (any capitalization is fine, extra columns OK):
     Unitid, StudentId, RaceEthnicity, Sex, GenderDetail, IsFullTime,
     IsFirstTime, IsTransfer, IsDegreeCertSeeking, StudentLevel,
     IsHighSchool, IsDual, DistanceEdAll, DistanceEdSome

   Platform  : Ellucian Banner (Oracle), run via SQL*Plus or SQLcl
   Author    : <your name / office>
   -----------------------------------------------------------------------------
   HOW TO RUN
   -----------------------------------------------------------------------------
   1. Edit the DEFINE block below (unitid, reporting period, output path).
   2. Review every block marked  ">>> CUSTOMIZE"  -- these depend on your
      institution's Banner validation-table codes and business rules.
   3. Run:   sqlplus user/pass@db @01_e1d_enrollment_extract.sql
      or:    sql user/pass@db @01_e1d_enrollment_extract.sql   (SQLcl)
   4. Output CSV lands at &output_dir/e1d_enrollment.csv
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
   1. PARAMETERS  -- edit these for every reporting cycle
   --------------------------------------------------------------------------- */
-- >>> CUSTOMIZE: your 6-digit IPEDS Unitid
DEFINE unitid        = 123456
-- >>> CUSTOMIZE: 12-month collection period start
DEFINE period_start  = '01-JUL-2025'
-- >>> CUSTOMIZE: 12-month collection period end
DEFINE period_end    = '30-JUN-2026'
-- >>> CUSTOMIZE: server-side directory SQL*Plus can write to
DEFINE output_dir    = '/Users/yourname/ipeds-test'

-- Full-time credit-hour thresholds (per term). Adjust to your catalog's
-- definition of full-time status if different.
DEFINE ft_threshold_ug = 12
DEFINE ft_threshold_gr = 9

SPOOL &output_dir/e1d_enrollment.csv
SET MARKUP CSV ON DELIMITER , QUOTE ON

WITH

/* ---------------------------------------------------------------------------
   2. TERMS THAT FALL INSIDE THE 12-MONTH REPORTING PERIOD
      Pulled dynamically from STVTERM so you don't have to hand-list term
      codes every year. Uses term start/end dates -- adjust the overlap
      logic if your school's summer term historically spans the July 1
      boundary and needs special handling.
   --------------------------------------------------------------------------- */
relevant_terms AS (
    SELECT stvterm_code AS term_code
    FROM   stvterm
    WHERE  stvterm_start_date <= TO_DATE('&period_end','DD-MON-YYYY')
    AND    stvterm_end_date   >= TO_DATE('&period_start','DD-MON-YYYY')
),

/* ---------------------------------------------------------------------------
   3. REGISTERED CREDIT HOURS PER STUDENT PER TERM
      SFRSTCR = course registration table.
      >>> CUSTOMIZE: SFRSTCR_STST_CODE values that count as "registered"
          (commonly 'RE' = Registered; exclude cancelled/withdrawn codes
          per your school's IPEDS business rules).
   --------------------------------------------------------------------------- */
term_credit AS (
    SELECT
        s.sfrstcr_pidm                              AS pidm,
        s.sfrstcr_term_code                         AS term_code,
        SUM(s.sfrstcr_credit_hr)                    AS term_credit_hrs,
        MAX(sc.scbcrse_levl_code)                   AS course_level_code   -- crude "level of term" tiebreak
    FROM   sfrstcr s
    JOIN   scbcrse sc
           ON  sc.scbcrse_subj_code = s.sfrstcr_subj_code
           AND sc.scbcrse_crse_numb = s.sfrstcr_crse_numb
    WHERE  s.sfrstcr_term_code IN (SELECT term_code FROM relevant_terms)
    AND    s.sfrstcr_rsts_code IN ('RE')            -- >>> CUSTOMIZE
    GROUP BY s.sfrstcr_pidm, s.sfrstcr_term_code
),

/* ---------------------------------------------------------------------------
   4. DISTANCE EDUCATION FLAGS
      Based on the instructional method on each registered section.
      >>> CUSTOMIZE: SSBSECT_INSM_CODE value(s) that represent fully
          online / distance sections at your institution.
   --------------------------------------------------------------------------- */
section_de AS (
    SELECT
        s.sfrstcr_pidm                              AS pidm,
        s.sfrstcr_term_code                         AS term_code,
        CASE WHEN sec.ssbsect_insm_code = 'DE' THEN 1 ELSE 0 END AS is_de_section,  -- >>> CUSTOMIZE code 'DE'
        s.sfrstcr_credit_hr                         AS credit_hr
    FROM   sfrstcr s
    JOIN   ssbsect sec
           ON  sec.ssbsect_term_code = s.sfrstcr_term_code
           AND sec.ssbsect_crn       = s.sfrstcr_crn
    WHERE  s.sfrstcr_term_code IN (SELECT term_code FROM relevant_terms)
    AND    s.sfrstcr_rsts_code IN ('RE')            -- >>> CUSTOMIZE
),
person_de AS (
    SELECT
        pidm,
        SUM(credit_hr)                                        AS total_hrs,
        SUM(CASE WHEN is_de_section = 1 THEN credit_hr ELSE 0 END) AS de_hrs
    FROM section_de
    GROUP BY pidm
),

/* ---------------------------------------------------------------------------
   5. STUDENT ACADEMIC RECORD SNAPSHOT (most-recent relevant term per person)
      SGBSTDN = general student table, one row per student per effective term.
      This picks the record effective as of the LAST relevant term the
      student was enrolled in, which drives level, degree-seeking,
      student type (HS/dual), and admit-type-based first-time/transfer flags.
   --------------------------------------------------------------------------- */
stdn_latest AS (
    SELECT g.*
    FROM   sgbstdn g
    JOIN  (
        SELECT sfrstcr_pidm AS pidm, MAX(sfrstcr_term_code) AS max_term
        FROM   sfrstcr
        WHERE  sfrstcr_term_code IN (SELECT term_code FROM relevant_terms)
        AND    sfrstcr_rsts_code IN ('RE')          -- >>> CUSTOMIZE
        GROUP BY sfrstcr_pidm
    ) m
    ON  g.sgbstdn_pidm = m.pidm
    AND g.sgbstdn_term_code_eff = (
            SELECT MAX(g2.sgbstdn_term_code_eff)
            FROM   sgbstdn g2
            WHERE  g2.sgbstdn_pidm = g.sgbstdn_pidm
            AND    g2.sgbstdn_term_code_eff <= m.max_term
        )
),

/* ---------------------------------------------------------------------------
   6. FULL/PART-TIME DETERMINATION FOR THE PERIOD
      >>> CUSTOMIZE the business rule: this version uses the student's
      MAXIMUM term credit load during the period and the level-appropriate
      threshold. Some schools instead use "status in census term with the
      most credits" -- adjust term_credit filtering above if so.
   --------------------------------------------------------------------------- */
person_ft AS (
    SELECT
        tc.pidm,
        MAX(tc.term_credit_hrs) AS max_term_hrs
    FROM term_credit tc
    GROUP BY tc.pidm
),

/* ---------------------------------------------------------------------------
   7. RACE / ETHNICITY  (mapped to IPEDS 1-9 codes)
      Standard Ellucian logic:
        1 Nonresident alien   -> citizenship/visa indicates non-US
        2 Hispanic/Latino     -> SPBPERS_ETHN_CDE / ethnicity ind = Hispanic
        3-7 single race       -> GORPRAC race codes
        8 Two or more races   -> multiple GORPRAC rows
        9 Unknown              -> no usable race/ethnicity data
      >>> CUSTOMIZE the SPBPERS_ETHN_CDE and GORPRAC_RACE_CDE values to
          match your institution's validation tables (STVETHN / STVRACE).
   --------------------------------------------------------------------------- */
race_counts AS (
    SELECT gorprac_pidm AS pidm, COUNT(DISTINCT gorprac_race_cde) AS race_ct
    FROM   gorprac
    GROUP BY gorprac_pidm
),
race_single AS (
    SELECT gorprac_pidm AS pidm, MIN(gorprac_race_cde) AS race_cde
    FROM   gorprac
    GROUP BY gorprac_pidm
    HAVING COUNT(DISTINCT gorprac_race_cde) = 1
),
person_race AS (
    SELECT
        p.spbpers_pidm AS pidm,
        CASE
            WHEN NVL(p.spbpers_citz_ind,'X') = 'N'                       THEN 1   -- >>> CUSTOMIZE nonresident alien flag
            WHEN NVL(p.spbpers_ethn_cde,'X') IN ('H','2')                THEN 2   -- >>> CUSTOMIZE Hispanic code(s)
            WHEN rc.race_ct > 1                                          THEN 8
            WHEN rs.race_cde = 'AI'                                      THEN 3   -- >>> CUSTOMIZE race codes below
            WHEN rs.race_cde = 'AS'                                      THEN 4
            WHEN rs.race_cde = 'BL'                                      THEN 5
            WHEN rs.race_cde = 'HP'                                      THEN 6
            WHEN rs.race_cde = 'WH'                                      THEN 7
            ELSE 9
        END AS race_ethnicity
    FROM   spbpers p
    LEFT JOIN race_counts rc ON rc.pidm = p.spbpers_pidm
    LEFT JOIN race_single  rs ON rs.pidm = p.spbpers_pidm
),

/* ---------------------------------------------------------------------------
   8. FINAL PERSON-LEVEL ASSEMBLY
   --------------------------------------------------------------------------- */
final AS (
    SELECT DISTINCT
        &unitid                                                        AS unitid,
        pr.spriden_id                                                  AS student_id,

        NVL(race.race_ethnicity, 9)                                    AS race_ethnicity,

        CASE UPPER(sp.spbpers_sex)
             WHEN 'M' THEN 1
             WHEN 'F' THEN 2
             ELSE 3
        END                                                             AS sex,

        CASE UPPER(sp.spbpers_sex)
             WHEN 'M' THEN 1
             WHEN 'F' THEN 2
             ELSE 3
        END                                                             AS gender_detail,

        CASE
            WHEN sl.sgbstdn_levl_code = 'UG'                                       -- >>> CUSTOMIZE level codes
                 AND pf.max_term_hrs >= &ft_threshold_ug THEN 1
            WHEN sl.sgbstdn_levl_code <> 'UG'
                 AND pf.max_term_hrs >= &ft_threshold_gr THEN 1
            ELSE 0
        END                                                             AS is_full_time,

        CASE WHEN sl.sgbstdn_styp_code IN ('N','F') THEN 1 ELSE 0 END   AS is_first_time,   -- >>> CUSTOMIZE
        CASE WHEN sl.sgbstdn_styp_code = 'T'         THEN 1 ELSE 0 END  AS is_transfer,     -- >>> CUSTOMIZE

        CASE WHEN sl.sgbstdn_styp_code IN ('S','N')  THEN 0 ELSE 1 END  AS is_degree_cert_seeking, -- >>> CUSTOMIZE

        CASE WHEN sl.sgbstdn_levl_code = 'UG' THEN 'Undergraduate'      -- >>> CUSTOMIZE level codes
             ELSE 'Graduate'
        END                                                             AS student_level,

        CASE WHEN sl.sgbstdn_styp_code = 'H' THEN 1 ELSE 0 END          AS is_high_school,   -- >>> CUSTOMIZE
        CASE WHEN sl.sgbstdn_styp_code = 'D' THEN 1 ELSE 0 END          AS is_dual,          -- >>> CUSTOMIZE

        CASE WHEN NVL(pd.total_hrs,0) > 0
                  AND pd.de_hrs = pd.total_hrs THEN 1 ELSE 0 END        AS distance_ed_all,
        CASE WHEN NVL(pd.total_hrs,0) > 0
                  AND pd.de_hrs > 0
                  AND pd.de_hrs < pd.total_hrs THEN 1 ELSE 0 END        AS distance_ed_some

    FROM   stdn_latest sl
    JOIN   spriden pr ON pr.spriden_pidm = sl.sgbstdn_pidm AND pr.spriden_change_ind IS NULL
    JOIN   spbpers sp ON sp.spbpers_pidm = sl.sgbstdn_pidm
    LEFT JOIN person_race race ON race.pidm = sl.sgbstdn_pidm
    LEFT JOIN person_ft   pf   ON pf.pidm   = sl.sgbstdn_pidm
    LEFT JOIN person_de   pd   ON pd.pidm   = sl.sgbstdn_pidm
)

SELECT
    unitid              AS "Unitid",
    student_id          AS "StudentId",
    race_ethnicity      AS "RaceEthnicity",
    sex                 AS "Sex",
    gender_detail       AS "GenderDetail",
    is_full_time        AS "IsFullTime",
    is_first_time       AS "IsFirstTime",
    is_transfer         AS "IsTransfer",
    is_degree_cert_seeking AS "IsDegreeCertSeeking",
    student_level       AS "StudentLevel",
    is_high_school      AS "IsHighSchool",
    is_dual             AS "IsDual",
    distance_ed_all     AS "DistanceEdAll",
    distance_ed_some    AS "DistanceEdSome"
FROM final
ORDER BY "StudentId";

SET MARKUP CSV OFF
SPOOL OFF

SET PAGESIZE 14
SET TERMOUT ON
SET FEEDBACK ON
PROMPT Enrollment extract written to &output_dir/e1d_enrollment.csv
EXIT
