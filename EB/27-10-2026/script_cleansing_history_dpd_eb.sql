-- INFORMATION : 
-- jira: [CMSN-21091]

-- script: cleansing history eb dpd tanggal 15 ================

delete from ruleenginev2.recordmaxdpdeb eb
where eb.sync_dated in (
    DATE '2026-09-15',
    DATE '2026-10-15'
);

-- ==========================================================