-- Read-only. Pulls the real definition of get_my_ungani_staff_access(),
-- needed to fix a confirmed bug: sql/ungani-support-access.sql's owner-
-- only policies check `lower(u.role) = 'owner'`, but real tenant owners
-- have users.role = 'client' - 'owner' is only ever used for UNGANI's
-- own internal admin accounts on the same column. The app's REAL
-- owner-detection mechanism is this RPC (used by client.html,
-- staff-permission-guard.js, staff-visibility-filter.js, my-security.html
-- for 2FA gating) - "owner" is the default state for anyone with no
-- team_members row, not a role string. Need its exact return shape
-- (table/row vs jsonb) before writing an equivalent RLS predicate,
-- rather than guessing the calling syntax.

select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'get_my_ungani_staff_access';

-- Also confirm the return type directly, in case the above is long/hard
-- to read at a glance.
select
  p.proname,
  pg_get_function_result(p.oid) as return_type,
  p.provolatile as volatility,   -- 'i'=immutable, 's'=stable, 'v'=volatile
  p.prosecdef as is_security_definer
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'get_my_ungani_staff_access';
