-- =====================================================================
-- Confirms + applies the fix already proposed in
-- sql/fix-partner-payout-functions-column-rename.sql (written in a
-- prior session, never run). Re-diffed against pg_get_functiondef pulled
-- fresh this session (not trusted from the file alone) - the proposed
-- fix matches the live bodies exactly:
--   partner_commissions.commission_amount -> does not exist live, real
--   column is partner_commissions.amount
--   partner_commissions.paid_at -> does not exist live at all - "when
--   paid" is already fully captured by payout_id -> partner_payouts.payout_date
--
-- admin_get_ungani_partners_overview() was already fixed live (confirmed
-- via live pull) - not touched here. The 3 below are all still broken:
-- get_my_ungani_partner_dashboard() and admin_preview_ungani_partner_
-- payouts() would both 42703 on commission_amount; admin_process_ungani_
-- partner_payouts() would 42703 on EITHER column the moment it's ever
-- called for real (never has been).
--
-- Only addition beyond the proposed file: explicit revoke public/anon,
-- matching this project's current grant-hygiene standard (the original
-- partner-referral-system.sql predates that convention and only ever
-- granted to authenticated).
-- =====================================================================

CREATE OR REPLACE FUNCTION public.get_my_ungani_partner_dashboard()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_partner_id uuid;
  v_tenants jsonb;
  v_commissions jsonb;
  v_payouts jsonb;
begin
  select id into v_partner_id from public.partners where auth_user_id = auth.uid();

  if v_partner_id is null then
    return jsonb_build_object('ok', false, 'message', 'Not a recognized partner.');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'tenant_id', t.id,
    'business_name', t.business_name,
    'account_status', t.account_status,
    'package_key', s.package_key,
    'created_at', t.created_at
  )), '[]'::jsonb)
  into v_tenants
  from public.tenants t
  left join public.ungani_subscriptions s on s.tenant_id = t.id
  where t.referred_by_partner_id = v_partner_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'tenant_id', pc.tenant_id,
    'commission_type', pc.commission_type,
    'commission_amount', pc.amount,
    'status', pc.status,
    'payout_id', pc.payout_id,
    'created_at', pc.created_at
  ) order by pc.created_at desc), '[]'::jsonb)
  into v_commissions
  from public.partner_commissions pc
  where pc.partner_id = v_partner_id;

  select coalesce(jsonb_agg(jsonb_build_object(
    'payout_id', po.id,
    'payout_date', po.payout_date,
    'total_amount', po.total_amount,
    'commission_count', po.commission_count
  ) order by po.payout_date desc), '[]'::jsonb)
  into v_payouts
  from public.partner_payouts po
  where po.partner_id = v_partner_id;

  return jsonb_build_object('ok', true, 'tenants', v_tenants, 'commissions', v_commissions, 'payouts', v_payouts);
end;
$function$;

revoke all on function public.get_my_ungani_partner_dashboard() from public, anon;
grant execute on function public.get_my_ungani_partner_dashboard() to authenticated;

CREATE OR REPLACE FUNCTION public.admin_preview_ungani_partner_payouts()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_result jsonb;
begin
  if not public.is_ungani_admin() then
    return jsonb_build_object('ok', false, 'message', 'Only UNGANI admin can view this.');
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
    'partner_id', p.id,
    'full_name', p.full_name,
    'partner_code', p.partner_code,
    'owed_total', owed.total,
    'commission_count', owed.cnt,
    'breakdown', owed.breakdown
  )), '[]'::jsonb)
  into v_result
  from public.partners p
  join lateral (
    select
      coalesce(sum(pc.amount), 0) as total,
      count(*) as cnt,
      coalesce(jsonb_agg(jsonb_build_object(
        'tenant_id', pc.tenant_id,
        'commission_type', pc.commission_type,
        'commission_amount', pc.amount,
        'created_at', pc.created_at
      )), '[]'::jsonb) as breakdown
    from public.partner_commissions pc
    where pc.partner_id = p.id and pc.status = 'owed'
  ) owed on owed.cnt > 0;

  return jsonb_build_object('ok', true, 'partners', v_result);
end;
$function$;

revoke all on function public.admin_preview_ungani_partner_payouts() from public, anon;
grant execute on function public.admin_preview_ungani_partner_payouts() to authenticated;

CREATE OR REPLACE FUNCTION public.admin_process_ungani_partner_payouts(p_payout_date date DEFAULT CURRENT_DATE)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_partner record;
  v_payout_id uuid;
  v_total numeric;
  v_count int;
  v_processed jsonb := '[]'::jsonb;
