-- DROP PROCEDURE sourcemaster.cmuupload(varchar);

CREATE OR REPLACE PROCEDURE sourcemaster.cmuupload(IN filename1 character varying)
 LANGUAGE plpgsql
AS $procedure$
DECLARE
    v_code TEXT;
    v_err TEXT;
    v_bad_count INTEGER := 0;
    v_good_count INTEGER := 0;
    v_ctr INTEGER := 0;
    v_filename VARCHAR := filename1;
    rec RECORD;
 rec_existing RECORD;
    -- Cursor for looping through the table
    C1 CURSOR FOR SELECT * FROM sourcemaster.MARK_CASES_CMU;
BEGIN
    -- Log start of procedure
    RAISE NOTICE 'Starting cmuupload with filename: %', v_filename;
    -- Delete unwanted header/footer records
    RAISE NOTICE 'Deleting HEADER/FOOTER records from MARK_CASES_CMU';
    DELETE FROM sourcemaster.MARK_CASES_CMU WHERE FINANCIER_ID LIKE 'HEADER%' OR FINANCIER_ID LIKE 'FOOTER%';
    GET DIAGNOSTICS v_ctr = ROW_COUNT;
    RAISE NOTICE 'Deleted % HEADER/FOOTER records', v_ctr;
  -- Remove duplicate records
    RAISE NOTICE 'Removing duplicate records from MARK_CASES_CMU';
    DELETE FROM sourcemaster.MARK_CASES_CMU
    WHERE ctid NOT IN (
        SELECT MAX(ctid)
        FROM sourcemaster.MARK_CASES_CMU
        GROUP BY financier_id, appl_id, cust_id, product_id, reason_code, marking_code, makedate
    );
    GET DIAGNOSTICS v_ctr = ROW_COUNT;
    RAISE NOTICE 'Deleted % duplicate records', v_ctr;
    -- Update records
    ------------------------------------------------------------------
    -- Update awal pada table MARK_CASES_CMU
    -- Set STATUS_FLAG ke 'N', MAKEDATE dan MAKERID jika NULL
    UPDATE sourcemaster.mark_cases_cmu
    SET status_flag = 'N',
        makedate   = COALESCE(makedate, now()),
        makerid    = COALESCE(makerid, 'upload_sys');
 
-- 2. Validasi cust_id di cs_case_info
--    Masukkan ke tabel reject jika cust_id tidak ditemukan
INSERT INTO sourcemaster.mark_cases_reject_reason (
    financier_id, appl_id, cust_id, product_id, reason_code, remarks, marking_code, reason, datetime, filename
)
SELECT A.FINANCIER_ID, A.APPL_ID, A.CUST_ID, A.PRODUCT_ID, A.REASON_CODE, A.REMARKS, A.MARKING_CODE, 'CUST ID IS NOT FOUND ON CS CASE INFO', NOW(), v_filename
FROM sourcemaster.mark_cases_cmu A
WHERE NOT EXISTS (SELECT 1 from public.cs_case_info cci WHERE cci.cust_id = A.cust_id);

 
UPDATE sourcemaster.mark_cases_cmu A
SET status_flag = 'E'
FROM cs_case_info sub
WHERE A.financier_id = sub.financier_id
  AND A.cust_id = sub.cust_id
  AND sub.cust_id IS NULL
  AND A.status_flag = 'N';
 
-- 3. Validasi appl_id di cs_case_info
--    Masukkan ke tabel reject jika appl_id tidak ditemukan
INSERT INTO sourcemaster.mark_cases_reject_reason (
    financier_id, appl_id, cust_id, product_id, reason_code, remarks, marking_code, reason, datetime, filename
)
SELECT A.FINANCIER_ID, A.APPL_ID, A.CUST_ID, A.PRODUCT_ID, A.REASON_CODE, A.REMARKS, A.MARKING_CODE, 'APPL ID IS NOT FOUND ON CS CASE INFO', NOW(), v_filename
FROM sourcemaster.mark_cases_cmu A
WHERE NOT EXISTS (SELECT 1 from public.cs_case_info cci WHERE cci.appl_id = A.appl_id);
 
