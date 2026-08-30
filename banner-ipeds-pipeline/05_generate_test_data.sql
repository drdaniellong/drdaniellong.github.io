/* =============================================================================
   FAKE BANNER SCHEMA + 100-STUDENT TEST DATA GENERATOR
   =============================================================================
   Purpose: Build lightweight stand-ins for the Banner tables used by
     01_e1d_enrollment_extract.sql / 02_e1d_instructional_activity.sql
   and populate them with 100 fake students, so you can run the E1D
   extracts locally in SQLcl without a real Banner connection.

   IMPORTANT: This still requires an actual Oracle database that sqlcl can
   connect to (sqlcl is a client, not a database engine). If you don't
   already have one reachable from your Mac -- e.g. Oracle Database Free
   running locally in Docker, or a personal Oracle Cloud Free Tier / XE
   instance -- set that up first, then run this script against it:

       sql username/password@localhost:1521/freepdb1 @05_generate_test_data.sql

   WHAT THIS SCRIPT DOES
   ----------------------------------------------------------------------
   1. Drops the 16 tables involved, if they already exist (safe to rerun).
   2. Creates minimal versions of each table with only the columns the
      extract scripts actually reference.
   3. Loads validation-table rows using codes chosen to match the
      ">>> CUSTOMIZE" placeholder values already in 01/02, so those two
      scripts should run unmodified against this fake schema.
   4. Generates 100 fake students (PIDMs 500001-500100) with randomized
      but IPEDS-relevant attributes: sex, ethnicity, race, citizenship,
      level (UG/GR/DR), student type, and registrations across three
      terms spanning a 12-month reporting window.

   KNOWN SIMPLIFICATION -- WORTH YOUR ATTENTION
   ----------------------------------------------------------------------
   The IsDegreeCertSeeking placeholder in 01/02 excludes STYP codes
   ('S','N'), while IsFirstTime includes STYP codes ('N','F'). Code 'N'
   can't sensibly mean both "first-time" and "not degree-seeking" at a
   real institution, so this generator uses 'F' for first-time and
   never generates code 'N', to avoid baking a contradiction into your
   test run. When you customize the real extract for CCSU's actual STYP
   codes, revisit that overlap.
   ============================================================================= */

SET DEFINE OFF
WHENEVER SQLERROR CONTINUE

/* ---------------------------------------------------------------------------
   1. DROP TABLES IF THEY EXIST (safe to rerun this whole script)
   --------------------------------------------------------------------------- */
BEGIN
  FOR t IN (
      SELECT column_value AS table_name
      FROM   TABLE(SYS.ODCIVARCHAR2LIST(
                 'SFRSTCR','SSBSECT','SCBCRSE','SGBSTDN','GORPRAC',
                 'SPBPERS','SPRIDEN','STVTERM','STVSTYP','STVLEVL',
                 'STVETHN','STVRACE','STVCITZ','STVRSTS','GTVINSM','STVASTY'))
  ) LOOP
    BEGIN
      EXECUTE IMMEDIATE 'DROP TABLE ' || t.table_name || ' PURGE';
    EXCEPTION WHEN OTHERS THEN NULL; -- ignore "table does not exist"
    END;
  END LOOP;
END;
/

WHENEVER SQLERROR EXIT SQL.SQLCODE

/* ---------------------------------------------------------------------------
   2. CREATE TABLES  (minimal columns -- only what the extracts touch)
   --------------------------------------------------------------------------- */

-- Validation tables -----------------------------------------------------
CREATE TABLE stvterm (
    stvterm_code       VARCHAR2(6)  PRIMARY KEY,
    stvterm_desc       VARCHAR2(60),
    stvterm_start_date DATE,
    stvterm_end_date   DATE
);

CREATE TABLE stvstyp (
    stvstyp_code VARCHAR2(2) PRIMARY KEY,
    stvstyp_desc VARCHAR2(60)
);

CREATE TABLE stvlevl (
    stvlevl_code VARCHAR2(2) PRIMARY KEY,
    stvlevl_desc VARCHAR2(60)
);

