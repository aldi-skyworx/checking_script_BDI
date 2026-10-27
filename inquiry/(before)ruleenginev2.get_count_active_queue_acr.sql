-- fixing search query for get_count_active_queue_acr function ---------------------------------------------------

-- STEP: 1

DROP FUNCTION IF EXISTS ruleenginev2.get_count_active_queue_acr();


-- STEP : 2

-- DROP FUNCTION ruleenginev2.get_count_active_queue_acr(text);

CREATE OR REPLACE FUNCTION ruleenginev2.get_count_active_queue_acr(p_search text DEFAULT NULL)
 RETURNS bigint
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN (
        SELECT COUNT(DISTINCT mm.queuecode)
        FROM ruleenginev2.masterqueue mq
        JOIN ruleenginev2.masterrulemanagement mm
            ON mq.queue_code = mm.queuecode
            AND mq.status = true
            AND mq.isdeleted = false
            AND mq.approvedstatus = 'ACTIVE'
            AND mq.lob = 'CONS'
        JOIN ruleenginev2.masteraction ma
            ON mm.actioncode = ma.master_action_code
            AND ma.status = true
            AND ma.isdeleted = false
            AND ma.approvedstatus = 'ACTIVE'
            AND ma.lob = 'CONS'
            AND ma.master_action_type = 'Allocation'
        JOIN ruleenginev2.masterrule mr
            ON mm.rulecode = mr.rule_code
            AND mr.status = true
            AND mr.isdeleted = false
            AND mr.approvedstatus = 'ACTIVE'
            AND mr.lob = 'CONS'
        WHERE (
            p_search IS NULL
            OR mm.queuecode ILIKE '%' || p_search || '%'
            OR mm.rulecode ILIKE '%' || p_search || '%'
            OR mr.tailquery ILIKE '%' || p_search || '%'
            OR mr.rule_name ILIKE '%' || p_search || '%'
            OR mq.queue_name ILIKE '%' || p_search || '%'
        )
    );
END;
$function$
;

-- ---------------------------------------------------------------------------------------