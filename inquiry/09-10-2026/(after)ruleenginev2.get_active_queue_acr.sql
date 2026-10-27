-- fixing search query for get_active_queue_acr function ---------------------------------------------------

-- STEP: 1

drop function if exists ruleenginev2.get_active_queue_acr(int4, int4, text);

-- STEP : 2

-- DROP FUNCTION ruleenginev2.get_active_queue_acr(int4, int4, text, text);

CREATE OR REPLACE FUNCTION ruleenginev2.get_active_queue_acr(p_size integer, p_offset integer, p_search text DEFAULT NULL,  p_search_by text DEFAULT NULL)
 RETURNS TABLE(id bigint, queuecode text, rulecode text, rulestring text, rulename text, queuename text)
 LANGUAGE plpgsql
AS $function$
BEGIN
    RETURN QUERY
    SELECT DISTINCT ON (mm.queuecode)
        mm.rulemanagement_id AS id,
        mm.queuecode AS queuecode,
        mm.rulecode AS rulecode,
        mr.tailquery AS rulestring,
        mr.rule_name AS rulename,
        mq.queue_name AS queuename
    FROM ruleenginev2.masterqueue mq
    JOIN ruleenginev2.masterrulemanagement mm
        ON mq.queue_code = mm.queuecode
        and mq.status=true
        and mq.isdeleted=false 
        and mq.approvedstatus='ACTIVE'
        and mq.lob='CONS'
    JOIN ruleenginev2.masteraction ma
        ON mm.actioncode = ma.master_action_code
         and ma.status=true
        and ma.isdeleted=false 
        and ma.approvedstatus='ACTIVE'
        and ma.lob='CONS'
        and ma.master_action_type='Allocation'
    JOIN ruleenginev2.masterrule mr
        ON mm.rulecode = mr.rule_code
         and mr.status=true
        and mr.isdeleted=false 
        and mr.approvedstatus='ACTIVE'
        and mr.lob='CONS'
    where (
        case 
            when p_search is null then true
            when p_search_by = 'queue' then (
                mm.queuecode ilike '%' || p_search || '%'
                or mq.queue_name ilike '%' || p_search || '%'
            )
            when p_search_by = 'rule' then (
                mm.rulecode ilike '%' || p_search || '%'
                or mr.rule_name ilike '%' || p_search || '%'
            )
            else (
                mm.queuecode ilike '%' || p_search || '%'
                or mm.rulecode ilike '%' || p_search || '%'
                or mr.tailquery ilike '%' || p_search || '%'
                or mr.rule_name ilike '%' || p_search || '%'
                or mq.queue_name ilike '%' || p_search || '%'
            )
            end
    )
    ORDER BY
        mm.queuecode,
        mm.rulemanagement_id DESC
    LIMIT p_size
    OFFSET p_offset;
END;
$function$
;
