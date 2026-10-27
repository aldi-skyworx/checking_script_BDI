-- DROP PROCEDURE ruleenginev2.merge_allocation_temp_own_sme(text);

CREATE OR REPLACE PROCEDURE ruleenginev2.merge_allocation_temp_own_sme(IN rule_type text)
 LANGUAGE plpgsql
AS $procedure$
DECLARE 
    v_now TIMESTAMP := NOW();
BEGIN

    MERGE INTO ruleenginev2.allocationdistributionownershipcif AS trg
    USING (
        SELECT DISTINCT ON (cci.appl_id, cci.cust_id, cci.financier_id)
            at.queuecode,
            cci.cs_case_info_id,
            at.actioncodestatus,
            cci.appl_id::text,
            cci.cust_id::text,
            cci.financier_id::text,
            cci.cust_name,
            cci.cif_number,
            cci.dpd,
            cci.product,
            cci.outstanding_amt,
            cci.interest_outstanding,
            cci.principle_outstanding,
            cci.m_billed_outstanding,
            cci.amount_outstanding,
            at.lob,
            at.branchcode,
            at.actiontype,
            at.queuetype,
            at.usergroup,
            at.batchid,
            cci.user_amount3,
            cci.user_amount6,
            cci.currency,
            cci.watchlist_flag,
            cci.charge_off_flag,
            cci.late_fees,
            cci.charge_off_date,
			cci.account_closed_flg AS cci_acc_closed,
            t2.collector AS existing_collector,
            t2.queuecode AS existing_queuecode,
            t2.lob       AS lob_alokasi
        FROM ruleenginev2.allocation_temp at
        INNER JOIN public.cs_case_info cci 
            ON  at.cust_id      = cci.cust_id 
            AND at.financier_id = cci.financier_id
        INNER JOIN ruleenginev2.mastergroupingpurpose m
            ON  m.purpose = cci.purpose
            AND m.lob     = 'SME'
        LEFT JOIN (
            SELECT DISTINCT ON (cust_id)
                cust_id,
                collector,
                lob,
                queuecode
            FROM ruleenginev2.allocationdistributionownershipcif a
			JOIN ruleenginev2.snapshot_usersegmentedrole urs -- ini join baru untuk filter collector
      			ON a.collector = urs.usr_userid
     			AND urs.role_id IN (102, 108, 110, 89) -- ambil role (softcoll, remedial)
            WHERE financier_id = 'BDI-LOANS'
              AND collector IS NOT NULL
--              AND queuecode   = '2MQ-0213'
			  AND queuecode In ('2MQ-0213', '3MQ-000')
              AND lob         = 'SME'
            ORDER BY cust_id
        ) t2 
            ON t2.cust_id = at.cust_id
        WHERE at.lob          = 'SME'
          AND at.financier_id = 'BDI-LOANS'
         /* AND cci.dpd BETWEEN 1 AND 30
          AND cci.user_amount6 NOT IN (0, 1)*/
        ORDER BY cci.appl_id, cci.cust_id, cci.financier_id
    ) AS src
    ON (
        trg.appl_id      = src.appl_id AND
        trg.cust_id      = src.cust_id AND
        trg.financier_id = src.financier_id AND
        trg.lob          = 'SME'
    )
    WHEN MATCHED THEN 
        UPDATE SET
            currency              = src.currency,
            watchlist_flag        = src.watchlist_flag,
            charge_off_flag       = src.charge_off_flag,
            charge_off_date       = src.charge_off_date,
            user_amount6          = src.user_amount6,
            late_fees             = src.late_fees,
            cust_name             = src.cust_name,
            cif_number            = src.cif_number,
            dpd                   = src.dpd,
            product               = src.product,
            outstanding_amt       = src.outstanding_amt,
            interest_outstanding  = src.interest_outstanding,
            principle_outstanding = src.principle_outstanding,
            m_billed_outstanding  = src.m_billed_outstanding,
            amount_outstanding    = src.amount_outstanding,
            branchcode            = src.branchcode,
			account_closed_flag   = src.cci_acc_closed,
			queuecode = CASE WHEN trg.queuecode = '3MQ-000' THEN '2MQ-0213' ELSE src.queuecode END,
			collector = CASE WHEN trg.collector IS NULL THEN src.existing_collector ELSE trg.collector END
--			queuecode = '2MQ-0213'

    WHEN NOT MATCHED THEN
        INSERT (
            queuecode,
            cs_case_info_id,
            taskdated,
            collector,
            status,
            isdone,
            donedated,
            appl_id,
            cust_id,
            financier_id,
            cust_name,
            cif_number,
            dpd,
            product,
            outstanding_amt,
            interest_outstanding,
            principle_outstanding,
            m_billed_outstanding,
            amount_outstanding,
            lob,
            currency,
            watchlist_flag,
            charge_off_flag,
            user_amount6,
            late_fees,
            branchcode,
            charge_off_date,
			account_closed_flag
        )
        VALUES (
            '2MQ-0213',
            src.cs_case_info_id,
            v_now,
            src.existing_collector,
            CASE
                WHEN src.lob_alokasi = 'SME' AND src.existing_collector IS NOT NULL THEN 'NEW TASK'
                ELSE 'NEW ACCOUNT'
            END,
            FALSE,
            NULL,
            src.appl_id,
            src.cust_id,
            src.financier_id,
            src.cust_name,
            src.cif_number,
            src.dpd,
            src.product,
            src.outstanding_amt,
            src.interest_outstanding,
            src.principle_outstanding,
            src.m_billed_outstanding,
            src.amount_outstanding,
            src.lob,
            src.currency,
            src.watchlist_flag,
            src.charge_off_flag,
            src.user_amount6,
            src.late_fees,
            src.branchcode,
            src.charge_off_date,
			src.cci_acc_closed::text
        );

    -- Kosongkan tabel temporary setelah proses MERGE selesai
    TRUNCATE TABLE ruleenginev2.allocation_temp RESTART IDENTITY;
		
		
END;
$procedure$
;