begin
  if not public.is_ungani_admin() then
    return jsonb_build_object('ok', false, 'message', 'Only UNGANI admin can do this.');
  end if;

  for v_partner in
    select distinct partner_id from public.partner_commissions where status = 'owed'
  loop
    select coalesce(sum(amount), 0), count(*)
    into v_total, v_count
    from public.partner_commissions
    where partner_id = v_partner.partner_id and status = 'owed';

    if v_count > 0 then
      insert into public.partner_payouts (partner_id, payout_date, total_amount, commission_count)
      values (v_partner.partner_id, p_payout_date, v_total, v_count)
      returning id into v_payout_id;

      update public.partner_commissions
      set status = 'paid', payout_id = v_payout_id
      where partner_id = v_partner.partner_id and status = 'owed';

      v_processed := v_processed || jsonb_build_object(
        'partner_id', v_partner.partner_id,
        'payout_id', v_payout_id,
        'total_amount', v_total,
        'commission_count', v_count
      );
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'payout_date', p_payout_date, 'processed', v_processed);
end;
$function$;

revoke all on function public.admin_process_ungani_partner_payouts(date) from public, anon;
grant execute on function public.admin_process_ungani_partner_payouts(date) to authenticated;

-- Commits the migration above as its own transaction. Without this, a
-- SQL client that sends the whole pasted script as one implicit
-- transaction would have the test block's rollback below undo the
-- CREATE OR REPLACE statements too - confirmed this is exactly what
-- happened on the previous run (no error, but the verification showed
-- the fix never took).
commit;

-- =====================================================================
-- Rolled-back proof. Uses a throwaway TEST partner (not a real one) and
-- a throwaway owed commission against Billy Logistics' real tenant_id
-- (FK target only - no real money/partner data touched, all undone by
-- the final ROLLBACK). Temporarily links the test partner to the
-- current admin's own auth uid so get_my_ungani_partner_dashboard() has
-- a real match to exercise, inside the same rolled-back transaction.
-- =====================================================================

begin;

create temp table test_results (
  seq int generated always as identity,
  scenario text,
  expected text,
  actual text,
  status text
) on commit drop;

do $test$
declare
  v_admin_id uuid;
  v_tenant_id uuid;
  v_partner_id uuid;
  v_commission_id uuid;
  v_result jsonb;
  v_owed_total numeric;
  v_commission_status text;
  v_payout_id uuid;
