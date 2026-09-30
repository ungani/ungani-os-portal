-- =====================================================================
-- sql/rls-wrap-live-dynamic.sql
--
-- Wraps is_ungani_admin() / get_my_ungani_tenant_id() calls in RLS
-- policies as `(select public.is_ungani_admin())` /
-- `(select public.get_my_ungani_tenant_id())` so Postgres evaluates
-- them once per query instead of once per row.
--
-- Reads pg_policies LIVE and only touches whatever is actually still
-- unwrapped in the real database right now - no dependency on
-- sql/*.sql migration text, which can drift from the live schema
-- (confirmed already for partner_commissions and other functions).
--
-- Uses ALTER POLICY (not drop+create), so policy name, command, and
-- role list are all left exactly as they are today - only the
-- USING/WITH CHECK expression text changes, and only the two function
-- calls within it.
--
-- CASE FIX: Postgres deparses an already-wrapped call as
-- "( SELECT is_ungani_admin() AS is_ungani_admin)" - uppercase SELECT,
-- auto-generated alias. All matching below is case-insensitive (gi
-- flag / ~* operator) so already-wrapped calls are correctly
-- recognized and never double-wrapped, and Section 3 never
-- miscounts them as still-unwrapped.
--
-- SCHEMA SCOPE: Section 2 (the actual ALTER POLICY pass) is scoped to
-- schemaname = 'public' only. storage.objects is owned by
-- supabase_storage_admin - ALTER POLICY there would likely fail with
-- "must be owner of relation objects", and since Section 2 runs as one
-- DO block/transaction, a single failure would roll back every fix
-- already applied in that same run. Any storage-schema policies using
-- these functions are listed separately, report-only, below Section 1
-- - fix those (if wanted) via the Supabase Dashboard's Storage >
-- Policies editor, which runs with correct ownership.
--
-- Run in order, each as its own statement:
--   SECTION 1  - dry run + baseline public-policy count (read-only)
--   STORAGE    - report-only listing, not touched by Section 2
--   SECTION 2  - the real fix, public schema only (idempotent)
--   SECTION 3  - verification: one row, total_policies + remaining_unwrapped
-- =====================================================================


-- =====================================================================
-- SECTION 1: DRY RUN (public schema only) + baseline count
-- =====================================================================

with candidates as (
  select
    schemaname, tablename, policyname, cmd,
    qual as old_using,
    with_check as old_with_check,
    case when qual is not null then
      regexp_replace(
        regexp_replace(qual, '(?<!select )\m(public\.)?is_ungani_admin\(\)', '(select public.is_ungani_admin())', 'gi'),
        '(?<!select )\m(public\.)?get_my_ungani_tenant_id\(\)', '(select public.get_my_ungani_tenant_id())', 'gi'
      )
    end as new_using,
    case when with_check is not null then
      regexp_replace(
        regexp_replace(with_check, '(?<!select )\m(public\.)?is_ungani_admin\(\)', '(select public.is_ungani_admin())', 'gi'),
        '(?<!select )\m(public\.)?get_my_ungani_tenant_id\(\)', '(select public.get_my_ungani_tenant_id())', 'gi'
      )
    end as new_with_check
  from pg_policies
  where schemaname = 'public'
)
select schemaname, tablename, policyname, cmd, old_using, new_using, old_with_check, new_with_check
from candidates
where (old_using is not null and old_using is distinct from new_using)
   or (old_with_check is not null and old_with_check is distinct from new_with_check)
order by tablename, policyname;

select count(*) as total_public_policies_before
from pg_policies
where schemaname = 'public';


-- =====================================================================
-- STORAGE SCHEMA - REPORT ONLY. Not touched by Section 2.
-- =====================================================================

select
  schemaname, tablename, policyname, cmd,
  qual as old_using,
  with_check as old_with_check
from pg_policies
where schemaname = 'storage'
  and (
    (qual is not null and qual ~* '(?<!select )\m(public\.)?(is_ungani_admin|get_my_ungani_tenant_id)\(\)')
    or (with_check is not null and with_check ~* '(?<!select )\m(public\.)?(is_ungani_admin|get_my_ungani_tenant_id)\(\)')
  )
order by tablename, policyname;


-- =====================================================================
-- SECTION 2: THE REAL FIX - public schema only.
-- Idempotent: re-running this after it already fixed everything is a
-- safe no-op.
-- =====================================================================

do $$
declare
  r record;
  new_qual text;
  new_with_check text;
  alter_sql text;
  fixed_count int := 0;
begin
  for r in
    select schemaname, tablename, policyname, qual, with_check
    from pg_policies
    where schemaname = 'public'
  loop
    new_qual := r.qual;
    new_with_check := r.with_check;

    if new_qual is not null then
      new_qual := regexp_replace(new_qual, '(?<!select )\m(public\.)?is_ungani_admin\(\)', '(select public.is_ungani_admin())', 'gi');
      new_qual := regexp_replace(new_qual, '(?<!select )\m(public\.)?get_my_ungani_tenant_id\(\)', '(select public.get_my_ungani_tenant_id())', 'gi');
    end if;

    if new_with_check is not null then
      new_with_check := regexp_replace(new_with_check, '(?<!select )\m(public\.)?is_ungani_admin\(\)', '(select public.is_ungani_admin())', 'gi');
      new_with_check := regexp_replace(new_with_check, '(?<!select )\m(public\.)?get_my_ungani_tenant_id\(\)', '(select public.get_my_ungani_tenant_id())', 'gi');
    end if;

    if (new_qual is distinct from r.qual) or (new_with_check is distinct from r.with_check) then
      alter_sql := format('alter policy %I on %I.%I', r.policyname, r.schemaname, r.tablename);

      if new_qual is distinct from r.qual then
        alter_sql := alter_sql || format(' using (%s)', new_qual);
      end if;

      if new_with_check is distinct from r.with_check then
        alter_sql := alter_sql || format(' with check (%s)', new_with_check);
      end if;

      raise notice 'Fixing %.% (%): %', r.schemaname, r.tablename, r.policyname, alter_sql;
      execute alter_sql;
      fixed_count := fixed_count + 1;
    end if;
  end loop;

  raise notice 'Done. % polic(ies) altered.', fixed_count;
end $$;


-- =====================================================================
-- SECTION 3: VERIFICATION - one row, both counts together.
-- remaining_unwrapped must be 0. total_policies must match the
-- total_public_policies_before value from Section 1.
-- =====================================================================

select
  (select count(*) from pg_policies where schemaname = 'public') as total_policies,
  (select count(*) from pg_policies where schemaname = 'public' and (
    coalesce(qual, '') ~* '(?<!select )\m(public\.)?(is_ungani_admin|get_my_ungani_tenant_id)\(\)'
    or coalesce(with_check, '') ~* '(?<!select )\m(public\.)?(is_ungani_admin|get_my_ungani_tenant_id)\(\)'
  )) as remaining_unwrapped;
