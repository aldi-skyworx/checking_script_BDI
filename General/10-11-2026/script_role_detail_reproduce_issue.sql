begin;

WITH latest_role AS (
    SELECT 
    	rld_rl_id 
    FROM public.role_detail 
    ORDER BY rld_id DESC 
    LIMIT 1
)
SELECT setval(
    'public.role_detail_rld_id_seq1',
    (
        SELECT 
            COALESCE(MAX(rld_id), 0) - 
            COUNT(CASE WHEN rld_rl_id = (SELECT rld_rl_id FROM latest_role) THEN 1 END) - 2
        FROM public.role_detail
    )::bigint
);


commit;