begin
  select id into v_admin_id from auth.users where lower(email) = 'chris@ungani.com' limit 1;

  if v_admin_id is null then
    raise exception 'Could not find chris@ungani.com in auth.users - aborting test.';
  end if;

  select id into v_tenant_id from public.tenants limit 1;

  if v_tenant_id is null then
    raise exception 'Could not find any tenant for the FK target - aborting test.';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);

  insert into public.partners (full_name, email, partner_code, status, auth_user_id)
  values ('TEST PARTNER (payout fix check)', 'test-partner-payout-check@ungani.com', 'TESTPARTNER' || substr(gen_random_uuid()::text, 1, 8), 'active', v_admin_id)
  returning id into v_partner_id;

  insert into public.partner_commissions (partner_id, tenant_id, commission_type, amount, status)
  values (v_partner_id, v_tenant_id, 'onboarding', 1500, 'owed')
  returning id into v_commission_id;

  -------------------------------------------------------------------
  -- 1. admin_get_ungani_partners_overview() - regression (was already
  -- fixed, confirm the test partner's owed total appears correctly).
  -------------------------------------------------------------------
  begin
    v_result := public.admin_get_ungani_partners_overview();

    insert into test_results (scenario, expected, actual, status) values (
      '1. overview still works (regression)', 'ok=true',
      'ok=' || (v_result->>'ok'),
      case when (v_result->>'ok')::boolean = true then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('1. overview regression', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- 2. admin_preview_ungani_partner_payouts() - was broken (42703 on
  -- commission_amount), must now execute and show the right total.
  -------------------------------------------------------------------
  begin
    v_result := public.admin_preview_ungani_partner_payouts();

    select (p->>'owed_total')::numeric into v_owed_total
    from jsonb_array_elements(v_result->'partners') p
    where (p->>'partner_id')::uuid = v_partner_id;

    insert into test_results (scenario, expected, actual, status) values (
      '2. preview payouts works (was: 42703 commission_amount), owed=1500', 'ok=true, owed_total=1500',
      'ok=' || (v_result->>'ok') || ', owed_total=' || coalesce(v_owed_total::text, 'NULL'),
      case when (v_result->>'ok')::boolean = true and v_owed_total = 1500 then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('2. preview payouts', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- 3. get_my_ungani_partner_dashboard() - was broken (42703 on
  -- commission_amount), must now execute and show the real breakdown.
  -------------------------------------------------------------------
  begin
    v_result := public.get_my_ungani_partner_dashboard();

    insert into test_results (scenario, expected, actual, status) values (
      '3. partner dashboard works (was: 42703 commission_amount)', 'ok=true, 1 commission row',
      'ok=' || (v_result->>'ok') || ', commission_count=' || jsonb_array_length(coalesce(v_result->'commissions', '[]'::jsonb)),
      case when (v_result->>'ok')::boolean = true and jsonb_array_length(coalesce(v_result->'commissions', '[]'::jsonb)) = 1 then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('3. partner dashboard', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- 4. admin_process_ungani_partner_payouts() - the money-mutating
  -- function, never run for real before. Must now execute without the
  -- paid_at 42703, create a real payout row, and mark the commission
  -- 'paid' with the correct payout_id.
  -------------------------------------------------------------------
  begin
    v_result := public.admin_process_ungani_partner_payouts(current_date);

    select status, payout_id into v_commission_status, v_payout_id
    from public.partner_commissions where id = v_commission_id;

    insert into test_results (scenario, expected, actual, status) values (
      '4. process payouts works (was: would 42703 on paid_at)', 'ok=true, status=paid, payout_id set',
      'ok=' || (v_result->>'ok') || ', status=' || v_commission_status || ', payout_id set=' || (v_payout_id is not null),
      case when (v_result->>'ok')::boolean = true and v_commission_status = 'paid' and v_payout_id is not null then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('4. process payouts', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- 5. The payout row itself has the correct total/count.
  -------------------------------------------------------------------
  begin
    insert into test_results (scenario, expected, actual, status)
    select
      '5. payout row created with correct total/count',
      'total_amount=1500, commission_count=1',
      'total_amount=' || total_amount || ', commission_count=' || commission_count,
      case when total_amount = 1500 and commission_count = 1 then 'PASS' else 'FAIL' end
    from public.partner_payouts where id = v_payout_id;
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('5. payout row correct', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- 6. Re-running process payouts after everything is already paid
  -- processes nothing (no owed commissions left for the test partner).
  -------------------------------------------------------------------
  begin
    v_result := public.admin_process_ungani_partner_payouts(current_date);

    insert into test_results (scenario, expected, actual, status) values (
      '6. re-running process payouts finds nothing left to pay', 'ok=true, processed has no entry for test partner',
      'ok=' || (v_result->>'ok') || ', processed=' || (v_result->'processed' @> jsonb_build_array(jsonb_build_object('partner_id', v_partner_id::text)))::text,
      case when (v_result->>'ok')::boolean = true and not (v_result->'processed' @> jsonb_build_array(jsonb_build_object('partner_id', v_partner_id::text))) then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('6. re-run processes nothing', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  perform set_config('request.jwt.claims', '', true);
end;
$test$;

select scenario, expected, actual, status from test_results order by seq;

rollback;

-- =====================================================================
-- Combined verification SELECT (post-migration, persists - run last).
-- =====================================================================

select 'overload_count:get_my_ungani_partner_dashboard' as check_name, '1' as expected,
       count(*)::text as actual
from pg_proc
where proname = 'get_my_ungani_partner_dashboard' and pronamespace = 'public'::regnamespace

union all

select 'overload_count:admin_preview_ungani_partner_payouts', '1',
       count(*)::text
from pg_proc
where proname = 'admin_preview_ungani_partner_payouts' and pronamespace = 'public'::regnamespace

union all

select 'overload_count:admin_process_ungani_partner_payouts', '1',
       count(*)::text
from pg_proc
where proname = 'admin_process_ungani_partner_payouts' and pronamespace = 'public'::regnamespace

union all

select 'dashboard_no_longer_references_commission_amount_column', 'true',
       (pg_get_functiondef(p.oid) not like '%pc.commission_amount%')::text
from pg_proc p
where p.proname = 'get_my_ungani_partner_dashboard' and p.pronamespace = 'public'::regnamespace

union all

select 'preview_no_longer_references_commission_amount_column', 'true',
       (pg_get_functiondef(p.oid) not like '%pc.commission_amount%')::text
from pg_proc p
where p.proname = 'admin_preview_ungani_partner_payouts' and p.pronamespace = 'public'::regnamespace

union all

select 'process_no_longer_references_paid_at', 'true',
       (pg_get_functiondef(p.oid) not like '%paid_at%')::text
from pg_proc p
where p.proname = 'admin_process_ungani_partner_payouts' and p.pronamespace = 'public'::regnamespace

union all

select 'process_no_longer_references_commission_amount_column', 'true',
       (pg_get_functiondef(p.oid) not like '%sum(commission_amount)%')::text
from pg_proc p
where p.proname = 'admin_process_ungani_partner_payouts' and p.pronamespace = 'public'::regnamespace

union all

select 'dashboard_public_revoked', 'false',
       has_function_privilege('public', p.oid, 'EXECUTE')::text
from pg_proc p
where p.proname = 'get_my_ungani_partner_dashboard' and p.pronamespace = 'public'::regnamespace

union all

select 'preview_public_revoked', 'false',
       has_function_privilege('public', p.oid, 'EXECUTE')::text
from pg_proc p
where p.proname = 'admin_preview_ungani_partner_payouts' and p.pronamespace = 'public'::regnamespace

union all

select 'process_public_revoked', 'false',
       has_function_privilege('public', p.oid, 'EXECUTE')::text
from pg_proc p
where p.proname = 'admin_process_ungani_partner_payouts' and p.pronamespace = 'public'::regnamespace;