CREATE TABLE stvethn (
    stvethn_code VARCHAR2(2) PRIMARY KEY,
    stvethn_desc VARCHAR2(60)
);

CREATE TABLE stvrace (
    stvrace_code VARCHAR2(2) PRIMARY KEY,
    stvrace_desc VARCHAR2(60)
);

CREATE TABLE stvcitz (
    stvcitz_code VARCHAR2(2) PRIMARY KEY,
    stvcitz_desc VARCHAR2(60)
);

CREATE TABLE stvrsts (
    stvrsts_code           VARCHAR2(2) PRIMARY KEY,
    stvrsts_desc           VARCHAR2(60),
    stvrsts_incl_sect_enrl VARCHAR2(1)
);

CREATE TABLE gtvinsm (
    gtvinsm_code VARCHAR2(4) PRIMARY KEY,
    gtvinsm_desc VARCHAR2(60)
);

CREATE TABLE stvasty (
    stvasty_code VARCHAR2(2) PRIMARY KEY,
    stvasty_desc VARCHAR2(60)
);

-- Person tables -----------------------------------------------------------
CREATE TABLE spriden (
    spriden_pidm        NUMBER PRIMARY KEY,
    spriden_id           VARCHAR2(9),
    spriden_last_name    VARCHAR2(30),
    spriden_first_name   VARCHAR2(30),
    spriden_change_ind   VARCHAR2(1)
);

CREATE TABLE spbpers (
    spbpers_pidm      NUMBER PRIMARY KEY,
    spbpers_sex       VARCHAR2(1),
    spbpers_ethn_cde  VARCHAR2(2),
    spbpers_citz_ind  VARCHAR2(2)
);

CREATE TABLE gorprac (
    gorprac_pidm     NUMBER,
    gorprac_race_cde VARCHAR2(2)
);

-- Academic / course tables -------------------------------------------------
CREATE TABLE sgbstdn (
    sgbstdn_pidm          NUMBER,
    sgbstdn_term_code_eff VARCHAR2(6),
    sgbstdn_levl_code     VARCHAR2(2),
    sgbstdn_styp_code     VARCHAR2(2),
    PRIMARY KEY (sgbstdn_pidm, sgbstdn_term_code_eff)
);

CREATE TABLE scbcrse (
    scbcrse_subj_code VARCHAR2(4),
    scbcrse_crse_numb VARCHAR2(5),
    scbcrse_levl_code VARCHAR2(2),
    scbcrse_title     VARCHAR2(60),
    PRIMARY KEY (scbcrse_subj_code, scbcrse_crse_numb)
);

CREATE TABLE ssbsect (
    ssbsect_term_code VARCHAR2(6),
    ssbsect_crn       VARCHAR2(5),
    ssbsect_subj_code VARCHAR2(4),
    ssbsect_crse_numb VARCHAR2(5),
    ssbsect_insm_code VARCHAR2(4),
    PRIMARY KEY (ssbsect_term_code, ssbsect_crn)
);

CREATE TABLE sfrstcr (
    sfrstcr_pidm       NUMBER,
    sfrstcr_term_code  VARCHAR2(6),
    sfrstcr_crn        VARCHAR2(5),
    sfrstcr_subj_code  VARCHAR2(4),
    sfrstcr_crse_numb  VARCHAR2(5),
    sfrstcr_credit_hr  NUMBER(4,1),
    sfrstcr_rsts_code  VARCHAR2(2),
    PRIMARY KEY (sfrstcr_pidm, sfrstcr_term_code, sfrstcr_crn)
);

/* ---------------------------------------------------------------------------
   3. VALIDATION TABLE DATA
      Codes deliberately match the ">>> CUSTOMIZE" placeholder values in
      01_e1d_enrollment_extract.sql / 02_e1d_instructional_activity.sql.
   --------------------------------------------------------------------------- */

-- Three terms spanning a 12-month IPEDS window (07/01/2025-06/30/2026)
INSERT INTO stvterm VALUES ('202530','Summer 2025', DATE '2025-06-02', DATE '2025-08-15');
INSERT INTO stvterm VALUES ('202510','Fall 2025',   DATE '2025-08-25', DATE '2025-12-19');
INSERT INTO stvterm VALUES ('202620','Spring 2026', DATE '2026-01-20', DATE '2026-05-15');

