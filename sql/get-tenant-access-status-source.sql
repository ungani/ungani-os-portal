-- Read-only. Pulls the real source of get_ungani_tenant_access_status(),
-- called at the end of get_my_ungani_access_status() for any non-staff
-- user with a resolved tenant_id - this is the actual function that
-- produces the access_status/status value ('suspended' among others)
-- that client-access-guard.js checks against its blockedStatuses list to
-- decide whether to show the full-page "Workspace Access Restricted"
-- hard lock. Not pulled by the previous query since it wasn't in that
-- request's function-name list.
--
-- Confirmed from the previous pull: get_my_ungani_subscription_access()
-- already treats 'suspended'/'cancelled'/'canceled'/'expired'/
-- 'inactive'/'blocked' as can_write=false (soft read-only), not a hard
-- lock - so this function is the actual place the suspension-model
-- change needs to happen, not that one.

select p.proname, pg_get_functiondef(p.oid) as source
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'get_ungani_tenant_access_status';
