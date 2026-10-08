-- =====================================================================
-- Item 1 billing - scenario test script. Run AFTER
-- sql/item1-subscription-billing-fix-v2.sql has been applied.
--
-- Everything happens inside BEGIN ... ROLLBACK - nothing is kept. It
-- uses the REAL Billy Logistics tenant (ungani0722@gmail.com) and the
-- REAL configured starter/business package prices, but every mutation
-- (subscription state, payments, a throwaway partner, a temporary branch
-- flag) is undone by the final ROLLBACK.
--
-- auth.uid() is null by default in a plain SQL session (no JWT) - that
-- IS the service_role/webhook context, so most scenarios need no special
-- setup for S13. Where a scenario needs to run AS Billy's owner (S10,
-- S14, which call client_request_ungani_package_payment - that function
-- resolves the caller via get_my_ungani_tenant_id()/auth.uid()), the
-- script temporarily sets request.jwt.claims via set_config(...,true)
-- (transaction-scoped) to Billy's real owner id, then clears it again
-- immediately after.
--
-- Run this whole file as one script. The final SELECT (after ROLLBACK
-- would normally undo everything - the SELECT runs BEFORE the ROLLBACK,
-- so its result is what you paste back) prints one row per scenario:
-- scenario | expected | actual | status.
--
-- FIXED 2026-10-07: two scenarios in the previous version were stale
-- against the real live schema (confirmed via a real run against the
-- live DB, not guessed):
--   S11 inserted a literal 'zzz_nonexistent_package' package_key, which
--   violates ungani_payments' own check constraint before the
--   price-lookup logic this scenario means to test ever runs. Fixed by
--   using 'growth' - a real package_key value the check constraint
--   accepts and which NO OTHER scenario in this script touches - and
--   temporarily deleting its own ungani_packages row for the duration of
--   this one scenario (restored immediately after; the whole
--   transaction also rolls back regardless). That reproduces "price
--   unavailable" as the pricing function would actually hit it: a
--   package_key the payments table accepts but with no matching pricing
--   row, not a value the table itself refuses to store.
--   S12 inserted a partners row with only (status, onboarding_rate,
--   ongoing_rate) - the real partners table (sql/partner-referral-system.sql)
--   also requires partner_code, full_name, and email as not null. Fixed
--   by supplying all three with obvious disposable test values.
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
  v_tenant_id uuid;
  v_owner_id uuid;
  v_admin_id uuid;

  v_starter_total numeric;
  v_business_total numeric;

  v_payment_id uuid;
  v_payment_id_2 uuid;
  v_payment_id_3 uuid;
  v_result jsonb;
  v_sub public.ungani_subscriptions;
  v_payment public.ungani_payments;

  v_baseline_expired timestamptz := now() - interval '1 day';
  v_baseline_10left timestamptz := now() + interval '10 days';

  v_partial1 numeric;
  v_partial2 numeric;
  v_partial_biz numeric;
  v_expected_ends timestamptz;

  v_flag_id uuid;
  v_dup_ref text;

  v_partner_id uuid;
  v_commission_amt numeric;

  v_automation_payment_id uuid;
  v_pending_count int;