-- Update status_flag menjadi 'E' untuk appl_id yang tidak valid
UPDATE sourcemaster.mark_cases_cmu A
SET status_flag = 'E'
FROM cs_case_info sub
WHERE A.financier_id = sub.financier_id
  AND A.appl_id = sub.appl_id
  AND sub.appl_id IS NULL
  AND A.status_flag = 'N';
 
-- 4. Validasi financier_id di financier_master
--    Masukkan ke tabel reject jika financier_id tidak ditemukan
INSERT INTO sourcemaster.mark_cases_reject_reason (
    financier_id, appl_id, cust_id, product_id, reason_code, remarks, marking_code, reason, datetime, filename
)
SELECT A.FINANCIER_ID, A.APPL_ID, A.CUST_ID, A.PRODUCT_ID, A.REASON_CODE, A.REMARKS, A.MARKING_CODE, 'FINANCIER ID IS NOT FOUND', NOW(), v_filename
FROM sourcemaster.mark_cases_cmu A
WHERE NOT EXISTS (SELECT 1 from sourcemaster.financier_master fm WHERE fm.financier_id = A.financier_id);
UPDATE sourcemaster.mark_cases_cmu A
SET status_flag = 'E'
FROM sourcemaster.financier_master fm
WHERE A.financier_id <> fm.financier_id
  AND A.status_flag = 'N';
 
    -- Update S_APPL_ID, S_CUST_ID, S_PRODUCT_TYPE dari CS_CASE_INFO
   -- 1. Update status_flag, makedate, dan makerid
UPDATE sourcemaster.mark_cases_cmu
SET status_flag = 'N',
    makedate   = COALESCE(makedate, now()),
    makerid    = COALESCE(makerid, 'upload_sys');
-- 2. Update S_APPL_ID, S_CUST_ID, S_PRODUCT_TYPE dari CS_CASE_INFO
--    dan masukkan ke tabel reject jika tidak ditemukan
    UPDATE sourcemaster.mark_cases_cmu A
    SET s_appl_id      = sub.appl_id,
        s_cust_id      = sub.cust_id,
  s_financier_id = sub.financier_id
    FROM cs_case_info sub
    WHERE A.financier_id = sub.financier_id
      AND A.appl_id      = sub.appl_id
      AND A.cust_id      = sub.cust_id;

-- 3. Update S_PRODUCT_ID dari CS_CASE_INFO
--    dan masukkan ke tabel reject jika tidak ditemukan
WITH updated AS (
    UPDATE sourcemaster.mark_cases_cmu A
    SET s_product_id = sub.product_id
    FROM cs_case_info sub
    WHERE A.appl_id      = sub.appl_id
      AND A.cust_id      = sub.cust_id
      AND A.product_id   = sub.product_id
    RETURNING A.financier_id, A.appl_id, A.cust_id, A.product_id
)
INSERT INTO sourcemaster.mark_cases_reject_reason (
    financier_id, appl_id, cust_id, product_id, reason_code, remarks, marking_code, reason, datetime, filename
)
    SELECT A.FINANCIER_ID, A.APPL_ID, A.CUST_ID, A.PRODUCT_ID, A.REASON_CODE, A.REMARKS, A.MARKING_CODE, 'INVALID PRODUCT ID', NOW(), v_filename
FROM sourcemaster.mark_cases_cmu A
JOIN cs_case_info sub
    ON A.financier_id = sub.financier_id
    AND A.appl_id = sub.appl_id
    AND A.cust_id = sub.cust_id
WHERE sub.product_id <> A.product_id
  AND A.status_flag = 'N';