INSERT INTO stvstyp VALUES ('F','First-Time');
INSERT INTO stvstyp VALUES ('T','Transfer');
INSERT INTO stvstyp VALUES ('H','High School');
INSERT INTO stvstyp VALUES ('D','Dual Enrollment');
INSERT INTO stvstyp VALUES ('S','Special/Non-Degree');
INSERT INTO stvstyp VALUES ('C','Continuing');

INSERT INTO stvlevl VALUES ('UG','Undergraduate');
INSERT INTO stvlevl VALUES ('GR','Graduate');
INSERT INTO stvlevl VALUES ('DR','Doctoral/Professional Practice');

INSERT INTO stvethn VALUES ('H','Hispanic/Latino');
INSERT INTO stvethn VALUES ('N','Not Hispanic/Latino');

INSERT INTO stvrace VALUES ('AI','American Indian or Alaska Native');
INSERT INTO stvrace VALUES ('AS','Asian');
INSERT INTO stvrace VALUES ('BL','Black or African American');
INSERT INTO stvrace VALUES ('HP','Native Hawaiian or Other Pacific Islander');
INSERT INTO stvrace VALUES ('WH','White');

INSERT INTO stvcitz VALUES ('Y','US Citizen');
INSERT INTO stvcitz VALUES ('N','Nonresident Alien');

INSERT INTO stvrsts VALUES ('RE','Registered','Y');
INSERT INTO stvrsts VALUES ('DD','Dropped',   'N');
INSERT INTO stvrsts VALUES ('WD','Withdrawn', 'N');

INSERT INTO gtvinsm VALUES ('DE','Distance Education');
INSERT INTO gtvinsm VALUES ('TRAD','Traditional Classroom');

INSERT INTO stvasty VALUES ('N','New Freshman');
INSERT INTO stvasty VALUES ('T','Transfer');
INSERT INTO stvasty VALUES ('R','Readmit');

/* ---------------------------------------------------------------------------
   4. COURSE CATALOG
   --------------------------------------------------------------------------- */
INSERT INTO scbcrse VALUES ('ENG','101','UG','Freshman Composition');
INSERT INTO scbcrse VALUES ('MAT','120','UG','College Algebra');
INSERT INTO scbcrse VALUES ('HIS','150','UG','World History');
INSERT INTO scbcrse VALUES ('BIO','110','UG','Introductory Biology');
INSERT INTO scbcrse VALUES ('CSC','101','UG','Introduction to Computing');

INSERT INTO scbcrse VALUES ('MAT','501','GR','Advanced Statistics');
INSERT INTO scbcrse VALUES ('BUS','610','GR','Managerial Finance');
INSERT INTO scbcrse VALUES ('EDU','550','GR','Curriculum Design');
INSERT INTO scbcrse VALUES ('CSC','620','GR','Advanced Algorithms');
INSERT INTO scbcrse VALUES ('PSY','560','GR','Cognitive Psychology');

INSERT INTO scbcrse VALUES ('EDU','800','DR','Doctoral Seminar');
INSERT INTO scbcrse VALUES ('PSY','750','DR','Doctoral Research Methods');

COMMIT;

/* ---------------------------------------------------------------------------
   5. GENERATE 100 FAKE STUDENTS + REGISTRATIONS
      Seeded random values so the run is reproducible.
   --------------------------------------------------------------------------- */
