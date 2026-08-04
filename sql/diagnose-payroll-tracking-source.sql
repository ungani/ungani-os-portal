-- Read-only. Needed before writing the payroll/staff-payment tracking
-- migration (staff salary field on ungani_team_members, related_team_
-- member_id link on transactions). Two of the RPCs this feature touches
-- already exist and must be extended, not rewritten from scratch -
-- owner_upsert_ungani_team_member() and owner_get_ungani_team_members().
-- Guessing their current body risks silently dropping logic (permission
-- checks, existing fields, validation) that's already in there. Also
-- pulling the current real columns on both tables so the ALTER TABLE
-- statements are written against what's actually there, not assumed.

-- 1. Real source of owner_upsert_ungani_team_member()
select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'owner_upsert_ungani_team_member';

-- 2. Real source of owner_get_ungani_team_members()
select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'owner_get_ungani_team_members';

-- 3. Current real columns on ungani_team_members
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_team_members'
order by ordinal_position;

-- 4. Current real columns on transactions
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'transactions'
order by ordinal_position;

-- 5. Function signatures (arg names/types) for both RPCs, in case the
-- functiondef output above is long/hard to scan at a glance.
select
  p.proname,
  pg_get_function_arguments(p.oid) as arguments,
  pg_get_function_result(p.oid) as return_type
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('owner_upsert_ungani_team_member', 'owner_get_ungani_team_members');
