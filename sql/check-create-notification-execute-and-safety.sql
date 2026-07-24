-- Read-only. Two checks before wiring Nia into create_ungani_notification:
--
-- 1. Does the `authenticated` role already have EXECUTE? (the user's
--    direct question)
-- 2. Does the function's own body validate p_tenant_id against the
--    caller's tenant, or does it trust the parameter as-is? This function
--    is clearly built for triggers (system code, legitimately writes to
--    ANY tenant) - if it has no internal ownership check and gets EXECUTE
--    granted to `authenticated` directly, any logged-in client could call
--    it with a p_tenant_id that isn't their own and inject notifications
--    into a different business's account. Need to see the real source to
--    know whether that's already guarded or not.

select p.proname, has_function_privilege('authenticated', p.oid, 'EXECUTE') as authenticated_can_execute
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'create_ungani_notification';

-- All current grantees, for context (e.g. if only service_role/postgres
-- has it today, this shows exactly what's missing).
select grantee, privilege_type
from information_schema.routine_privileges
where routine_schema = 'public'
  and routine_name = 'create_ungani_notification';

select pg_get_functiondef(p.oid) as source
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'create_ungani_notification';