SET SERVEROUTPUT ON
DECLARE
    v_pidm         NUMBER;
    v_id           VARCHAR2(9);
    v_sex          VARCHAR2(1);
    v_ethn         VARCHAR2(2);
    v_citz         VARCHAR2(2);
    v_levl         VARCHAR2(2);
    v_styp         VARCHAR2(2);
    v_term_eff     VARCHAR2(6) := '202510';  -- Fall 2025 = everyone's admit/effective term

    v_terms        SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST('202530','202510','202620');
    v_courses_ug   SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST('ENG-101','MAT-120','HIS-150','BIO-110','CSC-101');
    v_courses_gr   SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST('MAT-501','BUS-610','EDU-550','CSC-620','PSY-560');
    v_courses_dr   SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST('EDU-800','PSY-750');
    v_race_pool    SYS.ODCIVARCHAR2LIST := SYS.ODCIVARCHAR2LIST('AI','AS','BL','HP','WH');

    v_crn_seq      NUMBER := 10000;
    v_num_terms    NUMBER;
    v_num_courses  NUMBER;
    v_pool_size    NUMBER;
    v_credit_hr    NUMBER;
    v_subj         VARCHAR2(4);
    v_numb         VARCHAR2(5);
    v_dash         NUMBER;
    v_course_str   VARCHAR2(20);
    v_r            NUMBER;
