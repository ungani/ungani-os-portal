-- Read-only. Confirming the real schema before writing user-limit
-- enforcement - specifically avoiding the exact "guess multiple possible
-- table/column names" pattern that broke my-package.html's own
-- "Current users" counter (the bug this whole fix is partly about).
--
-- Need to know for certain: does ungani_packages have a real, canonical
-- user_limit column? Is tenants.package_key the reliable way to resolve
-- which package a tenant is actually on? What does the CURRENT (already
-- fixed) owner_upsert_ungani_team_member look like, to build the
-- enforcement into it cleanly.

-- 1. Real columns on ungani_packages - specifically checking for a user
-- limit column under any of its plausible names.
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'ungani_packages'
order by ordinal_position;

-- 2. The real package catalog - every tier's actual user limit value (if
-- the column exists per query 1).
select *
from public.ungani_packages
order by sort_order;

-- 3. Real columns on ungani_team_members - specifically confirming the
-- exact status/active columns to use for "how many seats are currently
-- in use" (mirrors what get_my_ungani_staff_access() already treats as
-- active: status in ('active','accepted'), is_active, deactivated_at).
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'ungani_team_members'
order by ordinal_position;

-- 4. Confirm tenants.package_key is the real, live pointer to a tenant's
-- current package (not ungani_subscriptions.package_key or something
-- else) - a few real tenants, package_key alongside their real staff
-- count for a sanity check against what my-package.html currently shows.
select
  t.id,
  t.business_name,
  t.package_key,
  (select count(*) from public.ungani_team_members tm where tm.tenant_id = t.id) as total_team_member_rows,
  (select count(*) from public.ungani_team_members tm where tm.tenant_id = t.id and coalesce(tm.is_active, true) = true and tm.deactivated_at is null and lower(coalesce(tm.status,'active')) not in ('disabled')) as active_team_member_rows
from public.tenants t
order by t.created_at desc
limit 10;

-- 5. The current, live source of owner_upsert_ungani_team_member (post
-- last night's fix) - building the limit check into this exact version.
select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'owner_upsert_ungani_team_member';
