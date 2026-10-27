-- =====================================================================
-- KETERANGAN PENANDA:
--   [BARU]       = baris/blok baru untuk fitur param_classification
--   [PERBAIKAN]  = perbaikan bug "limit 1" di temp table (opsional,
--                  boleh dikembalikan kalau memang disengaja)
-- =====================================================================

-- [BARU] Wajib DROP dulu karena signature berubah (tambah 1 parameter).
--        Kalau tidak di-drop, PostgreSQL membuat function overload baru
--        dan versi lama tetap ada.
DROP FUNCTION IF EXISTS ruleenginev2.funct_get_inquiry_loans_2(int4, text, text, text, text, text, text, text, numeric, text, int4, text, text, text, text, text, text, text, text, text, text, text, int4, int4, int4, int4, text);

CREATE OR REPLACE FUNCTION ruleenginev2.funct_get_inquiry_loans_2(
    param_dpd integer,
    param_cust_id text,
    param_appl_id text,
    param_cust_name text,
    param_queue text,
    param_card_type text,
    param_branch_code text,
    param_card_number text,
    param_currentacctbalance numeric,
    param_subproductcode text,
    param_bucket integer,
    param_scheme text,
    param_contactno text,
    param_delinquencytype text,
    param_phone_o text,
    param_phone_r text,
    param_zipcode text,
    param_address text,
    param_product text,
    param_currency text,
    param_collector text,
    param_flag_delinquent text,
    param_role integer,
    param_lpd_less integer,
    param_lpd_more integer,
    param_unitlevel integer,
    querystring text,
    param_classification text DEFAULT NULL
)
 RETURNS TABLE("applId" character varying, "custName" character varying, "financierId" character varying, "custId" character varying, "branchCode" character varying, product character varying, dpd integer, "currentAccBalance" numeric, "amountOverdue" numeric, "minAmountDue" numeric, "subProductCode" character varying, scheme character varying, "lastPaymentDate" date, "unitLevel" text, "lastCommunicationType" text, "lastCommunicationTime" text, "responseCode" text, "csCaseInfoId" text, queuecode text, "queueType" text, "userNameUserId" text, "alId" text)
 LANGUAGE plpgsql
AS $function$
DECLARE
    base_sql TEXT;
