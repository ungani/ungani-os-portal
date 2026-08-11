-- Read-only. Confirms exactly what will be deleted for the "UNGANI QA
-- Test - DELETE ME" tenant before writing the actual delete script -
-- same 3-angle pattern as sql/tenant-cleanup-verify.sql /
-- sql/ice-cold-logistics-remaining-check.sql:
--   1. Find the real tenant row + its id/email.
--   2. Dynamic sweep (via information_schema, not a hand-maintained
--      table list) across EVERY table with a tenant_id column, so no
--      table gets silently missed the way registrations did in the
--      original 12-tenant cleanup.
--   3. registrations - only ever linked informally by email, not tenant_id.
-- Paste back the full output before I write the delete script.

-- 1. The tenant itself.
select id, business_name, business_email, business_type_key,
       account_status, package_key, created_at
from public.tenants
where business_name = 'UNGANI QA Test - DELETE ME';

-- 2. Dynamic sweep - every table in public with a tenant_id column,
-- row count for this specific tenant.
do $$
declare
  v_tenant_id uuid;
  r record;
  v_count bigint;
begin
  select id into v_tenant_id from public.tenants where business_name = 'UNGANI QA Test - DELETE ME';

  if v_tenant_id is null then
    raise notice 'Tenant not found - nothing to sweep.';
    return;
  end if;

  raise notice 'Tenant id: %', v_tenant_id;

  for r in
    select c.table_name
    from information_schema.columns c
    where c.table_schema = 'public'
      and c.column_name = 'tenant_id'
    order by c.table_name
  loop
    execute format('select count(*) from public.%I where tenant_id = %L', r.table_name, v_tenant_id)
      into v_count;

    if v_count > 0 then
      raise notice '  % : % row(s)', r.table_name, v_count;
    end if;
  end loop;
end $$;

-- 3. registrations - informal link by email, not tenant_id (same gap
-- that left 2 orphaned rows behind in the Ice Cold Logistics cleanup).
select id, business_name, email, status, auth_user_id, created_at
from public.registrations
where business_name = 'UNGANI QA Test - DELETE ME'
   or email = (select business_email from public.tenants where business_name = 'UNGANI QA Test - DELETE ME');

-- 4. Any Supabase Auth user tied to this tenant's email (for awareness -
-- deleting the auth.users row itself needs the Auth Admin API or the
-- dashboard, not a plain SQL delete, so this is informational only).
select id, email, created_at, last_sign_in_at
from auth.users
where email = (select business_email from public.tenants where business_name = 'UNGANI QA Test - DELETE ME');
