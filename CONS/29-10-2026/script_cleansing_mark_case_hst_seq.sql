-- INFORMATION : 
-- jira:
-- ===========================================================


BEGIN;

SELECT setval(
    'sourcemaster.mark_cases_hst_seq',
    COALESCE((SELECT MAX(mark_id) FROM sourcemaster.mark_cases_hst), 1)::bigint
);

SELECT setval(
    'sourcemaster.mark_cases_seq',
    COALESCE((SELECT MAX(mark_id) FROM sourcemaster.mark_cases), 1)::bigint
);

COMMIT;