-- Item 4 (subscription/payment reliability): my-package.html's tier
-- comparison grid currently renders hardcoded JS price constants
-- (monthlyPrice: 5000/8500/14000) with no live read from the real
-- public.ungani_packages table. The only existing catalog RPC,
-- get_admin_ungani_package_catalog(), explicitly requires
-- is_ungani_admin() (see sql/fix-package-catalog-wrong-table-and-yearly-pricing.sql),
-- so a client owner cannot call it. Confirmed live: prices currently
-- match (Starter 5000/51000, Growth 8500/86700, Business 14000/142800,
-- Custom 0/null) but nothing keeps them in sync if admin edits a price -
-- M-Pesa (api/mpesa-stk-push.js) already reads the real table for the
-- actual charge amount, so a drift would mean clients see one price and
-- get charged another.
--
-- This adds a second, non-admin-gated RPC exposing the same package
-- rows. Package pricing is non-sensitive catalog data (no tenant-
-- specific info), so the only gate is "must be authenticated" - same
-- shape as get_admin_ungani_package_catalog() minus the admin check.

create or replace function public.get_ungani_active_packages()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_packages jsonb;
begin
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

grant execute on function public.get_ungani_active_packages() to authenticated;

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================

select get_ungani_active_packages();

select routine_name, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name = 'get_ungani_active_packages'
  and grantee = 'authenticated';
