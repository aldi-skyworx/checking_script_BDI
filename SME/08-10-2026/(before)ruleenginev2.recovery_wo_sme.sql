-- DROP PROCEDURE ruleenginev2.recovery_wo_sme(text);

CREATE OR REPLACE PROCEDURE ruleenginev2.recovery_wo_sme(IN param_financierid text)
 LANGUAGE plpgsql
AS $procedure$
BEGIN

CREATE TEMP TABLE IF NOT EXISTS tmp_new_loan_cif
(
    cust_id text,
    financier_id text
) ON COMMIT DROP;

TRUNCATE TABLE tmp_new_loan_cif;

INSERT INTO tmp_new_loan_cif(cust_id, financier_id)
SELECT DISTINCT
    cci.cust_id,
    cci.financier_id
FROM public.cs_case_info cci
INNER JOIN ruleenginev2.allocation_temp at
    ON at.cust_id = cci.cust_id
   AND at.financier_id = cci.financier_id
   AND at.lob = 'SME'
WHERE cci.financier_id = param_financierid;

WITH
collec_roles AS (
    SELECT DISTINCT ON (ur.usr_userid)
        ur.usr_userid,
        ur.role_id
    FROM ruleenginev2.snapshot_usersegmentedrole ur
    JOIN ruleenginev2.snapshot_users us
        ON  ur.usr_userid          = us.usr_userid
        AND us.prd_sgm_id          = 4
        AND us.usr_status          IS TRUE
        AND us.usr_approved_status = 'ACTIVE'
        AND us.isdeleted           IS FALSE
    ORDER BY ur.usr_userid
),
collector_role_102 AS (
    select distinct usr_userid
    FROM collec_roles
    WHERE role_id in (102,108)
),
existing_collector AS (
    SELECT DISTINCT ON (cust_id, financier_id)
        cust_id,
        financier_id,
        collector,
		status AS existing_status
    FROM ruleenginev2.allocationdistributionownershipcif
    WHERE financier_id = param_financierid
      AND lob          = 'SME'
      AND collector    IS NOT NULL
    ORDER BY cust_id, financier_id, (collector IS NOT NULL) DESC
)
MERGE INTO ruleenginev2.allocationdistributionownershipcif AS trg
USING (
    SELECT DISTINCT ON (cci.appl_id, cci.cust_id, cci.financier_id)
        cci.cs_case_info_id                   AS cs_case_info_id,
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
        cci.currency,
        cci.watchlist_flag,
        cci.charge_off_flag,
        cci.late_fees,
        cci.charge_off_date,
        cci.user_amount6,
        cci.branch_code,
        'SME'::text                           AS lob,
        ec.collector                          AS existing_col,
		ec.existing_status AS existing_status
    FROM public.cs_case_info cci
    INNER JOIN ruleenginev2.allocation_temp at
        ON  at.cust_id      = cci.cust_id
        AND at.financier_id = cci.financier_id
        AND at.lob          = 'SME'
    INNER JOIN ruleenginev2.mastergroupingpurpose m
        ON  m.purpose = cci.purpose
        AND m.lob     = 'SME'
    LEFT JOIN existing_collector ec
        ON  ec.cust_id      = cci.cust_id
       AND ec.financier_id = cci.financier_id
    WHERE cci.financier_id = param_financierid
    ORDER BY
        cci.appl_id,
        cci.cust_id,
        cci.financier_id,
        (ec.collector IS NOT NULL) DESC
) AS src
ON (
    trg.appl_id      = src.appl_id
    AND trg.cust_id  = src.cust_id
    AND trg.financier_id = src.financier_id
    AND trg.lob      = 'SME'
)
--WHEN MATCHED AND trg.queuecode='2MQ-0213' THEN UPDATE SET
WHEN MATCHED AND trg.queuecode in ('2MQ-0213', '3MQ-000') THEN UPDATE SET
    collector = CASE
                    WHEN (SELECT role_id FROM collec_roles WHERE usr_userid = trg.collector) NOT IN (113, 140)
                    THEN NULL
                    ELSE src.existing_col
                END,
    queuecode             = '2MQ-0214',
    cs_case_info_id       = src.cs_case_info_id,
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
    lob                   = 'SME',
    branchcode            = src.branch_code
WHEN NOT MATCHED THEN INSERT (
    queuecode, cs_case_info_id, taskdated, collector, status,
    isdone, donedated, appl_id, cust_id, financier_id,
    cust_name, cif_number, dpd, product, outstanding_amt,
    interest_outstanding, principle_outstanding, m_billed_outstanding,
    amount_outstanding, lob, currency, watchlist_flag, charge_off_flag,
    user_amount6, late_fees, branchcode, charge_off_date
) VALUES (
    '2MQ-0214',
    src.cs_case_info_id,
    NOW(),
    src.existing_col,
--    'NEW ACCOUNT',
	COALESCE(src.existing_status, 'NEW ACCOUNT'),
    false, NULL,
    src.appl_id, src.cust_id, src.financier_id,
    src.cust_name, src.cif_number, src.dpd, src.product,
    src.outstanding_amt, src.interest_outstanding, src.principle_outstanding,
    src.m_billed_outstanding, src.amount_outstanding,
    'SME', src.currency, src.watchlist_flag, src.charge_off_flag,
    src.user_amount6, src.late_fees, src.branch_code, src.charge_off_date
);

UPDATE ruleenginev2.allocationdistributionownershipcif trg
SET status = 'NEW ACCOUNT'
FROM tmp_new_loan_cif nl
WHERE trg.cust_id = nl.cust_id
  AND trg.financier_id = nl.financier_id
  AND trg.lob = 'SME'
  AND trg.collector IS NULL;


TRUNCATE ruleenginev2.allocation_temp RESTART IDENTITY;
END;
$procedure$
;
