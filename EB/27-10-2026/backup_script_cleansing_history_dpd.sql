-- create: backup table ==================================
-- NOTE: jalankan urutan satu per satu

-- STEP: 1

SELECT *
INTO ruleenginev2.recordmaxdpdeb_301026_bak
FROM ruleenginev2.recordmaxdpdeb
WHERE sync_dated IN (
    DATE '2026-09-15',
    DATE '2026-10-15'
);



-- ======================================================
-- NOTE: jalankan urutan satu per satu

-- rollback: step rollback ===============================


-- STEP: 1
INSERT INTO ruleenginev2.recordmaxdpdeb
SELECT * FROM ruleenginev2.recordmaxdpdeb_301026_bak;


-- =======================================================