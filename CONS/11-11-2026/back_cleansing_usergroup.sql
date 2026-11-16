-- create: backup table =========================================

-- STEP: 1

SELECT *
INTO public.usergroupheader_301026_bak
FROM public.usergroupheader;

-- STEP: 2

SELECT *
INTO public.usergroupdetail_301026_bak
FROM public.usergroupdetail;

-- ==============================================================



-- Rollback steps ===============================================
-- NOTE: jalankan satu persatu

-- STEP: 1

DELETE FROM public.usergroupdetail;

-- STEP: 2

INSERT INTO public.usergroupdetail
SELECT * FROM public.usergroupdetail_301026_bak;

-- STEP: 3

DELETE FROM public.usergroupheader;

-- STEP: 4

INSERT INTO public.usergroupheader
SELECT * FROM public.usergroupheader_301026_bak;

-- STEP: 5

DELETE FROM public.usergroupdetail_301026_bak;

-- STEP: 6

UPDATE public.counterseq
SET counter = COALESCE(
    (SELECT MAX(substring(usergroup_code FROM '^8UG-(\d+)$')::bigint) 
        FROM public.usergroupheader), 
    0
)
WHERE fiturid = 8;


-- ==============================================================