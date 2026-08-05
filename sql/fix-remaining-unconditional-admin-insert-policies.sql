-- UNGANI OS: fix the same missed unconditional admin INSERT policy on the
-- remaining 5 operational tables - confirmed live via the catalog-driven
-- audit in sql/fix-documents-unconditional-admin-insert.sql (documents
-- itself already fixed by that file).
--
-- Confirmed bugs (all INSERT, permissive, qual = is_ungani_admin() only,
-- no reference to ungani_support_access_grants):
--   business_items  -> admin_can_create_items_management
--   business_records -> admin_can_create_records_management
--   client_people   -> admin_can_create_client_people
--   tasks           -> admin_can_create_tasks_management
--   transactions    -> admin_can_create_money_management
--
-- Same root cause as documents: the original "drop the 11 unconditional
-- write policies" sweep only matched ungani_admin_manage_% and
-- admin_can_update_%_management - a third naming pattern
-- (admin_can_create_%[_management]) existed on every one of these 6
-- tables and was never in scope. Admin could insert into any tenant's
-- items/records/people/tasks/transactions regardless of Support Access
-- grant state, the whole time.
--
-- Same dynamic, catalog-driven drop as before - not static name literals -
-- given `drop policy if exists "<name>"` already silently no-op'd once
-- tonight on this exact policy set.

do $$
declare
  r record;
  dropped_count int := 0;
begin
  for r in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and (
        (tablename = 'business_items' and policyname = 'admin_can_create_items_management')
        or (tablename = 'business_records' and policyname = 'admin_can_create_records_management')
        or (tablename = 'client_people' and policyname = 'admin_can_create_client_people')
        or (tablename = 'tasks' and policyname = 'admin_can_create_tasks_management')
        or (tablename = 'transactions' and policyname = 'admin_can_create_money_management')
      )
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
    dropped_count := dropped_count + 1;
    raise notice 'Dropped policy "%" on %.%', r.policyname, r.schemaname, r.tablename;
  end loop;

  raise notice 'Total policies dropped: %', dropped_count;

  if dropped_count <> 5 then
    raise notice 'WARNING: expected to drop exactly 5 policies, actually dropped %. Check the verification query below for what remains.', dropped_count;
  end if;
end $$;

-- ============================================================================
-- VERIFICATION 1 - expect ZERO rows. Re-runs the same catalog-driven
-- audit (not name-pattern matching) across all 6 tables - if this finds
-- anything now, including on documents, tell me the exact row and I'll
-- investigate further rather than assume this is complete.
-- ============================================================================

select
  tablename,
  policyname,
  cmd,
  permissive,
  qual as using_expr,
  with_check as with_check_expr
from pg_policies
where schemaname = 'public'
  and tablename in ('business_items', 'business_records', 'client_people', 'documents', 'tasks', 'transactions')
  and (
    (qual is not null and qual ilike '%is_ungani_admin%')
    or (with_check is not null and with_check ilike '%is_ungani_admin%')
  )
  and (coalesce(qual, '') || coalesce(with_check, '')) not ilike '%ungani_support_access_grants%';

-- ============================================================================
-- VERIFICATION 2 - confirm the intentional admin_can_read_* SELECT
-- policies are untouched (expect 6 rows, one per table, unchanged from
-- before).
-- ============================================================================

select tablename, policyname, cmd, qual
from pg_policies
where schemaname = 'public'
  and tablename in ('business_items', 'business_records', 'client_people', 'documents', 'tasks', 'transactions')
  and policyname like 'admin_can_read_%'
order by tablename;

-- ============================================================================
-- VERIFICATION 3 - confirm the grant-gated Support Access INSERT/UPDATE/
-- SELECT policies are untouched (expect these to still be present,
-- unchanged - the actual gate that should be the ONLY way admin gets
-- write access now).
-- ============================================================================

select tablename, policyname, cmd
from pg_policies
where schemaname = 'public'
  and tablename in ('business_items', 'business_records', 'client_people', 'documents', 'tasks', 'transactions')
  and (
    (qual is not null and qual ilike '%ungani_support_access_grants%')
    or (with_check is not null and with_check ilike '%ungani_support_access_grants%')
  )
order by tablename, cmd;
