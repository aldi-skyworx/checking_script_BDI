-- DROP FUNCTION ruleenginev2.get_allocation_history_sme(text, text);

CREATE OR REPLACE FUNCTION ruleenginev2.get_allocation_history_sme(p_custid text, p_lob text)
  RETURNS TABLE(lob text, remarks text, status text, queuetype text, role text, collector text, makerid text, applid text, custid text, dpd text, historyid text, allocationdated date, allocationtype text, "collectorName" text, "makerName" text)
  LANGUAGE plpgsql
AS $function$ BEGIN RETURN QUERY 
SELECT y.* 

FROM (
SELECT 
  DISTINCT ON (
    x.custid, x.allocationdated, x.collector, 
    x.makerid, x.remarks
  ) * 
FROM 
  (
    -- 1. DATA DARI MOVEMENT (cm)
    SELECT 
      'SME' :: text AS lob, 
      cm.remarks :: text, 
      u.usr_name :: text AS status, 
      cm.queue_type :: text, 
      NULL :: text AS role, 
      cm.unit_id :: text AS collector, 
      cm.makerid :: text, 
      cm.appl_id :: text, 
      cm.cust_id :: text as custid, 
      COALESCE(
        MAX(cm.dpd) OVER (
          PARTITION BY cm.cust_id, cm.allocation_date
        ), 
        0
      ):: text, 
      NULL :: text AS historyid, 
      cm.allocation_date :: date as allocationdated, 
      CASE WHEN cm.entry_type = 'A' THEN 'Allocation' WHEN cm.entry_type = 'E' THEN 'Escalation' WHEN cm.entry_type = 'RA' THEN 'Reallocation' WHEN cm.entry_type = 'BA' THEN 'BOD Allocation' WHEN cm.entry_type = 'TA' THEN 'UnAllocated' ELSE cm.entry_type END :: text, 
      u.usr_name :: text AS "collectorName", 
      u.usr_name :: text AS "makerName" 
    FROM 
      public.cs_case_mvmt_details cm 
      LEFT JOIN skycore_public.users u ON cm.unit_id = u.usr_id 
    WHERE 
      cm.cust_id = p_custid 
      AND cm.allocation_date >= NOW() - INTERVAL '10 years' 
      AND cm.unit_id IS NOT NULL 
      --and cm.purpose in(select ps.purpose from ruleenginev2.mastergroupingpurpose ps
      --where ps.lob='SME')
    UNION ALL 
      -- 2. DATA DARI ALLOCATION HISTORY (ah)
    SELECT 
      'SME' :: text, 
      ah.remarks :: text, 
      u.usr_name :: text, 
      ah.queuetype :: text, 
      NULL :: text, 
      ah.collector :: text, 
      ah.makerid :: text, 
      ah.applid :: text, 
      ah.custid :: text as custid, 
      ah.dpd :: text, 
      ah.historyid :: text AS historyid, 
      ah.allocationdated :: date, 
      CASE WHEN ah.allocationtype = 'MIGRATION' THEN 'MIGRATION' ELSE ah.allocationtype END :: text, 
      u.usr_name :: text, 
      u.usr_name :: text 
    FROM 
      ruleenginev2.allocationhistory ah 
      LEFT JOIN skycore_public.users u ON ah.collector = u.usr_userid 
    WHERE 
      ah.custid = p_custid 
      -- AND ah.lob = 'SME'
      ) x 
  -- PRIORITAS: cm dulu (historyid NULL menang)
ORDER BY 
  x.custid, 
  x.allocationdated desc,
  x.collector,
  x.makerid,
  x.remarks,
  CASE WHEN x.historyid IS NULL THEN 0 ELSE 1 END
) y
ORDER BY
  y.allocationdated DESC NULLS LAST,
  y.historyid DESC NULLS LAST;

END;
$function$
;