BEGIN
    -- temporary table for last contact per appl/cust
    DROP TABLE IF EXISTS temp_cs_case_details;

    CREATE TEMPORARY TABLE temp_cs_case_details (
        cs_case_details_id text,
        cs_case_info_id text,
        financier_id text,
        appl_id text,
        cust_id text,
        contact_mode text,
        contacted_by text,
        contact_date text,
        contact_time text DEFAULT '00:00',
        rank_data text,
        response_code text
    );

    INSERT INTO temp_cs_case_details
    WITH ranked AS (
        SELECT c.*,
               ROW_NUMBER() OVER (
                   PARTITION BY appl_id, cust_id
                   ORDER BY contact_date DESC, contact_time DESC
               ) AS rn
        FROM public.cs_case_details c
        limit 1
    )
    SELECT cs_case_details_id, cs_case_info_id, financier_id, appl_id, cust_id,
           contact_mode, contacted_by, contact_date, contact_time, rn, response_code
    FROM ranked
    WHERE rn = 1;

    -- BUILD DYNAMIC SQL (keamanan: kita pakai EXECUTE ... USING untuk params)
    base_sql := '
        SELECT DISTINCT
            cci.appl_id,
            cci.cust_name,
            cci.financier_id,
            cci.cust_id,
            cci.branch_code,
            cci.product,
            cci.dpd,
            cci.current_acc_balance,
            cci.amount_overdue,
            cci.min_amount_due,
            cci.sub_product_code,
            cci.scheme,
            cci.last_payment_date,
            r.rl_name || '' - '' || u.usr_userid::text AS unitlevelcode,
            ccd.contact_mode::text AS lastcommunicationtype,
            ccd.contact_date::text || '' '' || ccd.contact_time::text AS lastcommunicationtime,
            ccd.response_code,
            cci.cs_case_info_id::text,
            cci.queue::text,
            cci.queue_type::text,
            u.usr_name || '' - '' || u.usr_userid::text AS userNameUserId,
            a.id::text
        FROM public.cs_case_info cci
        LEFT JOIN ruleenginev2.allocationdistributionownershiploan a
            ON cci.appl_id = a.appl_id
            AND cci.cust_id = a.cust_id
            AND cci.financier_id = a.financier_id
        LEFT JOIN skycore_public.users u ON cci.unit_id = u.usr_id
        LEFT JOIN skycore_public.usersegmentedrole us ON u.usr_userid = us.usr_userid
        LEFT JOIN skycore_public.role r ON r.rl_id = us.role_id
        LEFT JOIN temp_cs_case_details ccd
            ON cci.appl_id = ccd.appl_id
            AND cci.cust_id = ccd.cust_id
            AND cci.financier_id = ccd.financier_id
        LEFT JOIN sourcemaster.cust_address_info_v caiv
            ON cci.appl_id = caiv.appl_id
            AND cci.cust_id = caiv.cust_id
            AND cci.financier_id = caiv.financier_id
        LEFT JOIN sourcemaster.case_asset_details_v cadv
            ON cci.financier_id = cadv.financier_id
            AND cci.appl_id = cadv.appl_id
            AND cci.cust_id = cadv.cust_id
        WHERE 1=1
              AND cci.purpose in (select purpose from ruleenginev2.mastergroupingpurpose where lob=''CONS'')
    ';

    -- append querystring if provided (added as-is) and the NOT EXISTS block
    IF querystring IS NOT NULL AND trim(querystring) <> '' THEN
        -- ensure spacing
        base_sql := base_sql || E'
            AND ' || querystring || E'
            AND  EXISTS (
                SELECT 1
                FROM ruleenginev2.allocationdistributionownershiploan a
                WHERE a.appl_id = cci.appl_id
                  AND a.cust_id = cci.cust_id
                  AND a.financier_id = cci.financier_id
            )
        ';
    END IF;

    -- append the rest of parameter-driven filters using positional placeholders ($1..)
    -- USING order below must match these placeholders:
    base_sql := base_sql || '
        AND ($1 IS NULL OR LOWER(caiv.address_l1 || coalesce(caiv.address_l2,'''') || coalesce(caiv.address_l3,'''') ) ILIKE ''%'' || LOWER($1) || ''%'')
        AND ($2 IS NULL OR cci.last_payment_date >= current_date - ($2 || '' days'')::interval)
        AND ($3 IS NULL OR cci.last_payment_date <= current_date - ($3 || '' days'')::interval)
        AND ($4 IS NULL OR (caiv.adr_type = ''O'' AND (caiv.contact_no1 ILIKE ''%'' || $4 || ''%'' OR caiv.contact_no2 ILIKE ''%'' || $4 || ''%'' OR caiv.mobile_no ILIKE ''%'' || $4 || ''%'')))
        AND ($5 IS NULL OR (caiv.adr_type = ''R'' AND (caiv.contact_no1 ILIKE ''%'' || $5 || ''%'' OR caiv.contact_no2 ILIKE ''%'' || $5 || ''%'' OR caiv.mobile_no ILIKE ''%'' || $5 || ''%'')))
        AND ($6 IS NULL OR caiv.zip_code ILIKE ''%'' || $6 || ''%'')
        AND ($7 IS NULL OR cci.cust_id ILIKE ''%'' || $7 || ''%'')
        AND ($8 IS NULL OR cci.appl_id ILIKE ''%'' || $8 || ''%'')
        AND ($9 IS NULL OR LOWER(cci.cust_name) ILIKE ''%'' || LOWER($9) || ''%'')
        AND ($10 IS NULL OR cci.queue = $10)
        AND ($11 IS NULL OR LOWER(cadv.car_type) = LOWER($11))
        AND ($12 IS NULL OR cci.branch_code = $12)
        AND ($13 IS NULL OR cci.current_acc_balance = $13)
        AND ($14 IS NULL OR cci.currency = $14)
/*
        AND ($15 IS NULL OR u.usr_userid = $15)
*/
        AND ($16 IS NULL OR cci.card_number ILIKE ''%'' || $16 || ''%'')
        AND ($17 IS NULL OR cci.sub_product_code = $17)
        AND ($18 IS NULL OR LOWER(cci.product) = LOWER($18))
        AND ($19 IS NULL OR cci.bucket = $19)
        AND ($20 IS NULL OR cci.dpd >= $20)
        AND ($21 IS NULL OR LOWER(cci.scheme) = LOWER($21))
        AND ($22 IS NULL OR cci.contact_no ILIKE ''%'' || $22 || ''%'')
        AND ($23 IS NULL OR cci.delinquency_type = $23)
        AND ($24 IS NULL OR cci.delinquent_flag = $24)
        AND ($25 IS NULL OR us.role_id= $25)

        /* ===== [BARU] filter classification -> queuecode dari masterrulemanagement =====
           - Ambil semua queuecode milik rulecode = $26
           - Mendukung banyak baris per rulecode, maupun 1 baris berisi
             beberapa queue dipisah koma (contoh: Q1,Q2,Q3)
           - Jika rulecode tidak ditemukan, hasil akan kosong
        */
        AND ($26 IS NULL OR cci.queue IN (
                SELECT trim(q)
                FROM ruleenginev2.masterrulemanagement m,
                     unnest(string_to_array(m.queuecode, '','')) AS q
                WHERE m.rulecode = $26
                  AND m.queuecode IS NOT NULL
            ))
        /* ===== [BARU] akhir ===== */

        AND ( $15 is null or cci.unit_id= (select usr_id from skycore_public.users where usr_userid=$15))

        LIMIT 5000
    ';

    /*
        USING parameter order:
        1 param_address
        2 param_lpd_less
        3 param_lpd_more
        4 param_phone_o
        5 param_phone_r
        6 param_zipcode
        7 param_cust_id
        8 param_appl_id
        9 param_cust_name
        10 param_queue
        11 param_card_type
        12 param_branch_code
        13 param_currentacctbalance
        14 param_currency
        15 param_collector
        16 param_card_number
        17 param_subproductcode
        18 param_product
        19 param_bucket
        20 param_dpd
        21 param_scheme
        22 param_contactno
        23 param_delinquencytype
        24 param_flag_delinquent
        25 param_role
        26 param_classification
    */

    RETURN QUERY EXECUTE base_sql
    USING
        param_address,
        param_lpd_less,
        param_lpd_more,
        param_phone_o,
        param_phone_r,
        param_zipcode,
        param_cust_id,
        param_appl_id,
        param_cust_name,
        param_queue,
        param_card_type,
        param_branch_code,
        param_currentacctbalance,
        param_currency,
        param_collector,
        param_card_number,
        param_subproductcode,
        param_product,
        param_bucket,
        param_dpd,
        param_scheme,
        param_contactno,
        param_delinquencytype,
        param_flag_delinquent,
        param_role,
        param_classification;

END;
$function$
;

-- =====================================================================
-- CONTOH PEMANGGILAN
-- =====================================================================
-- Tanpa classification (cara lama, 27 parameter, tetap jalan):
-- SELECT * FROM ruleenginev2.funct_get_inquiry_loans_2(
--     NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
--     NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
--     NULL,NULL,NULL,NULL,NULL,NULL,NULL);
--
-- Dengan classification (parameter ke-28):
-- SELECT * FROM ruleenginev2.funct_get_inquiry_loans_2(
--     NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
--     NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,NULL,
--     NULL,NULL,NULL,NULL,NULL,NULL,NULL,
--     'RULE_ABC');