begin
  -------------------------------------------------------------------
  -- SETUP: resolve Billy Logistics tenant + owner + admin, neutralize
  -- branch add-on so prices are clean package prices only.
  -------------------------------------------------------------------
  select id into v_owner_id from auth.users where lower(email) = 'ungani0722@gmail.com' limit 1;
  select id into v_admin_id from auth.users where lower(email) = 'chris@ungani.com' limit 1;

  if v_owner_id is null then
    raise exception 'Could not find Billy Logistics owner (ungani0722@gmail.com) in auth.users - aborting test.';
  end if;
  if v_admin_id is null then
    raise exception 'Could not find admin (chris@ungani.com) in auth.users - aborting test.';
  end if;

  -- Resolve tenant via get_my_ungani_tenant_id() using the owner's own
  -- identity, so the test uses EXACTLY the same resolution path the real
  -- app uses - not a guessed join.
  perform set_config('request.jwt.claims', json_build_object('sub', v_owner_id::text, 'role', 'authenticated')::text, true);
  v_tenant_id := public.get_my_ungani_tenant_id();
  perform set_config('request.jwt.claims', '', true);

  if v_tenant_id is null then
    raise exception 'Could not resolve a tenant_id for the Billy Logistics owner - aborting test.';
  end if;

  insert into public.ungani_subscriptions (tenant_id) values (v_tenant_id) on conflict (tenant_id) do nothing;

  -- Neutralize the branch add-on for the duration of this transaction so
  -- expected totals are clean package prices (this is rolled back).
  update public.branches set is_grandfathered_free = true where tenant_id = v_tenant_id;

  v_starter_total := (public.calculate_ungani_subscription_amount(v_tenant_id, 'starter')->>'total_amount')::numeric;
  v_business_total := (public.calculate_ungani_subscription_amount(v_tenant_id, 'business')->>'total_amount')::numeric;

  if v_starter_total is null or v_business_total is null then
    raise exception 'starter/business package prices are not configured - cannot run scenarios.';
  end if;

  -------------------------------------------------------------------
  -- S1: on-time full payment -> exactly 1 period, package unchanged.
  -------------------------------------------------------------------
  begin
    update public.ungani_subscriptions set
      package_key = 'starter', subscription_status = 'active', payment_status = 'paid',
      subscription_ends_at = v_baseline_expired, period_amount_due_ksh = null, period_amount_paid_ksh = 0,
      period_package_key = null, credit_balance_ksh = 0, pending_downgrade_package_key = null,
      pending_downgrade_requested_at = null, user_limit = 2, updated_at = now()
    where tenant_id = v_tenant_id;

    insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
    values (v_tenant_id, 'starter', v_starter_total, 'KES', 'paid', now(), 'TEST-S1-' || gen_random_uuid(), now(), now())
    returning id into v_payment_id;

    perform public.set_ungani_subscription_period_from_payment(v_payment_id);

    select * into v_sub from public.ungani_subscriptions where tenant_id = v_tenant_id;
    v_expected_ends := now() + interval '1 month';

    insert into test_results (scenario, expected, actual, status) values (
      'S1 on-time full payment',
      'package=starter, credit=0, ends~' || v_expected_ends,
      'package=' || v_sub.package_key || ', credit=' || v_sub.credit_balance_ksh || ', ends=' || v_sub.subscription_ends_at,
      case when v_sub.package_key = 'starter' and v_sub.credit_balance_ksh = 0
             and abs(extract(epoch from (v_sub.subscription_ends_at - v_expected_ends))) < 60
           then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S1 on-time full payment', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S2: early renewal with 10 days left -> new end = old end + 1 period.
  -------------------------------------------------------------------
  begin
    update public.ungani_subscriptions set
      package_key = 'starter', subscription_status = 'active', payment_status = 'paid',
      subscription_ends_at = v_baseline_10left, period_amount_due_ksh = null, period_amount_paid_ksh = 0,
      period_package_key = null, credit_balance_ksh = 0, pending_downgrade_package_key = null,
      pending_downgrade_requested_at = null, updated_at = now()
    where tenant_id = v_tenant_id;

    insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
    values (v_tenant_id, 'starter', v_starter_total, 'KES', 'paid', now(), 'TEST-S2-' || gen_random_uuid(), now(), now())
    returning id into v_payment_id;

    perform public.set_ungani_subscription_period_from_payment(v_payment_id);

    select * into v_sub from public.ungani_subscriptions where tenant_id = v_tenant_id;
    v_expected_ends := v_baseline_10left + interval '1 month';

    insert into test_results (scenario, expected, actual, status) values (
      'S2 early renewal, 10 days left',
      'ends = old_end + 1 month = ' || v_expected_ends,
      'ends = ' || v_sub.subscription_ends_at,
      case when abs(extract(epoch from (v_sub.subscription_ends_at - v_expected_ends))) < 5 then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S2 early renewal', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S3 + S4: partial then completing payment, same package.
  -------------------------------------------------------------------
  begin
    update public.ungani_subscriptions set
      package_key = 'starter', subscription_status = 'active', payment_status = 'paid',
      subscription_ends_at = v_baseline_expired, period_amount_due_ksh = null, period_amount_paid_ksh = 0,
      period_package_key = null, credit_balance_ksh = 0, pending_downgrade_package_key = null,
      pending_downgrade_requested_at = null, updated_at = now()
    where tenant_id = v_tenant_id;

    v_partial1 := round(v_starter_total / 3.0);

    insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
    values (v_tenant_id, 'starter', v_partial1, 'KES', 'paid', now(), 'TEST-S3-' || gen_random_uuid(), now(), now())
    returning id into v_payment_id;

    perform public.set_ungani_subscription_period_from_payment(v_payment_id);

    select * into v_sub from public.ungani_subscriptions where tenant_id = v_tenant_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S3 partial payment (1/3 of due)',
      'status=partial, package=starter, paid_so_far=' || v_partial1 || ', due=' || v_starter_total,
      'status=' || v_sub.payment_status || ', package=' || v_sub.package_key || ', paid_so_far=' || v_sub.period_amount_paid_ksh || ', due=' || v_sub.period_amount_due_ksh,
      case when v_sub.payment_status = 'partial' and v_sub.package_key = 'starter'
             and v_sub.period_amount_paid_ksh = v_partial1 and v_sub.period_amount_due_ksh = v_starter_total
           then 'PASS' else 'FAIL' end
    );

    v_partial2 := v_starter_total - v_partial1 + round(v_starter_total / 6.0);

    insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
    values (v_tenant_id, 'starter', v_partial2, 'KES', 'paid', now(), 'TEST-S4-' || gen_random_uuid(), now(), now())
    returning id into v_payment_id_2;

    perform public.set_ungani_subscription_period_from_payment(v_payment_id_2);

    select * into v_sub from public.ungani_subscriptions where tenant_id = v_tenant_id;
    v_expected_ends := now() + interval '1 month';

    insert into test_results (scenario, expected, actual, status) values (
      'S4 completing payment -> extended, credit left over',
      'status=paid, package=starter, credit=' || round(v_starter_total / 6.0) || ', ends~' || v_expected_ends,
      'status=' || v_sub.payment_status || ', package=' || v_sub.package_key || ', credit=' || v_sub.credit_balance_ksh || ', ends=' || v_sub.subscription_ends_at,
      case when v_sub.payment_status = 'paid' and v_sub.package_key = 'starter'
             and v_sub.credit_balance_ksh = round(v_starter_total / 6.0)
             and abs(extract(epoch from (v_sub.subscription_ends_at - v_expected_ends))) < 60
           then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S3/S4 partial then complete', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S5: prepay exactly 3 periods -> 3 periods, 0 credit.
  -------------------------------------------------------------------
  begin
    update public.ungani_subscriptions set
      package_key = 'starter', subscription_status = 'active', payment_status = 'paid',
      subscription_ends_at = v_baseline_expired, period_amount_due_ksh = null, period_amount_paid_ksh = 0,
      period_package_key = null, credit_balance_ksh = 0, pending_downgrade_package_key = null,
      pending_downgrade_requested_at = null, updated_at = now()
    where tenant_id = v_tenant_id;

    insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
    values (v_tenant_id, 'starter', v_starter_total * 3, 'KES', 'paid', now(), 'TEST-S5-' || gen_random_uuid(), now(), now())
    returning id into v_payment_id;

    perform public.set_ungani_subscription_period_from_payment(v_payment_id);

    select * into v_sub from public.ungani_subscriptions where tenant_id = v_tenant_id;
    v_expected_ends := now() + interval '3 months';

    insert into test_results (scenario, expected, actual, status) values (
      'S5 prepay 3 periods',
      'credit=0, ends~' || v_expected_ends,
      'credit=' || v_sub.credit_balance_ksh || ', ends=' || v_sub.subscription_ends_at,
      case when v_sub.credit_balance_ksh = 0 and abs(extract(epoch from (v_sub.subscription_ends_at - v_expected_ends))) < 60
           then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S5 prepay 3 periods', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S6: upgrade Starter -> Business, pay full Business price -> exactly
  -- 1 Business period, no extra period.
  -------------------------------------------------------------------
  begin
    update public.ungani_subscriptions set
      package_key = 'starter', subscription_status = 'active', payment_status = 'paid',
      subscription_ends_at = v_baseline_expired, period_amount_due_ksh = null, period_amount_paid_ksh = 0,
      period_package_key = null, credit_balance_ksh = 0, pending_downgrade_package_key = null,
      pending_downgrade_requested_at = null, updated_at = now()
    where tenant_id = v_tenant_id;

    insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
    values (v_tenant_id, 'business', v_business_total, 'KES', 'paid', now(), 'TEST-S6-' || gen_random_uuid(), now(), now())
    returning id into v_payment_id;

    perform public.set_ungani_subscription_period_from_payment(v_payment_id);

    select * into v_sub from public.ungani_subscriptions where tenant_id = v_tenant_id;
    v_expected_ends := now() + interval '1 month';

    insert into test_results (scenario, expected, actual, status) values (
      'S6 upgrade Starter->Business, full price',
      'package=business, credit=0, ends~' || v_expected_ends,
      'package=' || v_sub.package_key || ', credit=' || v_sub.credit_balance_ksh || ', ends=' || v_sub.subscription_ends_at,
      case when v_sub.package_key = 'business' and v_sub.credit_balance_ksh = 0
             and abs(extract(epoch from (v_sub.subscription_ends_at - v_expected_ends))) < 60
           then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S6 upgrade full price', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S7: pay 1/3 toward Business while active package is Starter ->
  -- package must stay Starter.
  -------------------------------------------------------------------
  begin
    update public.ungani_subscriptions set
      package_key = 'starter', subscription_status = 'active', payment_status = 'paid',
      subscription_ends_at = v_baseline_expired, period_amount_due_ksh = null, period_amount_paid_ksh = 0,
      period_package_key = null, credit_balance_ksh = 0, pending_downgrade_package_key = null,
      pending_downgrade_requested_at = null, updated_at = now()
    where tenant_id = v_tenant_id;

    v_partial_biz := round(v_business_total / 3.0);

    insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
    values (v_tenant_id, 'business', v_partial_biz, 'KES', 'paid', now(), 'TEST-S7-' || gen_random_uuid(), now(), now())
    returning id into v_payment_id;

    perform public.set_ungani_subscription_period_from_payment(v_payment_id);

    select * into v_sub from public.ungani_subscriptions where tenant_id = v_tenant_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S7 partial upgrade payment',
      'package=starter (unchanged), status=partial, due=' || v_business_total,
      'package=' || v_sub.package_key || ', status=' || v_sub.payment_status || ', due=' || v_sub.period_amount_due_ksh,
      case when v_sub.package_key = 'starter' and v_sub.payment_status = 'partial' and v_sub.period_amount_due_ksh = v_business_total
           then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S7 partial upgrade', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S8: same payment applied twice -> counted once (idempotency).
  -------------------------------------------------------------------
  begin
    update public.ungani_subscriptions set
      package_key = 'starter', subscription_status = 'active', payment_status = 'paid',
      subscription_ends_at = v_baseline_expired, period_amount_due_ksh = null, period_amount_paid_ksh = 0,
      period_package_key = null, credit_balance_ksh = 0, pending_downgrade_package_key = null,
      pending_downgrade_requested_at = null, updated_at = now()
    where tenant_id = v_tenant_id;

    insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
    values (v_tenant_id, 'starter', v_starter_total, 'KES', 'paid', now(), 'TEST-S8-' || gen_random_uuid(), now(), now())
    returning id into v_payment_id;

    perform public.set_ungani_subscription_period_from_payment(v_payment_id);
    select subscription_ends_at, credit_balance_ksh into v_expected_ends, v_commission_amt from public.ungani_subscriptions where tenant_id = v_tenant_id;

    -- Apply the SAME payment id again.
    perform public.set_ungani_subscription_period_from_payment(v_payment_id);

    select * into v_sub from public.ungani_subscriptions where tenant_id = v_tenant_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S8 same payment applied twice',
      'unchanged after 2nd call: ends=' || v_expected_ends || ', credit=' || v_commission_amt,
      'ends=' || v_sub.subscription_ends_at || ', credit=' || v_sub.credit_balance_ksh,
      case when v_sub.subscription_ends_at = v_expected_ends and v_sub.credit_balance_ksh = v_commission_amt
           then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S8 idempotency', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S9a: duplicate reference, resolve as "applied as extra period".
  -------------------------------------------------------------------
  begin
    update public.ungani_subscriptions set
      package_key = 'starter', subscription_status = 'active', payment_status = 'paid',
      subscription_ends_at = v_baseline_expired, period_amount_due_ksh = null, period_amount_paid_ksh = 0,
      period_package_key = null, credit_balance_ksh = 0, pending_downgrade_package_key = null,
      pending_downgrade_requested_at = null, updated_at = now()
    where tenant_id = v_tenant_id;

    v_dup_ref := 'TEST-DUP-' || gen_random_uuid();

    insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
    values (v_tenant_id, 'starter', v_starter_total, 'KES', 'paid', now(), v_dup_ref, now(), now())
    returning id into v_payment_id;
    perform public.set_ungani_subscription_period_from_payment(v_payment_id);

    select subscription_ends_at into v_expected_ends from public.ungani_subscriptions where tenant_id = v_tenant_id;

    insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
    values (v_tenant_id, 'starter', v_starter_total, 'KES', 'paid', now(), v_dup_ref, now(), now())
    returning id into v_payment_id_2;
    perform public.set_ungani_subscription_period_from_payment(v_payment_id_2);

    select * into v_payment from public.ungani_payments where id = v_payment_id_2;
    select id into v_flag_id from public.ungani_payment_duplicate_flags where payment_id = v_payment_id_2 and status = 'pending_review';

    insert into test_results (scenario, expected, actual, status) values (
      'S9a duplicate flagged, not applied',
      'applied_to_subscription_at=null, flag exists',
      'applied_to_subscription_at=' || coalesce(v_payment.applied_to_subscription_at::text, 'null') || ', flag_id=' || coalesce(v_flag_id::text, 'MISSING'),
      case when v_payment.applied_to_subscription_at is null and v_flag_id is not null then 'PASS' else 'FAIL' end
    );

    -- Resolve as admin. aal:'aal2' required since commit 9135ca4
    -- ("Fix admin 2FA lockout") made is_ungani_admin() mandatory-check
    -- the JWT's MFA assurance level - no real TOTP challenge exists in
    -- this synthetic session, so the claim has to be supplied directly.
    perform set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated', 'aal', 'aal2')::text, true);
    v_result := public.admin_resolve_ungani_payment_duplicate(v_flag_id, 'applied_as_extra_period', 'test');
    perform set_config('request.jwt.claims', '', true);

    select * into v_payment from public.ungani_payments where id = v_payment_id_2;
    select * into v_sub from public.ungani_subscriptions where tenant_id = v_tenant_id;
    v_expected_ends := v_expected_ends + interval '1 month';

    insert into test_results (scenario, expected, actual, status) values (
      'S9a resolve as extra period -> applied',
      'ok=true, payment applied, ends~' || v_expected_ends,
      'result=' || v_result::text || ', applied=' || coalesce(v_payment.applied_to_subscription_at::text,'null') || ', ends=' || v_sub.subscription_ends_at,
      case when (v_result->>'ok')::boolean = true and v_payment.applied_to_subscription_at is not null
             and abs(extract(epoch from (v_sub.subscription_ends_at - v_expected_ends))) < 60
           then 'PASS' else 'FAIL' end
    );
  exception when others then
    perform set_config('request.jwt.claims', '', true);
    insert into test_results (scenario, expected, actual, status) values ('S9a duplicate / extra period', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S9b: duplicate reference, resolve as "marked for refund" ->
  -- excluded from revenue (payment_status flips to 'refunded').
  -------------------------------------------------------------------
  begin
    update public.ungani_subscriptions set
      package_key = 'starter', subscription_status = 'active', payment_status = 'paid',
      subscription_ends_at = v_baseline_expired, period_amount_due_ksh = null, period_amount_paid_ksh = 0,
      period_package_key = null, credit_balance_ksh = 0, pending_downgrade_package_key = null,
      pending_downgrade_requested_at = null, updated_at = now()
    where tenant_id = v_tenant_id;

    v_dup_ref := 'TEST-DUP2-' || gen_random_uuid();

    insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
    values (v_tenant_id, 'starter', v_starter_total, 'KES', 'paid', now(), v_dup_ref, now(), now())
    returning id into v_payment_id;
    perform public.set_ungani_subscription_period_from_payment(v_payment_id);

    insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
    values (v_tenant_id, 'starter', v_starter_total, 'KES', 'paid', now(), v_dup_ref, now(), now())
    returning id into v_payment_id_2;
    perform public.set_ungani_subscription_period_from_payment(v_payment_id_2);

    select id into v_flag_id from public.ungani_payment_duplicate_flags where payment_id = v_payment_id_2 and status = 'pending_review';

    perform set_config('request.jwt.claims', json_build_object('sub', v_admin_id::text, 'role', 'authenticated')::text, true);
    v_result := public.admin_resolve_ungani_payment_duplicate(v_flag_id, 'marked_for_refund', 'test refund');
    perform set_config('request.jwt.claims', '', true);

    select * into v_payment from public.ungani_payments where id = v_payment_id_2;

    insert into test_results (scenario, expected, actual, status) values (
      'S9b resolve as refund -> excluded from revenue',
      'ok=true, payment_status=refunded, never applied',
      'result=' || v_result::text || ', payment_status=' || v_payment.payment_status || ', applied=' || coalesce(v_payment.applied_to_subscription_at::text,'null'),
      case when (v_result->>'ok')::boolean = true and v_payment.payment_status = 'refunded' and v_payment.applied_to_subscription_at is null
           then 'PASS' else 'FAIL' end
    );
  exception when others then
    perform set_config('request.jwt.claims', '', true);
    insert into test_results (scenario, expected, actual, status) values ('S9b duplicate / refund', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S10: schedule a downgrade, then the renewal is priced at and
  -- applies the cheaper package.
  -------------------------------------------------------------------
  begin
    update public.ungani_subscriptions set
      package_key = 'business', subscription_status = 'active', payment_status = 'paid',
      subscription_ends_at = v_baseline_expired, period_amount_due_ksh = null, period_amount_paid_ksh = 0,
      period_package_key = null, credit_balance_ksh = 0, pending_downgrade_package_key = null,
      pending_downgrade_requested_at = null, updated_at = now()
    where tenant_id = v_tenant_id;

    perform set_config('request.jwt.claims', json_build_object('sub', v_owner_id::text, 'role', 'authenticated')::text, true);
    v_result := public.client_request_ungani_package_payment('starter');
    perform set_config('request.jwt.claims', '', true);

    select * into v_sub from public.ungani_subscriptions where tenant_id = v_tenant_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S10a schedule downgrade Business->Starter',
      'action=scheduled_downgrade, pending_downgrade=starter, no payment row',
      'action=' || (v_result->>'action') || ', pending_downgrade=' || coalesce(v_sub.pending_downgrade_package_key,'null'),
      case when v_result->>'action' = 'scheduled_downgrade' and v_sub.pending_downgrade_package_key = 'starter'
           then 'PASS' else 'FAIL' end
    );

    -- The "next renewal" (any path) must now price at the downgraded
    -- package automatically - simulate the webhook/automation path by
    -- calling calculate_ungani_subscription_amount with NO override,
    -- under auth.uid() = null (default state).
    v_result := public.calculate_ungani_subscription_amount(v_tenant_id);

    insert into test_results (scenario, expected, actual, status) values (
      'S10b renewal pricing honors pending downgrade',
      'package_key=starter, total=' || v_starter_total,
      'package_key=' || (v_result->>'package_key') || ', total=' || (v_result->>'total_amount'),
      case when v_result->>'package_key' = 'starter' and (v_result->>'total_amount')::numeric = v_starter_total
           then 'PASS' else 'FAIL' end
    );

    insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
    values (v_tenant_id, v_result->>'package_key', (v_result->>'total_amount')::numeric, 'KES', 'paid', now(), 'TEST-S10-' || gen_random_uuid(), now(), now())
    returning id into v_payment_id;
    perform public.set_ungani_subscription_period_from_payment(v_payment_id);

    select * into v_sub from public.ungani_subscriptions where tenant_id = v_tenant_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S10c downgrade applies on paid renewal',
      'package=starter, pending_downgrade cleared',
      'package=' || v_sub.package_key || ', pending_downgrade=' || coalesce(v_sub.pending_downgrade_package_key,'null'),
      case when v_sub.package_key = 'starter' and v_sub.pending_downgrade_package_key is null then 'PASS' else 'FAIL' end
    );
  exception when others then
    perform set_config('request.jwt.claims', '', true);
    insert into test_results (scenario, expected, actual, status) values ('S10 scheduled downgrade', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S11: price unavailable -> not applied, failure logged.
  --
  -- FIXED (round 2): round 1 inserted a payment with a literal invalid
  -- package_key ('zzz_nonexistent_package'), which violates
  -- ungani_payments' own package_key check constraint before the
  -- price-lookup logic this scenario means to test ever runs (confirmed
  -- live: 23514 check-constraint violation). Round 2's fix (delete the
  -- 'growth' row, reinsert it afterwards) hit a SECOND real issue on
  -- the actual live schema: yearly_price_ksh is a GENERATED column
  -- (confirmed live: "cannot insert a non-DEFAULT value into column
  -- yearly_price_ksh"), so `insert ... select <whole row>` can never
  -- restore it. Fixed by never deleting/reinserting at all - instead
  -- temporarily RENAME growth's package_key to a value nothing else
  -- matches, then rename it back. An UPDATE never touches generated
  -- columns, so this sidesteps the issue entirely, while still
  -- reproducing "price unavailable" exactly as the real pricing
  -- function would hit it: a package_key the payments table accepts,
  -- with (temporarily) no matching pricing row.
  -------------------------------------------------------------------
  begin
    update public.ungani_subscriptions set
      package_key = 'starter', subscription_status = 'active', payment_status = 'paid',
      subscription_ends_at = v_baseline_expired, period_amount_due_ksh = null, period_amount_paid_ksh = 0,
      period_package_key = null, credit_balance_ksh = 0, pending_downgrade_package_key = null,
      pending_downgrade_requested_at = null, updated_at = now()
    where tenant_id = v_tenant_id;

    update public.ungani_packages set package_key = '__test_disabled_growth__' where package_key = 'growth';

    insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
    values (v_tenant_id, 'growth', 1, 'KES', 'paid', now(), 'TEST-S11-' || gen_random_uuid(), now(), now())
    returning id into v_payment_id;

    perform public.set_ungani_subscription_period_from_payment(v_payment_id);

    select * into v_payment from public.ungani_payments where id = v_payment_id;
    select * into v_sub from public.ungani_subscriptions where tenant_id = v_tenant_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S11 price unavailable',
      'applied=null, subscription unchanged (still starter, ends=' || v_baseline_expired || '), failure logged',
      'applied=' || coalesce(v_payment.applied_to_subscription_at::text,'null') || ', package=' || v_sub.package_key || ', ends=' || v_sub.subscription_ends_at
        || ', failure_exists=' || exists(select 1 from public.ungani_payment_processing_failures where payment_id = v_payment_id),
      case when v_payment.applied_to_subscription_at is null and v_sub.package_key = 'starter'
             and v_sub.subscription_ends_at = v_baseline_expired
             and exists(select 1 from public.ungani_payment_processing_failures where payment_id = v_payment_id)
           then 'PASS' else 'FAIL' end
    );

    -- Restore growth immediately - belt-and-suspenders on top of the
    -- final ROLLBACK, since no later scenario in this script uses it.
    update public.ungani_packages set package_key = 'growth' where package_key = '__test_disabled_growth__';
  exception when others then
    update public.ungani_packages set package_key = 'growth' where package_key = '__test_disabled_growth__';
    insert into test_results (scenario, expected, actual, status) values ('S11 price unavailable', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S12: referred-tenant commissions - onboarding once, then monthly,
  -- then monthly x3 on a prepay.
  --
  -- FIXED: the previous version's partner insert only set (status,
  -- onboarding_rate, ongoing_rate) - the real partners table
  -- (sql/partner-referral-system.sql) also requires partner_code,
  -- full_name, and email as not null. Fixed by supplying all three with
  -- obvious disposable test values.
  -------------------------------------------------------------------
  begin
    begin
      insert into public.partners (partner_code, full_name, email, status, onboarding_rate, ongoing_rate)
      values ('TEST-S12-' || substr(gen_random_uuid()::text, 1, 8), 'TEST PARTNER - DELETE ME', 'test-partner-delete-me+' || gen_random_uuid() || '@example.invalid', 'active', 30, 2)
      returning id into v_partner_id;
    exception when others then
      insert into test_results (scenario, expected, actual, status) values ('S12 setup (insert partner)', 'insert succeeds', 'ERROR: ' || sqlerrm, 'FAIL');
      v_partner_id := null;
    end;

    if v_partner_id is not null then
      update public.tenants set referred_by_partner_id = v_partner_id where id = v_tenant_id;

      update public.ungani_subscriptions set
        package_key = 'starter', subscription_status = 'active', payment_status = 'paid',
        subscription_ends_at = v_baseline_expired, period_amount_due_ksh = null, period_amount_paid_ksh = 0,
        period_package_key = null, credit_balance_ksh = 0, pending_downgrade_package_key = null,
        pending_downgrade_requested_at = null, updated_at = now()
      where tenant_id = v_tenant_id;

      -- First fully paid period -> onboarding commission.
      insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
      values (v_tenant_id, 'starter', v_starter_total, 'KES', 'paid', now(), 'TEST-S12A-' || gen_random_uuid(), now(), now())
      returning id into v_payment_id;
      perform public.set_ungani_subscription_period_from_payment(v_payment_id);

      select amount into v_commission_amt from public.partner_commissions
      where partner_id = v_partner_id and tenant_id = v_tenant_id and commission_type = 'onboarding';

      insert into test_results (scenario, expected, actual, status) values (
        'S12a onboarding commission (first period)',
        round(v_starter_total * 30 / 100, 2)::text,
        coalesce(v_commission_amt::text, 'MISSING ROW'),
        case when v_commission_amt = round(v_starter_total * 30 / 100, 2) then 'PASS' else 'FAIL' end
      );

      -- Second payment (next period) -> monthly commission x1.
      insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
      values (v_tenant_id, 'starter', v_starter_total, 'KES', 'paid', now(), 'TEST-S12B-' || gen_random_uuid(), now(), now())
      returning id into v_payment_id_2;
      perform public.set_ungani_subscription_period_from_payment(v_payment_id_2);

      select amount into v_commission_amt from public.partner_commissions
      where partner_id = v_partner_id and source_payment_id = v_payment_id_2 and commission_type = 'monthly';

      insert into test_results (scenario, expected, actual, status) values (
        'S12b monthly commission x1',
        round(v_starter_total * 1 * 2 / 100, 2)::text,
        coalesce(v_commission_amt::text, 'MISSING ROW'),
        case when v_commission_amt = round(v_starter_total * 1 * 2 / 100, 2) then 'PASS' else 'FAIL' end
      );

      -- Third payment, prepaying 3 periods -> monthly commission x3 on
      -- this one payment.
      insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
      values (v_tenant_id, 'starter', v_starter_total * 3, 'KES', 'paid', now(), 'TEST-S12C-' || gen_random_uuid(), now(), now())
      returning id into v_payment_id_3;
      perform public.set_ungani_subscription_period_from_payment(v_payment_id_3);

      select amount into v_commission_amt from public.partner_commissions
      where partner_id = v_partner_id and source_payment_id = v_payment_id_3 and commission_type = 'monthly';

      insert into test_results (scenario, expected, actual, status) values (
        'S12c monthly commission x3 (prepay)',
        round(v_starter_total * 3 * 2 / 100, 2)::text,
        coalesce(v_commission_amt::text, 'MISSING ROW'),
        case when v_commission_amt = round(v_starter_total * 3 * 2 / 100, 2) then 'PASS' else 'FAIL' end
      );
    end if;
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S12 commissions', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S13: webhook path - auth.uid() is null (the default state in this
  -- script unless explicitly set, exactly matching the real service_role
  -- webhook context). Re-run a plain full payment under that condition
  -- and confirm it still applies correctly.
  -------------------------------------------------------------------
  begin
    update public.ungani_subscriptions set
      package_key = 'starter', subscription_status = 'active', payment_status = 'paid',
      subscription_ends_at = v_baseline_expired, period_amount_due_ksh = null, period_amount_paid_ksh = 0,
      period_package_key = null, credit_balance_ksh = 0, pending_downgrade_package_key = null,
      pending_downgrade_requested_at = null, updated_at = now()
    where tenant_id = v_tenant_id;

    perform set_config('request.jwt.claims', '', true);

    insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, paid_at, payment_reference, created_at, updated_at)
    values (v_tenant_id, 'starter', v_starter_total, 'KES', 'paid', now(), 'TEST-S13-' || gen_random_uuid(), now(), now())
    returning id into v_payment_id;

    perform public.set_ungani_subscription_period_from_payment(v_payment_id);

    select * into v_sub from public.ungani_subscriptions where tenant_id = v_tenant_id;
    v_expected_ends := now() + interval '1 month';

    insert into test_results (scenario, expected, actual, status) values (
      'S13 webhook path (auth.uid() is null)',
      'auth.uid() was null, payment applied, ends~' || v_expected_ends,
      'auth.uid()=' || coalesce(auth.uid()::text,'null') || ', ends=' || v_sub.subscription_ends_at,
      case when auth.uid() is null and abs(extract(epoch from (v_sub.subscription_ends_at - v_expected_ends))) < 60
           then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S13 webhook path', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S14: choosing a plan twice -> one pending payment; an automation
  -- renewal invoice (no source) is never touched.
  -------------------------------------------------------------------
  begin
    update public.ungani_subscriptions set
      package_key = 'starter', subscription_status = 'active', payment_status = 'paid',
      subscription_ends_at = v_baseline_expired, period_amount_due_ksh = null, period_amount_paid_ksh = 0,
      period_package_key = null, credit_balance_ksh = 0, pending_downgrade_package_key = null,
      pending_downgrade_requested_at = null, updated_at = now()
    where tenant_id = v_tenant_id;

    -- A pre-existing automation-created renewal invoice (no `source`).
    insert into public.ungani_payments (tenant_id, package_key, amount, currency, payment_status, billing_period_start, billing_period_end, due_date, created_at, updated_at)
    values (v_tenant_id, 'starter', v_starter_total, 'KES', 'pending', current_date, current_date + 30, current_date + 7, now(), now())
    returning id into v_automation_payment_id;

    perform set_config('request.jwt.claims', json_build_object('sub', v_owner_id::text, 'role', 'authenticated')::text, true);
    v_result := public.client_request_ungani_package_payment('business');
    v_result := public.client_request_ungani_package_payment('business');
    perform set_config('request.jwt.claims', '', true);

    select count(*) into v_pending_count
    from public.ungani_payments
    where tenant_id = v_tenant_id and payment_status = 'pending' and source = 'package_selection';

    select payment_status into v_dup_ref from public.ungani_payments where id = v_automation_payment_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S14 choose a plan twice -> one pending payment, automation row untouched',
      'package_selection_pending_count=1, automation_row_status=pending',
      'package_selection_pending_count=' || v_pending_count || ', automation_row_status=' || v_dup_ref,
      case when v_pending_count = 1 and v_dup_ref = 'pending' then 'PASS' else 'FAIL' end
    );
  exception when others then
    perform set_config('request.jwt.claims', '', true);
    insert into test_results (scenario, expected, actual, status) values ('S14 choose plan twice', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

end;
$test$;

select scenario, expected, actual, status from test_results order by seq;

rollback;
