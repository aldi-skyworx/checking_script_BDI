-- create: backup table =========================================

-- STEP: 1

with
group_correct_role as (
    select h.usergroupheader_id, h.usergrouptype as expected_role
    from public.usergroupheader h
    where h.usergrouptype is not null
),
group_members as (
    select d.usergroupdetail_id, d.userid, g.expected_role
    from public.usergroupdetail d
    inner join group_correct_role g
        on g.usergroupheader_id = d.usergroupheader_id
),
users_with_role as (
    select distinct usr_userid
    from public.usersegmentedrole
),
members_with_matching_role as (
    select distinct m.usergroupdetail_id
    from group_members m
    inner join public.usersegmentedrole x
        on x.usr_userid = m.userid
        and x.role_id   = m.expected_role
),
to_delete_step1 as (
    select m.usergroupdetail_id
    from group_members m
    where m.userid in (select usr_userid from users_with_role)
        and m.usergroupdetail_id not in (select usergroupdetail_id from members_with_matching_role)
),
to_delete_step2 as (
    select d.usergroupdetail_id
    from public.usergroupdetail d
    where not exists (
        select 1
        from public.users u
        where u.usr_userid = d.userid
    )
)
select 
    d.*, 
    case 
        when s1.usergroupdetail_id is not null then 'STEP_1'
        else 'STEP_2'
    end as step_origin
into public.usergroupdetail_301026_bak
from (
    select *, 'skycore' as source_schema from public.usergroupdetail
    union all
    select *, 'public' as source_schema from public.usergroupdetail
) d
left join to_delete_step1 s1 on d.usergroupdetail_id = s1.usergroupdetail_id
left join to_delete_step2 s2 on d.usergroupdetail_id = s2.usergroupdetail_id
where s1.usergroupdetail_id is not null 
    or s2.usergroupdetail_id is not null;

-- =============================================================



-- Rollback steps ===============================================
-- NOTE: jalankan satu persatu


-- STEP : 1

INSERT INTO public.usergroupdetail (
    usergroupdetail_id, usergroupheader_id, usergroupcode, userid, 
    createdby, createddated, modifiedby, modifieddated
)
SELECT 
    usergroupdetail_id, usergroupheader_id, usergroupcode, userid, 
    createdby, createddated, modifiedby, modifieddated
FROM public.usergroupdetail_301026_bak
WHERE step_origin = 'STEP_1';


-- STEP : 2

INSERT INTO public.usergroupdetail (
    usergroupdetail_id, usergroupheader_id, usergroupcode, userid, 
    createdby, createddated, modifiedby, modifieddated
)
SELECT 
    usergroupdetail_id, usergroupheader_id, usergroupcode, userid, 
    createdby, createddated, modifiedby, modifieddated
FROM public.usergroupdetail_301026_bak
WHERE step_origin = 'STEP_2';


-- STEP: 3

WITH member_count AS (
    SELECT
        d.usergroupheader_id,
        COUNT(*) AS actual_total
    FROM public.usergroupdetail d
    GROUP BY d.usergroupheader_id
)
UPDATE public.usergroupheader h
SET totalmember = mc.actual_total
FROM member_count mc
WHERE h.usergroupheader_id = mc.usergroupheader_id;


-- =============================================================