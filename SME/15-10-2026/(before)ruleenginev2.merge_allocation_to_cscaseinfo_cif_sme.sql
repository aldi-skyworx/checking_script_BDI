-- DROP PROCEDURE ruleenginev2.merge_allocation_to_cscaseinfo_cif_sme(text);

CREATE OR REPLACE PROCEDURE ruleenginev2.merge_allocation_to_cscaseinfo_cif_sme(
    IN param_queue text,
    IN is_bod boolean DEFAULT false
)
LANGUAGE plpgsql
AS $procedure$
BEGIN

    DROP TABLE IF EXISTS tmp_allocation_sme;

    IF param_queue = '2MQ-0213' THEN

        CREATE TEMP TABLE tmp_allocation_sme
        ON COMMIT DROP AS
        SELECT
            own.appl_id,
            own.cust_id,
            own.financier_id,
            own.queuecode,
            u.usr_id
        FROM ruleenginev2.allocationdistributionownershipcif own
        JOIN skycore_public.users u
            ON u.usr_userid = own.collector
            AND u.prd_sgm_id = 4
            AND u.usr_approved_status = 'ACTIVE'
            AND u.isdeleted IS FALSE
        WHERE own.lob = 'SME'
            AND own.queuecode = param_queue;

    ELSE

        CREATE TEMP TABLE tmp_allocation_sme
        ON COMMIT DROP AS
        SELECT
            own.appl_id,
            own.cust_id,
            own.financier_id,
            own.queuecode,
            u.usr_id
        FROM ruleenginev2.allocationdistributionownershipcif own
        LEFT JOIN skycore_public.users u
            ON u.usr_userid = own.collector
            AND u.prd_sgm_id = 4
            AND u.usr_approved_status = 'ACTIVE'
            AND u.isdeleted IS FALSE
        WHERE own.lob = 'SME'
            AND own.queuecode = param_queue;

    END IF;

    CREATE INDEX idx_tmp_allocation_sme
        ON tmp_allocation_sme (
            appl_id,
            cust_id,
            financier_id
        );

    CREATE TEMP TABLE tmp_purpose_sme
    ON COMMIT DROP AS
    SELECT purpose
    FROM ruleenginev2.mastergroupingpurpose
    WHERE lob = 'SME';

    CREATE INDEX idx_tmp_purpose_sme
        ON tmp_purpose_sme (purpose);

    UPDATE public.cs_case_info AS trg
    SET
        tmp_allocation_flag      = 'N',
        manual_reallocation_flag = 'N',
        queue_type               = 'Ownership SME',
        queue_date               = NOW(),
        unit_id                  = src.usr_id,
        queue                    = src.queuecode,
        allocation_date          = NOW()
    FROM tmp_allocation_sme src
    WHERE trg.appl_id      = src.appl_id
        AND trg.cust_id      = src.cust_id
        AND trg.financier_id = src.financier_id
        AND trg.purpose IN (
            SELECT purpose
            FROM tmp_purpose_sme
        )
        AND (
            trg.unit_id IS DISTINCT FROM src.usr_id
            OR trg.queue IS DISTINCT FROM src.queuecode
        );

    -- ----------------------
    IF param_queue = '3MQ-000' AND is_bod IS TRUE THEN

        INSERT INTO ruleenginev2.allocationhistory (
            applid,
            custid,
            financierid,
            queuecode,
            queuetype,
            collector,
            lob,
            allocationdated,
            status,
            allocationtype,
            dpd,
            makerid
        )
        SELECT 
            own.appl_id,
            own.cust_id,
            own.financier_id,
            own.queuecode,
            'Ownership',
            own.collector,
            own.lob,
            NOW(),
            own.status,
            'BOD',
            own.dpd,
            'SYS'
        FROM ruleenginev2.allocationdistributionownershipcif own
        WHERE own.lob = 'SME'
            AND own.queuecode = param_queue;
    
    END IF;

END;
$procedure$
;