WITH updated AS (
        UPDATE sourcemaster.mark_cases_cmu a
        SET s_appl_id = sub.appl_id,
            s_cust_id = sub.cust_id,
            s_product_type = sub.product_type
        FROM cs_case_info sub
        WHERE a.financier_id = sub.financier_id
          AND a.appl_id = sub.appl_id
          AND a.cust_id = sub.cust_id
        RETURNING a.financier_id, a.appl_id, a.cust_id, a.product_id
    )
    INSERT INTO sourcemaster.mark_cases_reject_reason (
        financier_id, appl_id, cust_id, product_id, reason_code, remarks, marking_code, reason, datetime, filename
    )
    SELECT 
        a.financier_id, a.appl_id, a.cust_id, a.product_id, a.reason_code, a.remarks, a.marking_code,
        'INVALID COMBINATION DATA OF APPL ID, CUST ID, FINANCIER ID', NOW(), v_filename
    FROM sourcemaster.mark_cases_cmu a
    LEFT JOIN cs_case_info sub ON a.financier_id = sub.financier_id
        AND a.appl_id = sub.appl_id
        AND a.cust_id = sub.cust_id
    WHERE sub.financier_id IS NULL AND a.status_flag = 'N';

 
    -- Update S_MARKING_CODE dari sourcemaster.company_generic (asumsikan satu nilai)
--    UPDATE sourcemaster.mark_cases_cmu A
--    SET s_marking_code = (
--        SELECT keys FROM sourcemaster.company_generic WHERE keys = A.marking_code LIMIT 1
--    );
    -- Update S_REASON_CODE dari sourcemaster.company_generic (menggunakan nilai dan kunci)
--    UPDATE sourcemaster.mark_cases_cmu A
--    SET s_reason_code = (
--        SELECT values FROM sourcemaster.company_generic
--         WHERE values = A.reason_code AND keys = A.s_marking_code LIMIT 1
--    );
    -- Update S_REASON_DESC dari sourcemaster.company_generic
UPDATE sourcemaster.mark_cases_cmu A
SET s_reason_desc = CASE 
    WHEN A.marking_code = 'CHARGEOFF' THEN
        (SELECT mcr.mcr_description 
         FROM param.master_charge_reason mcr
         WHERE mcr.mcr_code = A.reason_code)
    WHEN A.marking_code = 'DELQREAS' THEN
        (SELECT mdr.mdr_description 
         FROM param.master_delinquency_reason mdr
         WHERE mdr.mdr_code = A.reason_code)
    WHEN A.marking_code = 'SPLCAT' THEN
        (SELECT msc.msc_description 
         FROM param.master_special_category msc
         WHERE msc.msc_code = A.reason_code)
    WHEN A.marking_code = 'RECOVERY' THEN
        (SELECT dp.ddl_description 
         FROM param.ddl_param dp 
         WHERE dp.ddlt_id = '7'
         AND dp.ddl_code = A.reason_code)
    ELSE s_reason_desc
END;

    -- Validasi wajib: jika ada field penting yang kosong, set REASON dan STATUS_FLAG = 'E'
    UPDATE sourcemaster.mark_cases_cmu
    SET reason      = 'FINANCIER FIELDS CAN NOT BE NULL',
        status_flag = 'E',
        filename    = v_filename
    WHERE (financier_id = '' OR financier_id IS NULL)
      AND status_flag = 'N';
    UPDATE sourcemaster.mark_cases_cmu
    SET reason      = 'CUST ID FIELDS CAN NOT BE NULL',
        status_flag = 'E',
        filename    = v_filename
    WHERE (cust_id = '' OR cust_id IS NULL)
      AND status_flag = 'N';
    UPDATE sourcemaster.mark_cases_cmu
    SET reason      = 'APPL ID FIELDS CAN NOT BE NULL',
        status_flag = 'E',
        filename    = v_filename
    WHERE (appl_id  = '' OR appl_id IS NULL)
      AND status_flag = 'N';
    UPDATE sourcemaster.mark_cases_cmu
    SET reason      = 'PRODUCT ID FIELDS CAN NOT BE NULL',
        status_flag = 'E',
        filename    = v_filename
    WHERE (product_id = '' OR product_id IS NULL)
      AND status_flag = 'N';
    UPDATE sourcemaster.mark_cases_cmu
    SET reason      = 'REASON CODE FIELDS CAN NOT BE NULL',
        status_flag = 'E',
        filename    = v_filename
    WHERE (reason_code  = '' OR reason_code IS NULL)
      AND status_flag = 'N';
    UPDATE sourcemaster.mark_cases_cmu
    SET reason      = 'MARKING CODE FIELDS CAN NOT BE NULL',
        status_flag = 'E',
        filename    = v_filename
    WHERE (marking_code = '' OR marking_code IS NULL)
      AND status_flag = 'N';
