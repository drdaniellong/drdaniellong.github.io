/* =============================================================================
   BANNER VALIDATION-TABLE CODE DISCOVERY
   =============================================================================
   Purpose: Find YOUR institution's actual code values so you can fill in
   every ">>> CUSTOMIZE" spot in the E1D enrollment / instructional-activity
   extracts. Run this once (in SQL*Plus, SQLcl, or as an ad-hoc Argos
   DataBlock) against your Banner schema and review the output with your
   registrar/IR office -- these values are configured locally and I can't
   know them in advance.
   ============================================================================= */

-- Student type codes (drives IsFirstTime / IsTransfer / IsDegreeCertSeeking /
-- IsHighSchool / IsDual in the enrollment extract)
SELECT stvstyp_code, stvstyp_desc
FROM   stvstyp
ORDER  BY stvstyp_code;

-- Student level codes (drives StudentLevel + doctoral/professional split)
SELECT stvlevl_code, stvlevl_desc
FROM   stvlevl
ORDER  BY stvlevl_code;

-- Ethnicity codes (Hispanic/Latino indicator)
SELECT stvethn_code, stvethn_desc
FROM   stvethn
ORDER  BY stvethn_code;

-- Race codes (used with GORPRAC for multi-race / single-race mapping)
SELECT stvrace_code, stvrace_desc
FROM   stvrace
ORDER  BY stvrace_code;

-- Citizenship type codes (used to help identify nonresident alien status)
SELECT stvcitz_code, stvcitz_desc
FROM   stvcitz
ORDER  BY stvcitz_code;

-- Registration status codes (which ones mean "still enrolled" vs
-- dropped/cancelled/withdrawn -- drives every SFRSTCR filter)
SELECT stvrsts_code, stvrsts_desc, stvrsts_incl_sect_enrl
FROM   stvrsts
ORDER  BY stvrsts_code;

-- Instructional method codes (drives DistanceEdAll / DistanceEdSome)
SELECT gtvinsm_code, gtvinsm_desc
FROM   gtvinsm
ORDER  BY gtvinsm_code;

-- Admission type codes (sometimes a better source of truth than STYP for
-- first-time vs transfer than SGBSTDN_STYP_CODE alone)
SELECT stvasty_code, stvasty_desc
FROM   stvasty
ORDER  BY stvasty_code;

-- Sanity check: how many DISTINCT levl codes actually have registrations
-- in a recent term, and roughly how many credit hours are at each level.
-- Swap in a real term code before running.
-- SELECT sc.scbcrse_levl_code, COUNT(*), SUM(s.sfrstcr_credit_hr)
-- FROM   sfrstcr s
-- JOIN   scbcrse sc ON sc.scbcrse_subj_code = s.sfrstcr_subj_code
--                   AND sc.scbcrse_crse_numb = s.sfrstcr_crse_numb
-- WHERE  s.sfrstcr_term_code = 'XXXXXX'
-- GROUP BY sc.scbcrse_levl_code;
