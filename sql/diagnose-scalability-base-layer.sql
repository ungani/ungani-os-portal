-- Read-only diagnostic. Confirms (or disproves) the one part of the
-- scalability story that can't be verified from source control, because
-- the base schema/RLS/tenant-resolver function predates this repo's sql/
-- tracking and was never captured in a migration file (see
-- ARCHITECTURE.md "Known gaps"). Everything below is a SELECT against
-- system catalogs - nothing here writes or changes anything.
--
-- Run all of this and paste back the full output.

-- ============================================================
-- PART 1: the tenant-resolver function itself.
-- This runs on almost every RLS-protected query in the app. If its body
-- does anything more than a cheap indexed lookup (e.g. a scan, a join, a
-- non-STABLE/VOLATILE marking that defeats query-plan caching), it's a
-- per-query cost that scales with platform size, not per-tenant size.
-- ============================================================

select
  p.proname as function_name,
  case p.provolatile
    when 'i' then 'IMMUTABLE'
    when 's' then 'STABLE'
    when 'v' then 'VOLATILE'
  end as volatility,
  p.prosecdef as is_security_definer,
  pg_get_functiondef(p.oid) as full_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'get_my_ungani_tenant_id';

-- ============================================================
-- PART 2: is tenant_id actually indexed on every high-traffic table?
-- A missing index here means every RLS-filtered query against that table
-- does a sequential scan that gets slower as TOTAL rows across ALL
-- tenants grow - i.e. exactly the "gets worse as tenant count grows"
-- failure mode Chris asked about.
-- ============================================================

select
  t.table_name,
  exists (
    select 1 from pg_indexes i
    where i.schemaname = 'public'
      and i.tablename = t.table_name
      and i.indexdef ilike '%tenant_id%'
  ) as has_tenant_id_index
from (values
  ('business_items'), ('transactions'), ('tasks'), ('client_people'),
  ('business_events'), ('ungani_commitments'), ('registrations'),
  ('documents'), ('ungani_audit_log'), ('ungani_price_lists'),
  ('ungani_quotations'), ('ungani_orders'), ('ungani_customer_invoices')
) as t(table_name)
where exists (select 1 from information_schema.tables it where it.table_schema = 'public' and it.table_name = t.table_name);

-- ============================================================
-- PART 3: real row counts today, for scale-headroom context.
-- (approximate via reltuples - fast, doesn't do a full count scan)
-- ============================================================

select relname as table_name, reltuples::bigint as approx_row_count
from pg_class
where relname in (
  'tenants', 'business_items', 'transactions', 'tasks', 'client_people',
  'business_events', 'registrations', 'ungani_commitments'
)
order by approx_row_count desc;

-- ============================================================
-- PART 4: any RLS policy whose USING/WITH CHECK clause does something
-- more expensive than the standard "tenant_id = get_my_ungani_tenant_id()"
-- shape - e.g. a correlated subquery or join that itself isn't tenant-
-- scoped first, which WOULD scale with total platform data.
-- ============================================================

select
  schemaname, tablename, policyname, cmd,
  qual as using_clause,
  with_check
from pg_policies
where schemaname = 'public'
order by tablename, policyname;