--    UPDATE sourcemaster.mark_cases_cmu
--    SET reason      = 'FINANCIER ID IS WRONG OR NOT EXIST IN THE SYSTEM',
--        status_flag = 'E',
--        filename    = v_filename
--    WHERE s_financier_id IS NULL AND status_flag = 'N';
 
     INSERT INTO SOURCEMASTER.MARK_CASES_REJECT_REASON (FINANCIER_ID, APPL_ID, CUST_ID, PRODUCT_ID, REASON_CODE, REMARKS, MARKING_CODE, REASON, DATETIME, FILENAME)
     SELECT FINANCIER_ID, APPL_ID, CUST_ID, PRODUCT_ID, REASON_CODE, REMARKS, MARKING_CODE, REASON, NOW(), FILENAME
     FROM SOURCEMASTER.MARK_CASES_CMU WHERE STATUS_FLAG = 'E';
 
    UPDATE sourcemaster.mark_cases_cmu
    SET reason      = 'S_APPLICATION IS NOT CORRECT',
        status_flag = 'E',
        filename    = v_filename
    WHERE (s_appl_id IS NULL)
      AND status_flag = 'N';
    UPDATE sourcemaster.mark_cases_cmu
    SET reason      = 'S_CUSTOMER ID IS NOT CORRECT',
        status_flag = 'E',
        filename    = v_filename
    WHERE (s_cust_id IS NULL)
      AND status_flag = 'N';
    UPDATE sourcemaster.mark_cases_cmu
    SET reason      = 'PRODUCT ID IS NOT CORRECT',
        status_flag = 'E',
        filename    = v_filename
    WHERE s_product_id IS NULL AND status_flag = 'N';
--    UPDATE sourcemaster.mark_cases_cmu
--    SET reason      = 'MARKING CODE IS NOT CORRECT',
--        status_flag = 'E',
--        filename    = v_filename
--    WHERE s_marking_code IS NULL AND status_flag = 'N';
--    UPDATE sourcemaster.mark_cases_cmu
--    SET reason      = 'REASON CODE IS NOT CORRECT',
--        status_flag = 'E',
--        filename    = v_filename
--    WHERE s_reason_code IS NULL AND status_flag = 'N';
    UPDATE sourcemaster.mark_cases_cmu
    SET reason      = 'REASON DESCRIPTION IS NOT CORRECT',
        status_flag = 'E',
        filename    = v_filename
    WHERE s_reason_desc IS NULL AND status_flag = 'N';
 
     INSERT INTO SOURCEMASTER.MARK_CASES_REJECT_REASON (FINANCIER_ID, APPL_ID, CUST_ID, PRODUCT_ID, REASON_CODE, REMARKS, MARKING_CODE, REASON, DATETIME, FILENAME)
     SELECT FINANCIER_ID, APPL_ID, CUST_ID, PRODUCT_ID, REASON_CODE, REMARKS, MARKING_CODE, REASON, NOW(), FILENAME
     FROM SOURCEMASTER.MARK_CASES_CMU WHERE s_reason_desc IS NULL;
