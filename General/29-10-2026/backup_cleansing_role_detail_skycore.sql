-- create: backup table =========================================


-- STEP: 1

SELECT *
INTO public.role_detail_061126_bak
FROM public.role_detail
WHERE rld_rl_id IN (120, 121);

-- =============================================================



-- rollback steps ==============================================
-- NOTE: jalankan satu persatu


-- STEP : 1

DELETE FROM public.role_detail
WHERE rld_rl_id IN (120, 121);


-- STEP : 2

INSERT INTO public.role_detail
SELECT * FROM public.role_detail_061126_bak;


-- ==============================================================