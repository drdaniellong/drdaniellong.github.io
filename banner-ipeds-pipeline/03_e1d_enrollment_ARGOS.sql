/* =============================================================================
   IPEDS 12-MONTH ENROLLMENT (E1D) -- STUDENT ENROLLMENT EXTRACT
   ARGOS DATABLOCK VERSION (plain SELECT + Oracle bind parameters)
   =============================================================================
   Use this version as the SQL for an Argos DataBlock, feeding an Argos
   EXTRACT object with CSV output. See README_ARGOS.md for the click-path.

   Argos will auto-detect the :bind variables below the first time you save
   this DataBlock and let you configure each as a parameter (data type,
   prompt label, default value, and whether to prompt the user or hide it).
   Recommended parameter setup:
     :unitid          NUMBER   default 999999 (your real Unitid), hidden
     :period_start    DATE     default period start, hidden or prompted
     :period_end      DATE     default period end, hidden or prompted
     :ft_threshold_ug NUMBER   default 12, hidden
     :ft_threshold_gr NUMBER   default 9,  hidden

   Every ">>> CUSTOMIZE" spot must be updated with CCSU's actual Banner
   validation-table codes -- run 00_code_discovery.sql first to find them.
   ============================================================================= */

WITH

relevant_terms AS (
    SELECT stvterm_code AS term_code
    FROM   stvterm
    WHERE  stvterm_start_date <= :period_end
    AND    stvterm_end_date   >= :period_start
),

term_credit AS (
    SELECT
        s.sfrstcr_pidm      AS pidm,
        s.sfrstcr_term_code AS term_code,
        SUM(s.sfrstcr_credit_hr) AS term_credit_hrs
    FROM   sfrstcr s
    WHERE  s.sfrstcr_term_code IN (SELECT term_code FROM relevant_terms)
    AND    s.sfrstcr_rsts_code IN ('RE')             -- >>> CUSTOMIZE registration status code(s)
    GROUP BY s.sfrstcr_pidm, s.sfrstcr_term_code
),

section_de AS (
    SELECT
        s.sfrstcr_pidm      AS pidm,
        s.sfrstcr_term_code AS term_code,
        CASE WHEN sec.ssbsect_insm_code = 'DE' THEN 1 ELSE 0 END AS is_de_section, -- >>> CUSTOMIZE
        s.sfrstcr_credit_hr AS credit_hr
    FROM   sfrstcr s
    JOIN   ssbsect sec
           ON  sec.ssbsect_term_code = s.sfrstcr_term_code
           AND sec.ssbsect_crn       = s.sfrstcr_crn
    WHERE  s.sfrstcr_term_code IN (SELECT term_code FROM relevant_terms)
    AND    s.sfrstcr_rsts_code IN ('RE')             -- >>> CUSTOMIZE
),
person_de AS (
    SELECT
        pidm,
        SUM(credit_hr) AS total_hrs,
        SUM(CASE WHEN is_de_section = 1 THEN credit_hr ELSE 0 END) AS de_hrs
    FROM section_de
    GROUP BY pidm
),

stdn_latest AS (
    SELECT g.*
    FROM   sgbstdn g
    JOIN  (
        SELECT sfrstcr_pidm AS pidm, MAX(sfrstcr_term_code) AS max_term
        FROM   sfrstcr
        WHERE  sfrstcr_term_code IN (SELECT term_code FROM relevant_terms)
        AND    sfrstcr_rsts_code IN ('RE')           -- >>> CUSTOMIZE
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

person_ft AS (
    SELECT pidm, MAX(term_credit_hrs) AS max_term_hrs
    FROM   term_credit
    GROUP BY pidm
),

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
            WHEN NVL(p.spbpers_citz_ind,'X') = 'N'        THEN 1  -- >>> CUSTOMIZE
            WHEN NVL(p.spbpers_ethn_cde,'X') IN ('H','2') THEN 2  -- >>> CUSTOMIZE
            WHEN rc.race_ct > 1                            THEN 8
            WHEN rs.race_cde = 'AI'                        THEN 3  -- >>> CUSTOMIZE
            WHEN rs.race_cde = 'AS'                        THEN 4
            WHEN rs.race_cde = 'BL'                        THEN 5
            WHEN rs.race_cde = 'HP'                        THEN 6
            WHEN rs.race_cde = 'WH'                        THEN 7
            ELSE 9
        END AS race_ethnicity
    FROM   spbpers p
    LEFT JOIN race_counts rc ON rc.pidm = p.spbpers_pidm
    LEFT JOIN race_single  rs ON rs.pidm = p.spbpers_pidm
)

SELECT DISTINCT
    :unitid                                                        AS "Unitid",
    pr.spriden_id                                                  AS "StudentId",

    NVL(race.race_ethnicity, 9)                                    AS "RaceEthnicity",

    CASE UPPER(sp.spbpers_sex) WHEN 'M' THEN 1 WHEN 'F' THEN 2 ELSE 3 END AS "Sex",
    CASE UPPER(sp.spbpers_sex) WHEN 'M' THEN 1 WHEN 'F' THEN 2 ELSE 3 END AS "GenderDetail",

    CASE
        WHEN sl.sgbstdn_levl_code = 'UG' AND pf.max_term_hrs >= :ft_threshold_ug THEN 1  -- >>> CUSTOMIZE
        WHEN sl.sgbstdn_levl_code <> 'UG' AND pf.max_term_hrs >= :ft_threshold_gr THEN 1
        ELSE 0
    END                                                             AS "IsFullTime",

    CASE WHEN sl.sgbstdn_styp_code IN ('N','F') THEN 1 ELSE 0 END   AS "IsFirstTime",   -- >>> CUSTOMIZE
    CASE WHEN sl.sgbstdn_styp_code = 'T'         THEN 1 ELSE 0 END  AS "IsTransfer",     -- >>> CUSTOMIZE
    CASE WHEN sl.sgbstdn_styp_code IN ('S','N')  THEN 0 ELSE 1 END  AS "IsDegreeCertSeeking", -- >>> CUSTOMIZE

    CASE WHEN sl.sgbstdn_levl_code = 'UG' THEN 'Undergraduate' ELSE 'Graduate' END        AS "StudentLevel", -- >>> CUSTOMIZE

    CASE WHEN sl.sgbstdn_styp_code = 'H' THEN 1 ELSE 0 END          AS "IsHighSchool",   -- >>> CUSTOMIZE
    CASE WHEN sl.sgbstdn_styp_code = 'D' THEN 1 ELSE 0 END          AS "IsDual",         -- >>> CUSTOMIZE

    CASE WHEN NVL(pd.total_hrs,0) > 0 AND pd.de_hrs = pd.total_hrs THEN 1 ELSE 0 END      AS "DistanceEdAll",
    CASE WHEN NVL(pd.total_hrs,0) > 0 AND pd.de_hrs > 0 AND pd.de_hrs < pd.total_hrs
         THEN 1 ELSE 0 END                                                                AS "DistanceEdSome"

FROM   stdn_latest sl
JOIN   spriden pr ON pr.spriden_pidm = sl.sgbstdn_pidm AND pr.spriden_change_ind IS NULL
JOIN   spbpers sp ON sp.spbpers_pidm = sl.sgbstdn_pidm
LEFT JOIN person_race race ON race.pidm = sl.sgbstdn_pidm
LEFT JOIN person_ft   pf   ON pf.pidm   = sl.sgbstdn_pidm
LEFT JOIN person_de   pd   ON pd.pidm   = sl.sgbstdn_pidm
ORDER BY "StudentId"
