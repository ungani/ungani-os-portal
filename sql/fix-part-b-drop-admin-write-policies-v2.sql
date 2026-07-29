-- Corrected re-run of PART B from sql/fix-support-access-admin-scoping-
-- and-gate-writes.sql. The original static `drop policy if exists
-- "<name>" on ...` statements ran without error but had zero effect -
-- confirmed by re-querying pg_policies afterward and finding all 11
-- policies still present. `drop policy if exists` never throws when the
-- name doesn't match - it silently no-ops, which is exactly consistent
-- with a subtle name mismatch (stray whitespace, encoding difference,
-- something not visible in a plain-text/CSV render) rather than a
-- script-execution problem, since Part A's statements (earlier in the
-- same script) and the verification queries (later in the same script)
-- both ran successfully.
--
-- Fix: instead of retyping the policy name as a literal, pull the REAL
-- name straight from pg_policies and drop using THAT value via dynamic
-- SQL - this makes the match authoritative (driven by Postgres's own
-- catalog) rather than dependent on a hand-transcribed string matching
-- byte-for-byte. Uses %I (identifier) for policyname, schemaname, AND
-- tablename - all three are identifiers, never %L - learned directly
-- from the %L/%I mixup caught and avoided in the original sql/ungani-
-- support-access.sql draft.
--
-- Safe to re-run - if a listed policy is already gone (e.g. because it
-- somehow WAS already dropped for some rows), the loop just finds fewer
-- matches and drops nothing extra.

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
        (tablename = 'business_items' and policyname in ('ungani_admin_manage_business_items', 'admin_can_update_items_management'))
        or (tablename = 'business_records' and policyname in ('ungani_admin_manage_business_records', 'admin_can_update_records_management'))
        or (tablename = 'client_people' and policyname in ('admin_can_update_client_people'))
        or (tablename = 'documents' and policyname in ('ungani_admin_manage_documents', 'admin_can_update_documents_management'))
        or (tablename = 'tasks' and policyname in ('ungani_admin_manage_tasks', 'admin_can_update_tasks_management'))
        or (tablename = 'transactions' and policyname in ('ungani_admin_manage_transactions', 'admin_can_update_money_management'))
      )
  loop
    execute format('drop policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);
    dropped_count := dropped_count + 1;
    raise notice 'Dropped policy "%" on %.%', r.policyname, r.schemaname, r.tablename;
  end loop;

  raise notice 'Total policies dropped: %', dropped_count;

  if dropped_count <> 11 then
    raise notice 'WARNING: expected to drop exactly 11 policies, actually dropped %. Check the verification query below for what remains.', dropped_count;
  end if;
end $$;

-- =====================================================================
-- VERIFICATION - run after the above.
-- =====================================================================

-- Expect ZERO rows - if anything shows up here, tell me the exact
-- tablename/policyname/qual and I'll investigate further (rather than
-- assume the dynamic drop above worked without checking).
select tablename, policyname, cmd, qual
from pg_policies
where schemaname = 'public'
  and tablename in ('business_items', 'business_records', 'client_people', 'documents', 'tasks', 'transactions')
  and (
    policyname like 'ungani_admin_manage_%'
    or policyname like 'admin_can_update_%_management'
    or policyname = 'admin_can_update_client_people'
  )
order by tablename, policyname;

-- Confirm the read policies are untouched (expect these to still be
-- present - this list should be unchanged from before).
select tablename, policyname, cmd, qual
from pg_policies
where schemaname = 'public'
  and tablename in ('business_items', 'business_records', 'client_people', 'documents', 'tasks', 'transactions')
  and policyname like 'admin_can_read_%'
order by tablename, policyname;
