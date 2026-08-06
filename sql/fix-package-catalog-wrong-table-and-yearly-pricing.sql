-- Fixes a real bug found via user-provided schema diagnostics: TWO
-- separate package tables exist. public.ungani_packages is the real,
-- authoritative one - confirmed by its use throughout tonight's work
-- (user-limit enforcement joins tenants.package_key against it,
-- multi_branch_included gates the multi-branch feature, and its real
-- column list/data matches every price used tonight: Starter 5000,
-- Growth 8500, Business 14000, Custom 0/custom). public.
-- ungani_package_catalog is a second, older/stale table that only
-- get_ungani_package_catalog() reads - and that RPC is called from
-- exactly ONE place in the whole app: admin-billing.html's package
-- dropdown auto-fill (confirmed via grep - not called anywhere else,
-- not dead code, just pointed at the wrong table). This migration:
--   1. Adds real yearly pricing to the CORRECT table (ungani_packages).
--   2. Adds billing_cycle tracking to tenants (which subscription
--      cycle a tenant is actually on - confirmed tenants.package_key
--      is real and already joined against ungani_packages in
--      owner_upsert_ungani_team_member).
--   3. Adds a NEW admin RPC reading the correct table with the correct
--      real column names (monthly_price_ksh, not monthly_price) -
--      deliberately NOT touching/guessing get_ungani_package_catalog()'s
--      actual body, which was never seen literally (only described).
--      admin-billing.html is switched to call the new RPC instead.
--
-- Yearly price formula matches exactly what my-package.html's
-- computeYearlyPrice() already computes client-side (15% off 12
-- months, rounded to the nearest 50) - a GENERATED column guarantees
-- this can never drift from what's actually charged, unlike the
-- earlier client-only version.

-- ============================================================
-- PART A: yearly_price_ksh on the REAL table.
-- ============================================================

alter table public.ungani_packages
  add column if not exists yearly_price_ksh numeric generated always as (
    case
      when monthly_price_ksh is null or monthly_price_ksh = 0 then null
      else round((monthly_price_ksh * 12 * 0.85) / 50) * 50
    end
  ) stored;

-- ============================================================
-- PART B: billing_cycle on tenants - which cycle this tenant is
-- actually subscribed under (separate from ungani_payments.
-- billing_period_start/end, which is the period a specific PAST
-- payment covered).
-- ============================================================

alter table public.tenants
  add column if not exists billing_cycle text not null default 'monthly';

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'tenants_billing_cycle_check'
  ) then
    alter table public.tenants
      add constraint tenants_billing_cycle_check check (billing_cycle in ('monthly', 'yearly'));
  end if;
end $$;

-- ============================================================
-- PART C: new, correctly-sourced admin catalog RPC.
-- ============================================================

create or replace function public.get_admin_ungani_package_catalog()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_packages jsonb;
begin
  if public.is_ungani_admin() is not true then
    return jsonb_build_object('ok', false, 'message', 'Admin access required.');
  end if;

  select jsonb_agg(
    jsonb_build_object(
      'package_key', package_key,
      'package_name', package_name,
      'monthly_price_ksh', monthly_price_ksh,
      'yearly_price_ksh', yearly_price_ksh,
      'onboarding_fee_ksh', onboarding_fee_ksh,
      'user_limit', user_limit,
      'is_custom', is_custom,
      'multi_branch_included', multi_branch_included
    )
    order by sort_order
  )
  into v_packages
  from public.ungani_packages
  where is_active = true;

  return jsonb_build_object('ok', true, 'packages', coalesce(v_packages, '[]'::jsonb));
end;
$function$;

grant execute on function public.get_admin_ungani_package_catalog() to authenticated;

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================

-- 1. Real prices + generated yearly prices, sanity-check against
-- tonight's known figures (Starter 5000->51000, Growth 8500->86700,
-- Business 14000->142800, Custom null->null).
select package_key, package_name, monthly_price_ksh, yearly_price_ksh, is_custom, is_active
from public.ungani_packages
order by sort_order;

-- 2. billing_cycle column + constraint exist.
select column_name, data_type, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'tenants' and column_name = 'billing_cycle';

select conname, pg_get_constraintdef(oid)
from pg_constraint
where conname = 'tenants_billing_cycle_check';

-- 3. New RPC exists + authenticated has EXECUTE.
select routine_name, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name = 'get_admin_ungani_package_catalog'
  and grantee = 'authenticated';