BEGIN
    DBMS_RANDOM.SEED(20260826);

    FOR i IN 1..100 LOOP
        v_pidm := 500000 + i;
        v_id   := 'B' || LPAD(i, 8, '0');

        -- ---- Sex (2% unknown, to exercise the "Unknown -> 3" branch) ----
        v_r := DBMS_RANDOM.VALUE(0,1);
        IF v_r < 0.02 THEN
            v_sex := NULL;
        ELSIF v_r < 0.51 THEN
            v_sex := 'M';
        ELSE
            v_sex := 'F';
        END IF;

        -- ---- Citizenship / ethnicity ----
        v_r := DBMS_RANDOM.VALUE(0,1);
        IF v_r < 0.04 THEN
            v_citz := 'N';   -- nonresident alien (~4%)
            v_ethn := NULL;
        ELSIF v_r < 0.16 THEN
            v_citz := 'Y';
            v_ethn := 'H';   -- Hispanic/Latino (~12%)
        ELSE
            v_citz := 'Y';
            v_ethn := 'N';
        END IF;

        INSERT INTO spriden (spriden_pidm, spriden_id, spriden_last_name, spriden_first_name, spriden_change_ind)
        VALUES (v_pidm, v_id, 'LastName'||i, 'FirstName'||i, NULL);

        INSERT INTO spbpers (spbpers_pidm, spbpers_sex, spbpers_ethn_cde, spbpers_citz_ind)
        VALUES (v_pidm, v_sex, v_ethn, v_citz);

        -- ---- Race (only relevant when not already Hispanic/nonresident,
        --      but we populate GORPRAC regardless -- mirrors real Banner,
        --      where race and ethnicity are stored independently) ----
        IF DBMS_RANDOM.VALUE(0,1) < 0.10 THEN
            -- two or more races
            INSERT INTO gorprac VALUES (v_pidm, v_race_pool(TRUNC(DBMS_RANDOM.VALUE(1,6))));
            INSERT INTO gorprac VALUES (v_pidm, v_race_pool(TRUNC(DBMS_RANDOM.VALUE(1,6))));
        ELSE
            INSERT INTO gorprac VALUES (v_pidm, v_race_pool(TRUNC(DBMS_RANDOM.VALUE(1,6))));
        END IF;

        -- ---- Level: 70% UG / 25% GR / 5% DR ----
        v_r := DBMS_RANDOM.VALUE(0,1);
        IF v_r < 0.70 THEN
            v_levl := 'UG';
        ELSIF v_r < 0.95 THEN
            v_levl := 'GR';
        ELSE
            v_levl := 'DR';
        END IF;

        -- ---- Student type (see header note re: avoiding code 'N') ----
        v_r := DBMS_RANDOM.VALUE(0,1);
        IF v_r < 0.10 THEN v_styp := 'F';       -- first-time
        ELSIF v_r < 0.20 THEN v_styp := 'T';     -- transfer
        ELSIF v_r < 0.25 THEN v_styp := 'H';     -- high school
        ELSIF v_r < 0.30 THEN v_styp := 'D';     -- dual enrollment
        ELSIF v_r < 0.35 THEN v_styp := 'S';     -- special/non-degree
        ELSE v_styp := 'C'; END IF;              -- continuing

        INSERT INTO sgbstdn (sgbstdn_pidm, sgbstdn_term_code_eff, sgbstdn_levl_code, sgbstdn_styp_code)
        VALUES (v_pidm, v_term_eff, v_levl, v_styp);

        -- ---- Registrations across 1-3 terms ----
        v_num_terms := TRUNC(DBMS_RANDOM.VALUE(1,4));

        FOR t IN 1..v_num_terms LOOP

            -- pick a course pool + per-course credit weight by level
            IF v_levl = 'UG' THEN
                v_pool_size := v_courses_ug.COUNT;
                v_credit_hr := 3;
            ELSIF v_levl = 'GR' THEN
                v_pool_size := v_courses_gr.COUNT;
                v_credit_hr := 3;
            ELSE
                v_pool_size := v_courses_dr.COUNT;
                v_credit_hr := 4.5;
            END IF;

            -- ~60% full-time course load, ~40% part-time
            IF DBMS_RANDOM.VALUE(0,1) < 0.6 THEN
                v_num_courses := LEAST(v_pool_size, CASE WHEN v_levl='UG' THEN 4 ELSE 2 END);
            ELSE
                v_num_courses := LEAST(v_pool_size, CASE WHEN v_levl='UG' THEN 2 ELSE 1 END);
            END IF;

            FOR c IN 1..v_num_courses LOOP
                IF v_levl = 'UG' THEN
                    v_course_str := v_courses_ug(c);
                ELSIF v_levl = 'GR' THEN
                    v_course_str := v_courses_gr(c);
                ELSE
                    v_course_str := v_courses_dr(c);
                END IF;

                v_dash := INSTR(v_course_str, '-');
                v_subj := SUBSTR(v_course_str, 1, v_dash - 1);
                v_numb := SUBSTR(v_course_str, v_dash + 1);

                v_crn_seq := v_crn_seq + 1;

                INSERT INTO ssbsect (ssbsect_term_code, ssbsect_crn, ssbsect_subj_code, ssbsect_crse_numb, ssbsect_insm_code)
                VALUES (v_terms(t), TO_CHAR(v_crn_seq), v_subj, v_numb,
                        CASE WHEN DBMS_RANDOM.VALUE(0,1) < 0.3 THEN 'DE' ELSE 'TRAD' END);

                INSERT INTO sfrstcr (sfrstcr_pidm, sfrstcr_term_code, sfrstcr_crn, sfrstcr_subj_code, sfrstcr_crse_numb, sfrstcr_credit_hr, sfrstcr_rsts_code)
                VALUES (v_pidm, v_terms(t), TO_CHAR(v_crn_seq), v_subj, v_numb, v_credit_hr, 'RE');
            END LOOP;
        END LOOP;

    END LOOP;

    COMMIT;
    DBMS_OUTPUT.PUT_LINE('Generated 100 fake students with registrations across 3 terms.');
END;
/

/* ---------------------------------------------------------------------------
   6. QUICK SANITY CHECKS
   --------------------------------------------------------------------------- */
SELECT 'spriden' AS tbl, COUNT(*) AS rows_ FROM spriden
UNION ALL SELECT 'spbpers', COUNT(*) FROM spbpers
UNION ALL SELECT 'gorprac', COUNT(*) FROM gorprac
UNION ALL SELECT 'sgbstdn', COUNT(*) FROM sgbstdn
UNION ALL SELECT 'scbcrse', COUNT(*) FROM scbcrse
UNION ALL SELECT 'ssbsect', COUNT(*) FROM ssbsect
UNION ALL SELECT 'sfrstcr', COUNT(*) FROM sfrstcr
UNION ALL SELECT 'stvterm', COUNT(*) FROM stvterm;

SELECT sgbstdn_levl_code, sgbstdn_styp_code, COUNT(*) AS student_count
FROM   sgbstdn
GROUP BY sgbstdn_levl_code, sgbstdn_styp_code
ORDER BY 1,2;

PROMPT Test schema and data generation complete.
PROMPT Now run 01_e1d_enrollment_extract.sql and 02_e1d_instructional_activity.sql
PROMPT against this same connection (adjust &output_dir to a local folder first).
