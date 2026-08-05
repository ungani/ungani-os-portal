-- UNGANI OS: fix the missed admin_can_create_documents_management policy
-- + a catalog-driven audit for the same bug class on the other 5 tables.
--
-- Confirmed live: RLS is enabled on documents, and every policy is correct
-- EXCEPT admin_can_create_documents_management (INSERT, permissive,
-- qual = is_ungani_admin(), no grant check) - this was never part of the
-- original "drop the 11 unconditional write policies" sweep, because that
-- sweep matched on two specific name patterns (ungani_admin_manage_% and
-- admin_can_update_%_management) and this policy uses a third pattern
-- (admin_can_create_%_management) that search never considered. This
-- explains the "documents behaves independently of grant state" symptom
-- exactly - on writes/inserts, not reads (admin_can_read_documents_
-- management is unconditional by deliberate design, not a bug).
--
-- ============================================================================
-- STEP 1: drop the confirmed bug on documents.
-- ============================================================================
--
-- Using the same dynamic, catalog-driven drop as sql/fix-part-b-drop-
-- admin-write-policies-v2.sql, not a static `drop policy if exists
-- "<name>"` - that exact statement form already silently no-op'd once
-- tonight on this same policy set, so a real name-match confirmed via
-- pg_policies itself is the only trustworthy way to do this.

do $$
declare
  r record;
  dropped_count int := 0;
begin
  for r in
    select schemaname, tablename, policyname
    from pg_policies
    where schemaname = 'public'
      and tablename = 'documents'
      and policyname = 'admin_can_create_documents_management'
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
    dropped_count := dropped_count + 1;
    raise notice 'Dropped policy "%" on %.%', r.policyname, r.schemaname, r.tablename;
  end loop;

  if dropped_count = 0 then
    raise notice 'WARNING: admin_can_create_documents_management not found - already gone, or the name does not match exactly. Check the audit query below.';
  end if;
end $$;

-- ============================================================================
-- STEP 2: catalog-driven audit for the same bug class on all 6 tables.
-- ============================================================================
--
-- Not another name-pattern guess (that already missed this exact policy
-- once) - this inspects the REAL qual/with_check text of every policy on
-- all 6 operational tables and flags any that grant is_ungani_admin() a
-- bypass with no reference to the grants table at all. This will also
-- correctly re-surface the intentional, deliberately-preserved
-- admin_can_read_*_management (SELECT) policies - those are fine, keep
-- them. What matters is whether anything with cmd IN ('INSERT','UPDATE',
-- 'ALL') shows up here that isn't already accounted for.
--
-- Run this and send back every row - do not drop anything from this list
-- without confirming first, the same way admin_can_create_documents_
-- management itself was found and confirmed before writing STEP 1 above.

select
  tablename,
  policyname,
  cmd,
  permissive,
  (qual is not null and qual ilike '%is_ungani_admin%') as admin_in_using,
  (with_check is not null and with_check ilike '%is_ungani_admin%') as admin_in_with_check,
  (coalesce(qual, '') || coalesce(with_check, '')) ilike '%ungani_support_access_grants%' as references_grant_table,
  qual as using_expr,
  with_check as with_check_expr
from pg_policies
where schemaname = 'public'
  and tablename in ('business_items', 'business_records', 'client_people', 'documents', 'tasks', 'transactions')
  and (
    (qual is not null and qual ilike '%is_ungani_admin%')
    or (with_check is not null and with_check ilike '%is_ungani_admin%')
  )
  and (coalesce(qual, '') || coalesce(with_check, '')) not ilike '%ungani_support_access_grants%'
order by tablename, cmd, policyname;

-- ============================================================================
-- Verification - confirm the documents fix landed.
-- ============================================================================

select policyname, cmd, permissive, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'documents'
order by cmd, policyname;