-- OR s_reason_code IS NULL
-- OR s_marking_code IS NULL
-- OR s_product_id IS NULL
-- OR s_financier_id IS NULL
-- OR s_cust_id IS NULL
-- OR s_appl_id IS NULL;
 
    -- Set mark_update = 'Y' bila sudah ada record di MARK_CASES (asumsi logika sederhana)
  UPDATE sourcemaster.mark_cases_cmu A
    SET mark_update = 'Y'
    WHERE status_flag = 'N'
      AND EXISTS (
         SELECT 1 FROM sourcemaster.mark_cases
         WHERE marking_code = A.marking_code
           AND appl_id      = A.appl_id
           AND cust_id      = A.cust_id
           AND financier_id = A.financier_id
      );
    -- Open cursor and process records
    RAISE NOTICE 'Opening cursor C1 to process MARK_CASES_CMU records';
    FOR rec IN
    SELECT * FROM sourcemaster.mark_cases_cmu WHERE status_flag = 'N'
    LOOP
        RAISE NOTICE 'Processing record: financier_id=%, appl_id=%, cust_id=%, product_id=%, reason_code=%, marking_code=%',
                     rec.FINANCIER_ID, rec.APPL_ID, rec.CUST_ID, rec.PRODUCT_ID, rec.REASON_CODE, rec.MARKING_CODE;
        BEGIN
            IF COALESCE(rec.MARK_UPDATE, 'N') <> 'Y' THEN
                RAISE NOTICE 'Inserting new record into MARK_CASES for financier_id=%, appl_id=%, cust_id=%',
                             rec.FINANCIER_ID, rec.APPL_ID, rec.CUST_ID;
                INSERT INTO sourcemaster.MARK_CASES (MARK_ID, FINANCIER_ID, APPL_ID, CUST_ID, PRODUCT_ID, PRODUCT_TYPE, REASON_CODE, REASON_DESC, REMARKS, MAKERID, MAKEDATE, MARKING_CODE)
                VALUES (nextval('sourcemaster.mark_cases_seq'::regclass),
                        rec.FINANCIER_ID, rec.APPL_ID, rec.CUST_ID, rec.PRODUCT_ID,
                        rec.S_PRODUCT_TYPE, TRIM(rec.REASON_CODE), TRIM(rec.S_REASON_DESC),
                        TRIM(rec.REMARKS), TRIM(rec.MAKERID), NOW(), TRIM(rec.MARKING_CODE));
                RAISE NOTICE 'Successfully inserted record into MARK_CASES';
                v_good_count := v_good_count + 1;
            ELSIF rec.MARK_UPDATE = 'Y' THEN
                RAISE NOTICE 'Archiving existing record to MARK_CASES_HST and updating MARK_CASES for financier_id=%, appl_id=%, cust_id=%, marking_code=%',
                             rec.FINANCIER_ID, rec.APPL_ID, rec.CUST_ID, rec.MARKING_CODE;
                -- Fetch the existing record from MARK_CASES
                SELECT * INTO rec_existing
                FROM sourcemaster.MARK_CASES
                WHERE APPL_ID = rec.APPL_ID
                  AND CUST_ID = rec.CUST_ID
                  AND FINANCIER_ID = rec.FINANCIER_ID
                  AND MARKING_CODE = rec.MARKING_CODE;
 
                IF FOUND THEN
                    -- Insert the existing (old) record into HST with a new MARK_ID
                    INSERT INTO sourcemaster.MARK_CASES_HST (MARK_ID, FINANCIER_ID, APPL_ID, CUST_ID, PRODUCT_ID, PRODUCT_TYPE, REASON_CODE, REASON_DESC, REMARKS, MAKERID, MAKEDATE, MARKING_CODE)
                    VALUES (nextval('sourcemaster.mark_cases_seq'::regclass),
                            rec_existing.FINANCIER_ID, rec_existing.APPL_ID, rec_existing.CUST_ID, rec_existing.PRODUCT_ID,
                            rec_existing.PRODUCT_TYPE, rec_existing.REASON_CODE, rec_existing.REASON_DESC,
                            rec_existing.REMARKS, rec_existing.MAKERID, rec_existing.MAKEDATE, rec_existing.MARKING_CODE);
                    RAISE NOTICE 'Successfully inserted old record into MARK_CASES_HST';
                END IF;
 
                -- Update the existing record in MARK_CASES with new data
                UPDATE sourcemaster.MARK_CASES
                SET REASON_CODE = TRIM(rec.REASON_CODE),
                    REASON_DESC = TRIM(rec.S_REASON_DESC),
                    REMARKS = TRIM(rec.REMARKS),
                    PRODUCT_ID = rec.PRODUCT_ID,
                    PRODUCT_TYPE = rec.S_PRODUCT_TYPE,
                    MAKERID = TRIM(rec.MAKERID),
                    MAKEDATE = NOW()
                WHERE APPL_ID = rec.APPL_ID
                  AND CUST_ID = rec.CUST_ID
                  AND FINANCIER_ID = rec.FINANCIER_ID
                  AND MARKING_CODE = rec.MARKING_CODE;
                GET DIAGNOSTICS v_ctr = ROW_COUNT;
                RAISE NOTICE 'Updated % record(s) in MARK_CASES', v_ctr;
                v_good_count := v_good_count + v_ctr;
            END IF;
        EXCEPTION
            WHEN OTHERS THEN
                v_err := SQLERRM;
                v_code := SQLSTATE;
                v_bad_count := v_bad_count + 1;
                RAISE NOTICE 'Error processing record: financier_id=%, appl_id=%, cust_id=%. Error code: %, Error message: %',
                             rec.FINANCIER_ID, rec.APPL_ID, rec.CUST_ID, v_code, v_err;
                UPDATE sourcemaster.MARK_CASES_CMU
                SET REASON = 'EXCEPTION DURING INSERTION OF THIS RECORD',
                    STATUS_FLAG = 'E'
                WHERE FINANCIER_ID = rec.FINANCIER_ID
                  AND APPL_ID = rec.APPL_ID
                  AND CUST_ID = rec.CUST_ID
                  AND PRODUCT_ID = rec.PRODUCT_ID
                  AND MARKING_CODE = rec.MARKING_CODE
                  AND REASON_CODE = rec.REASON_CODE
                  AND STATUS_FLAG = 'N';
                GET DIAGNOSTICS v_ctr = ROW_COUNT;
                RAISE NOTICE 'Marked % record(s) as error (STATUS_FLAG=''E'') in MARK_CASES_CMU', v_ctr;
