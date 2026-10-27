-- fixing search query for get_count_active_queue_acr function ---------------------------------------------------

-- STEP: 1

DROP FUNCTION IF EXISTS ruleenginev2.get_count_active_queue_acr(text);


-- STEP : 2

-- DROP FUNCTION ruleenginev2.get_count_active_queue_acr(text, text);

CREATE OR REPLACE FUNCTION ruleenginev2.get_count_active_queue_acr(p_search text DEFAULT NULL, p_search_by text DEFAULT NULL)
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
        where (
            case 
                when p_search is null then true
                when p_search_by = 'queue' then mm.queuecode ilike '%' || p_search || '%'
                when p_search_by = 'rule' then mm.rulecode ilike '%' || p_search || '%'
                else (
                    mm.queuecode ilike '%' || p_search || '%'
                    or mm.rulecode ilike '%' || p_search || '%'
                    or mr.tailquery ilike '%' || p_search || '%'
                    or mr.rule_name ilike '%' || p_search || '%'
                    or mq.queue_name ilike '%' || p_search || '%'
                )
                end
        )
    );
END;
$function$
;

-- ---------------------------------------------------------------------------------------