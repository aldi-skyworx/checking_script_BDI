select h.usergroupheader_id, h.usergroup_code, h.totalmember,
    (select count(*) from public.usergroupdetail d
        where d.usergroupheader_id = h.usergroupheader_id) as actual_total
from public.usergroupheader h
where h.totalmember is distinct from
    (select count(*) from public.usergroupdetail d
        where d.usergroupheader_id = h.usergroupheader_id);