--                INSERT INTO ERROR_LOG (BATCHID, PROCESS, QUEUE_CODE, RUN_DATE, ERROR_CODE, ERROR_DESC, MAKERID)
--                VALUES (1113, 'CMU Upload IN LOOP', NULL, NOW(), v_code, v_err, 'SYS');
--                RAISE NOTICE 'Logged error to ERROR_LOG for record: financier_id=%, appl_id=%, cust_id=%',
--                             rec.FINANCIER_ID, rec.APPL_ID, rec.CUST_ID;
        END;
    END LOOP;
    RAISE NOTICE 'Closed cursor C1. Processed % good records, % bad records', v_good_count, v_bad_count;
    -- Move successful records to history
    RAISE NOTICE 'Inserting successful records into MARK_CASES_HST';
--     Move rejected records to reject log (commented out in original)
     RAISE NOTICE 'Inserting rejected records into MARK_CASES_REJECT_REASON';
 
     GET DIAGNOSTICS v_ctr = ROW_COUNT;
     RAISE NOTICE 'Inserted % rejected records into MARK_CASES_REJECT_REASON', v_ctr;
 
EXCEPTION
    WHEN OTHERS THEN
        v_err := SQLERRM;
        v_code := SQLSTATE;
        RAISE NOTICE 'Exception in main block. Error code: %, Error message: %', v_code, v_err;
        INSERT INTO sourcemaster.ERROR_LOG ( PROCESS, QUEUE_CODE, RUN_DATE, ERROR_CODE, ERROR_DESC, MAKERID, FILENAME)
        VALUES ('CMU Upload', NULL, NOW(), v_code, v_err, 'SYS', v_filename);
 
END;
 
$procedure$
;
