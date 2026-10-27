-- INFORMATION : 
-- jira: [CMSN-21089]
-- ===========================================================

-- script: untuk cleansing usergroup ==========================
-- NOTE: Jalankan satu persatu setiap tahapan


-- STEP: 1 

begin;

with
group_correct_role as (
    select h.usergroupheader_id, h.usergroup_code, h.usergrouptype as expected_role
    from public.usergroupheader h
    where h.usergrouptype is not null
),
group_members as (
    select d.usergroupdetail_id, d.usergroupcode, d.userid, g.expected_role
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
to_delete as (
    select m.*
    from group_members m
    where m.userid in (select usr_userid from users_with_role)
        and m.usergroupdetail_id not in (select usergroupdetail_id from members_with_matching_role)
)
delete from public.usergroupdetail d
using to_delete t
where d.usergroupdetail_id = t.usergroupdetail_id;

commit;


-- STEP: 2

begin;

with
orphan_members as (
    select d.usergroupdetail_id
    from public.usergroupdetail d
    where not exists (
        select 1
        from public.users u
        where u.usr_userid = d.userid
    )
)
delete from public.usergroupdetail d
using orphan_members o
where d.usergroupdetail_id = o.usergroupdetail_id; 

commit;


-- STEP: 3 

begin;

create temp table tmp_member_count on commit drop as
select
    d.usergroupheader_id,
    count(*) as actual_total
from public.usergroupdetail d
group by d.usergroupheader_id;

create temp table tmp_header_update on commit drop as
select
    h.usergroupheader_id,
    coalesce(mc.actual_total, 0) as new_total
from public.usergroupheader h
left join tmp_member_count mc
    on mc.usergroupheader_id = h.usergroupheader_id
where h.totalmember is distinct from coalesce(mc.actual_total, 0);

create index on tmp_header_update (usergroupheader_id);

update public.usergroupheader h
set totalmember = t.new_total
from tmp_header_update t
where h.usergroupheader_id = t.usergroupheader_id;

commit;


-- ===============================================================