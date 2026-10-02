-- =====================================================================
-- Item 1: Subscription billing fixes + Payment Instructions panel.
--
-- Rewritten from the LIVE definitions pulled via the two discovery
-- queries in this conversation - not from any repo sql/*.sql file.
--
-- Covers, in one coherent design:
--   1. Early renewal extends from the tenant's existing
--      subscription_ends_at when it's still in the future, never from
--      "now" - a renewal before expiry never loses remaining days.
--   2. Underpayment: payments accumulate in
--      ungani_subscriptions.period_amount_paid_ksh against
--      period_amount_due_ksh; the period is extended, the receipt email
--      fires, and commission is calculated ONLY once fully paid. A
--      partial payment instead queues a "balance due" email and leaves
--      subscription_ends_at untouched.
--   3. Overpayment (Chris's decision: carry forward): any amount above
--      what a period needed becomes credit_balance_ksh, automatically
--      applied toward the next period's total before more cash is
--      required.
--   4. Duplicate payment_reference detection: if a payment shares its
--      reference with an already-paid payment, it's held (never
--      auto-applied to the subscription) and flagged into
--      ungani_payment_duplicate_flags for admin choice - apply as an
--      extra period, or mark for refund.
--   5. Silent failures: every exception previously swallowed by
--      `raise warning` (invisible to anyone) now also writes a row to
--      ungani_payment_processing_failures, with admin RPCs to list and
--      resolve them.
--   6. Package downgrade bug: a payment with no package_key no longer
--      defaults straight to 'starter' - it falls back to the tenant's
--      current subscription package_key, then the tenant's own
--      package_key, and only 'starter' as a last resort with nothing
--      else to go on.
--   7. Commission: rewritten to use the REAL partner_commissions columns
--      (source_payment_id, amount - not payment_id/rate/base_amount/
--      commission_amount, which don't exist and made every commission
--      insert silently fail since the feature was added). commission_type
--      values corrected to 'onboarding'/'monthly' to match the two real
--      partial unique indexes. "Onboarding once" is now driven by
--      whether an onboarding commission already exists for this
--      (partner, tenant) pair, not a payment-count guess - and it only
--      fires once a period is genuinely fully paid, not on every partial
--      payment.
--   8. Idempotency: ungani_payments.applied_to_subscription_at guards
--      the whole function - once a payment's amount has been counted
--      toward a period, calling this function again for the same
--      payment id is a safe no-op.
--   9. Security: calculate_ungani_subscription_amount now requires the
--      caller to be admin or querying their own tenant (previously
--      wide open to anon/public and any authenticated caller for any
--      tenant - Chris already revoked anon/public on the 5 billing
--      functions separately; this adds the missing internal check).
--  10. Package change via payment (replaces the upgrade-request/admin-
--      approval flow entirely): client_request_ungani_package_payment
--      decides upgrade vs downgrade by comparing live package prices.
--      Upgrade/same package -> creates or reuses a pending ungani_payments
--      row carrying the chosen package_key; paying it (any method) is
--      what applies the new package, via the package_key-first resolution
--      set_ungani_subscription_period_from_payment already had. Downgrade
--      -> no payment, stored as pending_downgrade_package_key, applied
--      automatically the next time a period completes (no refund for
--      time already paid on the better package).
--  11. User limit follows the package automatically: confirmed
--      owner_upsert_ungani_team_member already enforces the staff limit
--      by joining ungani_packages live via package_key - zero change
--      needed there. ungani_subscriptions.user_limit (a separate,
--      denormalized column some screens may read for display) is synced
--      on every completed period so it's never stale.
--
-- Deploy-order note: the two admin_get_/resolve_ ...duplicate/failure
-- RPCs and the new columns must exist before the rewritten
-- set_ungani_subscription_period_from_payment is called with real
-- traffic - since this is a single paste run as one transaction-per-
-- statement block in order (tables/columns first, functions after),
-- that's already the order below. Nothing in the currently-live app
-- calls the new columns/tables directly, so there is no window where
-- the live app breaks mid-deploy.
-- =====================================================================


-- ---------------------------------------------------------------------
-- SECTION 1: New columns.
-- ---------------------------------------------------------------------

alter table public.ungani_subscriptions
  add column if not exists period_amount_due_ksh numeric,
  add column if not exists period_amount_paid_ksh numeric not null default 0,
  add column if not exists credit_balance_ksh numeric not null default 0,
  add column if not exists pending_downgrade_package_key text,
  add column if not exists pending_downgrade_requested_at timestamptz;

alter table public.ungani_payments
  add column if not exists applied_to_subscription_at timestamptz;


-- ---------------------------------------------------------------------
-- SECTION 2: New tables.
-- ---------------------------------------------------------------------

create table if not exists public.ungani_payment_processing_failures (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid references public.ungani_payments(id),
  tenant_id uuid references public.tenants(id),
  failure_stage text not null,
  error_message text not null,
  occurred_at timestamptz not null default now(),
  resolved boolean not null default false,
  resolved_at timestamptz,
  resolved_by uuid,
  resolution_note text
);

create index if not exists idx_ungani_payment_processing_failures_unresolved
  on public.ungani_payment_processing_failures (occurred_at desc)
  where resolved = false;

alter table public.ungani_payment_processing_failures enable row level security;

drop policy if exists ungani_payment_processing_failures_admin_all on public.ungani_payment_processing_failures;
create policy ungani_payment_processing_failures_admin_all
  on public.ungani_payment_processing_failures
  for all
  using ((select public.is_ungani_admin()))
  with check ((select public.is_ungani_admin()));

create table if not exists public.ungani_payment_duplicate_flags (
  id uuid primary key default gen_random_uuid(),
  payment_id uuid not null references public.ungani_payments(id),
  tenant_id uuid references public.tenants(id),
  payment_reference text not null,
  duplicate_of_payment_id uuid references public.ungani_payments(id),
  amount numeric not null,
  status text not null default 'pending_review'
    check (status in ('pending_review', 'applied_as_extra_period', 'marked_for_refund')),
  flagged_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid,
  resolution_note text
);

create unique index if not exists uq_ungani_payment_duplicate_flags_payment_pending
  on public.ungani_payment_duplicate_flags (payment_id)
  where status = 'pending_review';

alter table public.ungani_payment_duplicate_flags enable row level security;

drop policy if exists ungani_payment_duplicate_flags_admin_all on public.ungani_payment_duplicate_flags;
create policy ungani_payment_duplicate_flags_admin_all
  on public.ungani_payment_duplicate_flags
  for all
  using ((select public.is_ungani_admin()))
  with check ((select public.is_ungani_admin()));


-- ---------------------------------------------------------------------
-- SECTION 3: calculate_ungani_subscription_amount - add the missing
-- internal access check. Body otherwise unchanged from the live version.
-- ---------------------------------------------------------------------

create or replace function public.calculate_ungani_subscription_amount(p_tenant_id uuid)
returns jsonb
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_package_key text;
  v_is_custom boolean;
  v_billing_cycle text;
  v_base_amount numeric;
  v_branch_addon numeric;
  v_billable_branches int;
  v_total numeric;
begin
  if not (
    (select public.is_ungani_admin())
    or p_tenant_id = (select public.get_my_ungani_tenant_id())
  ) then
    raise exception 'Access denied';
  end if;

  select coalesce(s.package_key, 'starter') into v_package_key
  from public.ungani_subscriptions s
  where s.tenant_id = p_tenant_id;

  if v_package_key is null then
    v_package_key := 'starter';
  end if;

  select coalesce(t.billing_cycle, 'monthly') into v_billing_cycle
  from public.tenants t
  where t.id = p_tenant_id;

  select
    coalesce(p.is_custom, false),
    case when v_billing_cycle = 'yearly' then p.yearly_price_ksh else p.monthly_price_ksh end
  into v_is_custom, v_base_amount
  from public.ungani_packages p
  where p.package_key = v_package_key;

  v_branch_addon := public.ungani_get_branch_addon_amount(p_tenant_id);
  v_billable_branches := public.ungani_get_billable_branch_count(p_tenant_id);

  v_total := case when v_base_amount is null then null else v_base_amount + coalesce(v_branch_addon, 0) end;

  return jsonb_build_object(
    'tenant_id', p_tenant_id,
    'package_key', v_package_key,
    'is_custom', coalesce(v_is_custom, false),
    'billing_cycle', v_billing_cycle,
    'base_amount', v_base_amount,
    'branch_addon_amount', coalesce(v_branch_addon, 0),
    'billable_branch_count', coalesce(v_billable_branches, 0),
    'total_amount', v_total
  );
end;
$function$;


-- ---------------------------------------------------------------------
-- SECTION 4: set_ungani_subscription_period_from_payment - the core
-- rewrite. Every numbered comment below maps to one of Chris's review
-- items from the second round (concurrency, duplicate deadlock,
-- multi-period prepayment, etc.) layered on the first round's 8.
--
-- Explicit DROP first: adding p_skip_duplicate_check changes the
-- parameter list, which CREATE OR REPLACE treats as a different
-- function (same overload-drift risk as queue_ungani_payment_
-- confirmation_email above). All 4 existing call sites (webhook + 3
-- admin wrappers) call with just the payment id, which still resolves
-- correctly against the new 2-arg signature via the added default.
-- ---------------------------------------------------------------------

drop function if exists public.set_ungani_subscription_period_from_payment(uuid);

create or replace function public.set_ungani_subscription_period_from_payment(
  p_payment_id uuid,
  p_skip_duplicate_check boolean default false
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_payment public.ungani_payments;
  v_sub public.ungani_subscriptions;
  v_billing_cycle text;
  v_tenant_package_key text;
  v_effective_package_key text;
  v_final_package_key text;
  v_new_user_limit int;
  v_period_interval interval;

  v_expected jsonb;
  v_expected_total numeric;
  v_billable_branches int;

  v_period_due numeric;
  v_period_paid_so_far numeric;
  v_credit numeric;
  v_available numeric;
  v_periods_covered int;
  v_leftover numeric;
  v_new_ends_at timestamptz;

  v_dup_payment_id uuid;

  v_partner_id uuid;
  v_partner_status text;
  v_is_first_period boolean;
  v_additional_periods int;
  v_onboarding_rate numeric;
  v_ongoing_rate numeric;
begin
  -- (concurrency) Lock this payment row first - a repeat/concurrent call
  -- for the SAME payment id now blocks here until the first call
  -- commits, instead of racing.
  select * into v_payment from public.ungani_payments where id = p_payment_id for update;

  if v_payment.id is null or v_payment.payment_status <> 'paid' then
    return;
  end if;

  -- (8) Idempotency: this payment's amount has already been counted
  -- toward a period. Safe no-op on any repeat call.
  if v_payment.applied_to_subscription_at is not null then
    return;
  end if;

  -- (concurrency) Ensure the tenant's subscription row exists, then lock
  -- it. Two payments for the SAME tenant arriving at the same moment
  -- (two STK pushes, or the genuine-duplicate scenario below) now
  -- serialize on this lock - whichever call gets here first commits its
  -- full decision before the second call reads anything.
  insert into public.ungani_subscriptions (tenant_id) values (v_payment.tenant_id)
  on conflict (tenant_id) do nothing;

  select * into v_sub from public.ungani_subscriptions where tenant_id = v_payment.tenant_id for update;

  -- (duplicate deadlock fix) Only flag against another payment that has
  -- ALREADY been applied. Two genuinely-simultaneous payments sharing a
  -- reference no longer both see "the other one" as already-applied and
  -- both bail - the subscription-row lock above means whichever call
  -- wins processes and applies first; the second call (now running
  -- after the first committed, same tenant) correctly sees the first as
  -- applied and flags itself. p_skip_duplicate_check lets
  -- admin_resolve_ungani_payment_duplicate re-run this function for a
  -- payment an admin has deliberately cleared - without it, this exact
  -- check would immediately re-flag it, since the original payment it
  -- was flagged against is (correctly) still applied.
  if not p_skip_duplicate_check and v_payment.payment_reference is not null then
    select id into v_dup_payment_id
    from public.ungani_payments
    where payment_reference = v_payment.payment_reference
      and id <> p_payment_id
      and payment_status = 'paid'
      and applied_to_subscription_at is not null
    order by paid_at asc nulls last
    limit 1;

    if v_dup_payment_id is not null then
      insert into public.ungani_payment_duplicate_flags
        (payment_id, tenant_id, payment_reference, duplicate_of_payment_id, amount)
      values
        (p_payment_id, v_payment.tenant_id, v_payment.payment_reference, v_dup_payment_id, v_payment.amount)
      on conflict (payment_id) where status = 'pending_review' do nothing;

      return;
    end if;
  end if;

  select coalesce(billing_cycle, 'monthly'), package_key
  into v_billing_cycle, v_tenant_package_key
  from public.tenants
  where id = v_payment.tenant_id;

  v_period_interval := case when v_billing_cycle = 'yearly' then interval '1 year' else interval '1 month' end;

  -- (6) Package downgrade fix: a payment with no package_key falls back
  -- to the tenant's CURRENT subscription package, then the tenant row's
  -- own package_key, and only 'starter' if genuinely nothing else is
  -- known - never blindly overwrites an existing higher package.
  v_effective_package_key := coalesce(v_payment.package_key, v_sub.package_key, v_tenant_package_key, 'starter');

  begin
    v_expected := public.calculate_ungani_subscription_amount(v_payment.tenant_id);
    v_expected_total := (v_expected->>'total_amount')::numeric;
    v_billable_branches := coalesce((v_expected->>'billable_branch_count')::int, 0);
  exception
    when others then
      insert into public.ungani_payment_processing_failures (payment_id, tenant_id, failure_stage, error_message)
      values (p_payment_id, v_payment.tenant_id, 'amount_calculation', sqlerrm);
      v_expected_total := null;
      v_billable_branches := 0;
  end;

  -- (2) Underpayment tracking: lock in the due amount for an
  -- already-in-progress period so a mid-period price change doesn't
  -- move the goalposts; only pull a fresh price when starting a new
  -- period (period_amount_due_ksh is null right after a period
  -- completes and resets). Rounded to whole shillings the moment it's
  -- locked in - M-Pesa amounts are always whole shillings, so every
  -- payment added afterward is exact integer arithmetic with zero
  -- floating-point comparison risk.
  v_period_due := coalesce(v_sub.period_amount_due_ksh, round(v_expected_total));
  v_period_paid_so_far := coalesce(v_sub.period_amount_paid_ksh, 0) + v_payment.amount;
  v_credit := coalesce(v_sub.credit_balance_ksh, 0);
  v_available := v_period_paid_so_far + v_credit;

  if v_period_due is null or v_available >= v_period_due then
    -- Fully paid (or pricing isn't configured for this package yet -
    -- treated as immediately payable rather than permanently blocking
    -- the tenant, matching the forgiving intent of the original code).

    -- (multi-period prepayment) Extend by every FULL period the
    -- available amount covers, capped at 24 in one call - a prepaid
    -- client is no longer suspended after month one just because this
    -- function used to advance the date by exactly one period
    -- regardless of how much was paid. Anything beyond 24 periods still
    -- survives as credit, it's just not applied to subscription_ends_at
    -- until a later call - an edge case well beyond any real pricing
    -- scenario today.
    if v_period_due is null then
      v_periods_covered := 1;
      v_leftover := 0;
    else
      v_periods_covered := least(floor(v_available / v_period_due)::int, 24);
      v_leftover := v_available - (v_periods_covered * v_period_due);
    end if;

    -- (1) Early renewal: extend from the LATER of "now/paid_at" and the
    -- tenant's existing subscription_ends_at, multiplied by however many
    -- full periods this payment covers - a renewal made while time
    -- remains adds on top of what's left, instead of overwriting it.
    v_new_ends_at := greatest(coalesce(v_sub.subscription_ends_at, v_payment.paid_at), coalesce(v_payment.paid_at, now()))
      + (v_period_interval * v_periods_covered);

    -- (item-1 addendum: package-change-via-payment) A period completing is
    -- the one moment "the next renewal" actually happens. An EXPLICIT
    -- package on the payment itself (the client paid full price for a
    -- different package - an upgrade) always wins. Otherwise, if the
    -- tenant has a scheduled downgrade waiting (chosen earlier at zero
    -- cost, takes effect at next renewal, no refund - see
    -- client_request_ungani_package_payment), THIS is that renewal, so it
    -- applies now. Either way the pending downgrade is cleared below -
    -- it's either just been applied, or superseded by an explicit upgrade.
    v_final_package_key := case
      when v_payment.package_key is not null then v_effective_package_key
      when v_sub.pending_downgrade_package_key is not null then v_sub.pending_downgrade_package_key
      else v_effective_package_key
    end;

    -- (user limit follows the package) owner_upsert_ungani_team_member
    -- already enforces the staff limit by joining ungani_packages live via
    -- package_key, so enforcement already follows the package automatically
    -- with zero changes needed there. This sync is purely so
    -- ungani_subscriptions.user_limit - a separate, denormalized column
    -- some screens may read directly for display - never shows a stale
    -- number after a package change.
    select p.user_limit into v_new_user_limit
    from public.ungani_packages p
    where p.package_key = v_final_package_key;

    insert into public.ungani_subscriptions (
      tenant_id, package_key, subscription_status, payment_status,
      subscription_ends_at, period_amount_due_ksh, period_amount_paid_ksh, credit_balance_ksh,
      user_limit, pending_downgrade_package_key, pending_downgrade_requested_at, updated_at
    ) values (
      v_payment.tenant_id, v_final_package_key, 'active', 'paid',
      v_new_ends_at, null, 0, v_leftover,
      coalesce(v_new_user_limit, 2), null, null, now()
    )
    on conflict (tenant_id) do update set
      package_key = excluded.package_key,
      subscription_status = 'active',
      payment_status = 'paid',
      subscription_ends_at = excluded.subscription_ends_at,
      period_amount_due_ksh = null,
      period_amount_paid_ksh = 0,
      credit_balance_ksh = excluded.credit_balance_ksh,
      user_limit = coalesce(v_new_user_limit, public.ungani_subscriptions.user_limit),
      pending_downgrade_package_key = null,
      pending_downgrade_requested_at = null,
      updated_at = now();

    begin
      perform public.queue_ungani_payment_confirmation_email(p_payment_id, v_new_ends_at, v_leftover);
    exception
      when others then
        insert into public.ungani_payment_processing_failures (payment_id, tenant_id, failure_stage, error_message)
        values (p_payment_id, v_payment.tenant_id, 'confirmation_email', sqlerrm);
    end;

    -- (6, redefined) Mismatch log moved here (period-completion only,
    -- never for a partial payment) and re-targeted: compares the FRESH
    -- live price calculation against what was actually locked in for
    -- this period. Comparing payment.amount to the due amount directly
    -- (the original signal) would now false-fire constantly on
    -- perfectly legitimate partial payments and multi-period
    -- prepayments, neither of which is a pricing problem - this instead
    -- catches real drift, e.g. the tenant's branch count or package
    -- price changed mid-period relative to what was locked in.
    begin
      if v_expected_total is not null and round(v_expected_total) <> v_period_due then
        insert into public.ungani_billing_amount_mismatches (
          tenant_id, payment_id, package_key, billing_cycle,
          expected_amount, actual_amount, difference, billable_branch_count
        ) values (
          v_payment.tenant_id, p_payment_id, v_final_package_key, v_billing_cycle,
          round(v_expected_total), v_period_due, round(v_expected_total) - v_period_due, v_billable_branches
        );
      end if;
    exception
      when others then
        insert into public.ungani_payment_processing_failures (payment_id, tenant_id, failure_stage, error_message)
        values (p_payment_id, v_payment.tenant_id, 'billing_mismatch_check', sqlerrm);
    end;

    -- (7, redefined for multi-period) Onboarding = rate x ONE period's
    -- due, only on the tenant's first-ever completed period - driven by
    -- whether an onboarding commission already exists for this
    -- (partner, tenant) pair, not a payment-count guess. Any ADDITIONAL
    -- periods covered by THIS SAME payment (a multi-period prepayment,
    -- or any call that isn't the first) earn the monthly/ongoing rate
    -- instead, as one combined row for however many additional periods
    -- this payment covered. Real columns (source_payment_id, amount)
    -- and real commission_type values ('onboarding' / 'monthly')
    -- matching the two live partial unique indexes - the original
    -- insert used columns and a value that don't exist and had silently
    -- failed on every attempt.
    begin
      select referred_by_partner_id into v_partner_id
      from public.tenants where id = v_payment.tenant_id;

      if v_partner_id is not null then
        select status into v_partner_status from public.partners where id = v_partner_id;

        if v_partner_status = 'active' then
          select not exists (
            select 1 from public.partner_commissions
            where partner_id = v_partner_id and tenant_id = v_payment.tenant_id and commission_type = 'onboarding'
          ) into v_is_first_period;

          if v_is_first_period then
            select onboarding_rate into v_onboarding_rate from public.partners where id = v_partner_id;

            if v_onboarding_rate is not null then
              insert into public.partner_commissions
                (partner_id, tenant_id, source_payment_id, commission_type, amount, status)
              values
                (v_partner_id, v_payment.tenant_id, p_payment_id, 'onboarding',
                 round(coalesce(v_period_due, v_payment.amount) * v_onboarding_rate / 100, 2), 'owed')
              on conflict (partner_id, tenant_id) where commission_type = 'onboarding' do nothing;
            end if;

            v_additional_periods := v_periods_covered - 1;
          else
            v_additional_periods := v_periods_covered;
          end if;

          if v_additional_periods > 0 then
            select ongoing_rate into v_ongoing_rate from public.partners where id = v_partner_id;

            if v_ongoing_rate is not null then
              insert into public.partner_commissions
                (partner_id, tenant_id, source_payment_id, commission_type, amount, status)
              values
                (v_partner_id, v_payment.tenant_id, p_payment_id, 'monthly',
                 round(coalesce(v_period_due, v_payment.amount) * v_additional_periods * v_ongoing_rate / 100, 2), 'owed')
              on conflict (partner_id, source_payment_id) where commission_type = 'monthly' do nothing;
            end if;
          end if;
        end if;
      end if;
    exception
      when others then
        insert into public.ungani_payment_processing_failures (payment_id, tenant_id, failure_stage, error_message)
        values (p_payment_id, v_payment.tenant_id, 'commission_calculation', sqlerrm);
    end;

  else
    -- Not yet fully paid - accumulate, notify, do NOT extend the period,
    -- do NOT fire commission, and (6) do NOT log a mismatch - a partial
    -- payment not matching the full due amount is expected, not an
    -- anomaly. subscription_status/subscription_ends_at deliberately
    -- untouched - a client with time remaining who pays partially early
    -- keeps full access and isn't marked overdue (payment_status moves
    -- to 'partial', never 'overdue'/'unpaid'/'failed' - the specific
    -- values every access-gate/reminder reader actually checks for).
    insert into public.ungani_subscriptions (
      tenant_id, package_key, subscription_status, payment_status,
      period_amount_due_ksh, period_amount_paid_ksh, credit_balance_ksh, updated_at
    ) values (
      v_payment.tenant_id, v_effective_package_key, coalesce(v_sub.subscription_status, 'trial'), 'partial',
      v_period_due, v_period_paid_so_far, v_credit, now()
    )
    on conflict (tenant_id) do update set
      package_key = excluded.package_key,
      payment_status = 'partial',
      period_amount_due_ksh = excluded.period_amount_due_ksh,
      period_amount_paid_ksh = excluded.period_amount_paid_ksh,
      updated_at = now();

    begin
      perform public.queue_ungani_partial_payment_email(p_payment_id, v_period_paid_so_far, v_period_due);
    exception
      when others then
        insert into public.ungani_payment_processing_failures (payment_id, tenant_id, failure_stage, error_message)
        values (p_payment_id, v_payment.tenant_id, 'partial_payment_email', sqlerrm);
    end;
  end if;

  update public.ungani_payments set applied_to_subscription_at = now() where id = p_payment_id;

exception
  when others then
    insert into public.ungani_payment_processing_failures (payment_id, tenant_id, failure_stage, error_message)
    values (p_payment_id, v_payment.tenant_id, 'subscription_period_update', sqlerrm);
end;
$function$;

revoke all on function public.set_ungani_subscription_period_from_payment(uuid, boolean) from public, anon, authenticated;
grant execute on function public.set_ungani_subscription_period_from_payment(uuid, boolean) to service_role;


-- ---------------------------------------------------------------------
-- SECTION 5: The 3 admin "mark paid" wrappers - remove the direct,
-- unconditional queue_ungani_payment_confirmation_email call. That
-- decision now belongs solely to set_ungani_subscription_period_from_payment,
-- which knows whether the period actually completed (full receipt) or
-- not (balance-due notice) - otherwise every partial payment would
-- ALSO get a misleading "payment confirmed" receipt email fired here,
-- before the period-completion check even runs. Everything else is
-- byte-identical to the live version.
-- ---------------------------------------------------------------------

create or replace function public.admin_accept_ungani_payment_proof_and_mark_paid(p_proof_id uuid, p_admin_note text DEFAULT NULL::text, p_payment_method text DEFAULT NULL::text, p_payment_reference text DEFAULT NULL::text)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_payment_id uuid;
  v_tenant_id uuid;
  v_invoice_number text;
  v_existing_method text;
  v_existing_reference text;
  v_clean_note text;
  v_clean_method text;
  v_clean_reference text;
begin
  if public.is_ungani_admin() is not true then
    raise exception 'Access denied';
  end if;
  select
    pp.payment_id,
    pp.tenant_id,
    pp.invoice_number
  into
    v_payment_id,
    v_tenant_id,
    v_invoice_number
  from public.ungani_payment_proofs pp
  where pp.id = p_proof_id
  limit 1;
  if v_payment_id is null then
    raise exception 'Payment proof not found';
  end if;
  select
    p.payment_method,
    p.payment_reference
  into
    v_existing_method,
    v_existing_reference
  from public.ungani_payments p
  where p.id = v_payment_id
  limit 1;
  if not found then
    raise exception 'Related payment record not found';
  end if;
  v_clean_note := nullif(trim(coalesce(p_admin_note, '')), '');
  v_clean_method := nullif(trim(coalesce(p_payment_method, '')), '');
  v_clean_reference := nullif(trim(coalesce(p_payment_reference, '')), '');
  update public.ungani_payment_proofs
  set
    proof_status = 'accepted',
    admin_note = coalesce(
      v_clean_note,
      admin_note,
      'Payment proof accepted and payment marked as paid by UNGANI admin.'
    ),
    reviewed_by = auth.uid(),
    reviewed_at = now()
  where id = p_proof_id;
  update public.ungani_payments
  set
    payment_status = 'paid',
    paid_at = coalesce(paid_at, now()),
    payment_method = coalesce(
      v_clean_method,
      nullif(trim(coalesce(v_existing_method, '')), ''),
      'Payment proof'
    ),
    payment_reference = coalesce(
      v_clean_reference,
      nullif(trim(coalesce(v_existing_reference, '')), ''),
      v_invoice_number,
      'Proof accepted'
    ),
    notes = case
      when v_clean_note is not null and length(v_clean_note) > 0 then
        case
          when notes is null or length(trim(notes)) = 0 then
            'Admin accepted payment proof: ' || v_clean_note
          else
            notes || E'\nAdmin accepted payment proof: ' || v_clean_note
        end
      else
        case
          when notes is null or length(trim(notes)) = 0 then
            'Payment proof accepted and payment marked as paid by UNGANI admin.'
          else
            notes || E'\nPayment proof accepted and payment marked as paid by UNGANI admin.'
        end
    end,
    updated_at = now()
  where id = v_payment_id;
  if not found then
    raise exception 'Unable to update payment record';
  end if;

  begin
    perform public.set_ungani_subscription_period_from_payment(v_payment_id);
  exception
    when others then
      raise warning 'Could not update subscription period for payment %: %', v_payment_id, sqlerrm;
  end;

  return true;
end;
$function$;

create or replace function public.admin_update_ungani_payment_status(p_payment_id uuid, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_record public.ungani_payments;
begin
  if not public.is_ungani_admin() then
    return jsonb_build_object(
      'ok', false,
      'message', 'Admin access required.'
    );
  end if;

  update public.ungani_payments
  set
    payment_status = p_status,
    paid_at = case when p_status = 'paid' then coalesce(paid_at, now()) else paid_at end,
    updated_at = now()
  where id = p_payment_id
  returning *
  into v_record;

  if v_record.id is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'Payment record not found.'
    );
  end if;

  if p_status = 'paid' then
    begin
      perform public.set_ungani_subscription_period_from_payment(v_record.id);
    exception
      when others then
        raise warning 'Could not update subscription period for payment %: %', v_record.id, sqlerrm;
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'message', 'Payment status updated.',
    'record', to_jsonb(v_record)
  );
exception
  when others then
    return jsonb_build_object(
      'ok', false,
      'message', sqlerrm
    );
end;
$function$;

create or replace function public.mark_admin_ungani_billing_record_paid(p_record_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_record public.ungani_payments;
begin
  if not public.is_ungani_admin() then
    return jsonb_build_object(
      'ok', false,
      'message', 'Admin access required.'
    );
  end if;

  update public.ungani_payments
  set
    payment_status = 'paid',
    paid_at = coalesce(paid_at, current_date),
    updated_at = now()
  where id = p_record_id
  returning *
  into v_record;

  if v_record.id is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'Billing record not found.'
    );
  end if;

  begin
    perform public.set_ungani_subscription_period_from_payment(v_record.id);
  exception
    when others then
      raise warning 'Could not update subscription period for payment %: %', v_record.id, sqlerrm;
  end;

  return jsonb_build_object(
    'ok', true,
    'message', 'Billing record marked as paid.',
    'record', jsonb_build_object(
      'id', v_record.id,
      'tenant_id', v_record.tenant_id,
      'package_key', v_record.package_key,
      'amount', v_record.amount,
      'currency', v_record.currency,
      'billing_start', v_record.billing_period_start,
      'billing_end', v_record.billing_period_end,
      'due_date', v_record.due_date,
      'paid_date', v_record.paid_at,
      'payment_status', v_record.payment_status,
      'payment_method', v_record.payment_method,
      'payment_reference', v_record.payment_reference,
      'invoice_number', v_record.invoice_number,
      'notes', v_record.notes,
      'created_by', v_record.recorded_by,
      'created_at', v_record.created_at,
      'updated_at', v_record.updated_at
    )
  );
exception
  when others then
    return jsonb_build_object(
      'ok', false,
      'message', sqlerrm
    );
end;
$function$;


-- ---------------------------------------------------------------------
-- SECTION 5b: queue_ungani_payment_confirmation_email gains two new
-- optional parameters so the ONE receipt email can state the real
-- outcome - the extension date, and any credit carried forward - rather
-- than a generic "payment received" that would otherwise apply
-- identically whether the payment merely completed a period or also
-- left money over. Explicit DROP first: changing the parameter list
-- via bare CREATE OR REPLACE creates a second overload alongside the
-- old 1-arg version rather than replacing it (same overload-drift class
-- of bug already found once this project, in
-- owner_upsert_ungani_team_member) - with both present, a 1-arg call
-- would still resolve ambiguously/incorrectly instead of cleanly
-- picking up the new behavior.
-- ---------------------------------------------------------------------

drop function if exists public.queue_ungani_payment_confirmation_email(uuid);

create or replace function public.queue_ungani_payment_confirmation_email(
  p_payment_id uuid,
  p_subscription_ends_at timestamptz default null,
  p_credit_carried_forward numeric default null
)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_payment public.ungani_payments;
  v_recipient_email text;
  v_recipient_name text;
  v_package_name text;
  v_amount_text text;
  v_date_text text;
  v_extension_line text := '';
  v_credit_line text := '';
begin
  select * into v_payment from public.ungani_payments where id = p_payment_id;

  if v_payment.id is null then
    return;
  end if;

  select coalesce(t.business_email, ''), coalesce(t.contact_person, t.business_name, 'there')
  into v_recipient_email, v_recipient_name
  from public.tenants t
  where t.id = v_payment.tenant_id;

  v_recipient_email := nullif(trim(coalesce(v_recipient_email, '')), '');

  if v_recipient_email is null then
    return;
  end if;

  if exists (
    select 1 from public.ungani_email_queue
    where email_type = 'payment_approved'
      and related_table = 'ungani_payments'
      and related_id = p_payment_id
  ) then
    return;
  end if;

  select package_name into v_package_name
  from public.ungani_packages
  where package_key = v_payment.package_key
  limit 1;

  v_amount_text := coalesce(v_payment.currency, 'KES') || ' ' || to_char(coalesce(v_payment.amount, 0), 'FM999,999,990.00');
  v_date_text := to_char(coalesce(v_payment.paid_at, now()), 'DD Mon YYYY');

  if p_subscription_ends_at is not null then
    v_extension_line := 'Your subscription is now active through ' || to_char(p_subscription_ends_at, 'DD Mon YYYY') || '.' || E'\n';
  end if;

  if p_credit_carried_forward is not null and p_credit_carried_forward > 0 then
    v_credit_line := 'You have KES ' || to_char(p_credit_carried_forward, 'FM999,999,990.00') ||
      ' in credit, automatically applied toward your next billing period.' || E'\n';
  end if;

  insert into public.ungani_email_queue (
    tenant_id,
    recipient_email,
    recipient_name,
    email_subject,
    email_body,
    email_type,
    related_table,
    related_id,
    send_status,
    created_at
  ) values (
    v_payment.tenant_id,
    v_recipient_email,
    v_recipient_name,
    'Your UNGANI OS payment receipt' || (case when v_payment.invoice_number is not null then ' - Invoice ' || v_payment.invoice_number else '' end),
    'Hi ' || v_recipient_name || E'\n\n' ||
    'This confirms your payment has been received and processed.' || E'\n\n' ||
    'Amount paid: ' || v_amount_text || E'\n' ||
    (case when v_package_name is not null then 'Package: ' || v_package_name || E'\n' else '' end) ||
    (case when v_payment.invoice_number is not null then 'Invoice: ' || v_payment.invoice_number || E'\n' else '' end) ||
    'Date: ' || v_date_text || E'\n\n' ||
    v_extension_line ||
    v_credit_line ||
    E'\n' ||
    'Thank you for your business.' || E'\n\n' ||
    'Regards,' || E'\n' ||
    'UNGANI' || E'\n' ||
    'info@ungani.com',
    'payment_approved',
    'ungani_payments',
    p_payment_id,
    'pending',
    now()
  );
exception
  when others then
    raise warning 'Could not queue payment-confirmation email for payment %: %', p_payment_id, sqlerrm;
end;
$function$;

revoke all on function public.queue_ungani_payment_confirmation_email(uuid, timestamptz, numeric) from public, anon;
grant execute on function public.queue_ungani_payment_confirmation_email(uuid, timestamptz, numeric) to authenticated, service_role;


-- ---------------------------------------------------------------------
-- SECTION 6: New supporting functions.
-- ---------------------------------------------------------------------

create or replace function public.queue_ungani_partial_payment_email(p_payment_id uuid, p_amount_paid_total numeric, p_amount_due numeric)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_payment public.ungani_payments;
  v_recipient_email text;
  v_recipient_name text;
  v_balance numeric;
begin
  select * into v_payment from public.ungani_payments where id = p_payment_id;
  if v_payment.id is null then
    return;
  end if;

  select coalesce(t.business_email, ''), coalesce(t.contact_person, t.business_name, 'there')
  into v_recipient_email, v_recipient_name
  from public.tenants t
  where t.id = v_payment.tenant_id;

  v_recipient_email := nullif(trim(coalesce(v_recipient_email, '')), '');
  if v_recipient_email is null then
    return;
  end if;

  if exists (
    select 1 from public.ungani_email_queue
    where email_type = 'partial_payment_received'
      and related_table = 'ungani_payments'
      and related_id = p_payment_id
  ) then
    return;
  end if;

  v_balance := greatest(coalesce(p_amount_due, 0) - coalesce(p_amount_paid_total, 0), 0);

  insert into public.ungani_email_queue (
    tenant_id, recipient_email, recipient_name, email_subject, email_body,
    email_type, related_table, related_id, send_status, created_at
  ) values (
    v_payment.tenant_id,
    v_recipient_email,
    v_recipient_name,
    'Payment received - balance still due',
    'Hi ' || v_recipient_name || E',\n\n' ||
    'We received a payment of KES ' || to_char(coalesce(v_payment.amount, 0), 'FM999,999,990.00') || '.' || E'\n' ||
    'Total paid toward this billing period so far: KES ' || to_char(coalesce(p_amount_paid_total, 0), 'FM999,999,990.00') || E'\n' ||
    'Remaining balance: KES ' || to_char(v_balance, 'FM999,999,990.00') || E'\n\n' ||
    'Your subscription period will be extended once the balance is fully paid.' || E'\n\n' ||
    'Regards,' || E'\n' ||
    'UNGANI' || E'\n' ||
    'info@ungani.com',
    'partial_payment_received',
    'ungani_payments',
    p_payment_id,
    'pending',
    now()
  );
exception
  when others then
    raise warning 'Could not queue partial-payment email for payment %: %', p_payment_id, sqlerrm;
end;
$function$;

create or replace function public.admin_get_ungani_payment_processing_failures()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_ungani_admin() then
    return jsonb_build_object('ok', false, 'message', 'Admin access required.');
  end if;

  return jsonb_build_object(
    'ok', true,
    'failures', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', f.id, 'payment_id', f.payment_id, 'tenant_id', f.tenant_id,
        'failure_stage', f.failure_stage, 'error_message', f.error_message,
        'occurred_at', f.occurred_at, 'resolved', f.resolved,
        'resolved_at', f.resolved_at, 'resolution_note', f.resolution_note
      ) order by f.occurred_at desc)
      from public.ungani_payment_processing_failures f
      where f.resolved = false
    ), '[]'::jsonb)
  );
end;
$function$;

create or replace function public.admin_resolve_ungani_payment_processing_failure(p_failure_id uuid, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_ungani_admin() then
    return jsonb_build_object('ok', false, 'message', 'Admin access required.');
  end if;

  update public.ungani_payment_processing_failures
  set resolved = true, resolved_at = now(), resolved_by = auth.uid(), resolution_note = p_note
  where id = p_failure_id;

  if not found then
    return jsonb_build_object('ok', false, 'message', 'Failure record not found.');
  end if;

  return jsonb_build_object('ok', true);
end;
$function$;

create or replace function public.admin_get_ungani_payment_duplicate_flags()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if not public.is_ungani_admin() then
    return jsonb_build_object('ok', false, 'message', 'Admin access required.');
  end if;

  return jsonb_build_object(
    'ok', true,
    'flags', coalesce((
      select jsonb_agg(jsonb_build_object(
        'id', d.id, 'payment_id', d.payment_id, 'tenant_id', d.tenant_id,
        'payment_reference', d.payment_reference, 'duplicate_of_payment_id', d.duplicate_of_payment_id,
        'amount', d.amount, 'status', d.status, 'flagged_at', d.flagged_at,
        'resolved_at', d.resolved_at, 'resolution_note', d.resolution_note
      ) order by d.flagged_at desc)
      from public.ungani_payment_duplicate_flags d
      where d.status = 'pending_review'
    ), '[]'::jsonb)
  );
end;
$function$;

create or replace function public.admin_resolve_ungani_payment_duplicate(p_flag_id uuid, p_resolution text, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_flag public.ungani_payment_duplicate_flags;
begin
  if not public.is_ungani_admin() then
    return jsonb_build_object('ok', false, 'message', 'Admin access required.');
  end if;

  if p_resolution not in ('applied_as_extra_period', 'marked_for_refund') then
    return jsonb_build_object('ok', false, 'message', 'Invalid resolution - must be applied_as_extra_period or marked_for_refund.');
  end if;

  select * into v_flag from public.ungani_payment_duplicate_flags
  where id = p_flag_id and status = 'pending_review';

  if v_flag.id is null then
    return jsonb_build_object('ok', false, 'message', 'Duplicate flag not found or already resolved.');
  end if;

  update public.ungani_payment_duplicate_flags
  set status = p_resolution, resolved_at = now(), resolved_by = auth.uid(), resolution_note = p_note
  where id = p_flag_id;

  if p_resolution = 'applied_as_extra_period' then
    -- p_skip_duplicate_check = true: an admin has deliberately reviewed
    -- this and confirmed it should be applied. Without the bypass, the
    -- normal duplicate check inside the core function would immediately
    -- re-flag this payment against the same other payment it was
    -- originally flagged against - that payment is (correctly) still
    -- applied, so the check would otherwise never let this one through.
    perform public.set_ungani_subscription_period_from_payment(v_flag.payment_id, true);
  end if;

  return jsonb_build_object('ok', true, 'resolution', p_resolution);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

create or replace function public.get_my_ungani_billing_status()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_sub public.ungani_subscriptions;
  v_pending_downgrade_name text;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found for this user.');
  end if;

  select * into v_sub from public.ungani_subscriptions where tenant_id = v_tenant_id;

  if v_sub.pending_downgrade_package_key is not null then
    select package_name into v_pending_downgrade_name
    from public.ungani_packages where package_key = v_sub.pending_downgrade_package_key;
  end if;

  return jsonb_build_object(
    'ok', true,
    'subscription_status', coalesce(v_sub.subscription_status, 'trial'),
    'payment_status', coalesce(v_sub.payment_status, 'trial'),
    'subscription_ends_at', v_sub.subscription_ends_at,
    'period_amount_due_ksh', v_sub.period_amount_due_ksh,
    'period_amount_paid_ksh', coalesce(v_sub.period_amount_paid_ksh, 0),
    'credit_balance_ksh', coalesce(v_sub.credit_balance_ksh, 0),
    'user_limit', v_sub.user_limit,
    'pending_downgrade_package_key', v_sub.pending_downgrade_package_key,
    'pending_downgrade_package_name', v_pending_downgrade_name,
    'pending_downgrade_requested_at', v_sub.pending_downgrade_requested_at
  );
end;
$function$;

-- (item-1 addendum: package change via payment) Replaces the "why do you
-- want to upgrade"/admin-approval flow entirely. One call, one decision:
--   - Target is cheaper than the current package (a genuine downgrade):
--     schedule it for the next renewal, no payment now, no refund for time
--     already paid on the current (better) package - matches Chris's
--     explicit spec exactly.
--   - Target is the same price or more expensive (upgrade, or a plain
--     renewal of the same package): create or reuse a pending
--     ungani_payments row carrying the chosen package_key and the real
--     amount due right now, which the new payment screen (STK/Paybill/
--     bank) pays against directly - the payment itself is what makes
--     set_ungani_subscription_period_from_payment apply the new package,
--     per the existing v_payment.package_key-first resolution it already
--     had from the first review round.
-- 'custom' packages are deliberately excluded - that pricing is manual/
-- negotiated, never self-serve.
create or replace function public.client_request_ungani_package_payment(p_package_key text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_target public.ungani_packages;
  v_current_package_key text;
  v_current_package public.ungani_packages;
  v_billing_cycle text;
  v_current_base_price numeric;
  v_target_base_price numeric;
  v_branch_addon numeric;
  v_billable_branches int;
  v_amount numeric;
  v_pending_with_proof_id uuid;
  v_pending_with_proof_amount numeric;
  v_payment_id uuid;
  v_period_start date;
  v_period_end date;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select * into v_target from public.ungani_packages
  where package_key = lower(trim(coalesce(p_package_key, '')))
    and is_active = true;

  if v_target.id is null then
    return jsonb_build_object('ok', false, 'message', 'Package not found.');
  end if;

  if coalesce(v_target.is_custom, false) then
    return jsonb_build_object('ok', false, 'message', 'Custom pricing is arranged directly with UNGANI - contact support to change to this package.');
  end if;

  select coalesce(billing_cycle, 'monthly') into v_billing_cycle
  from public.tenants where id = v_tenant_id;

  select package_key into v_current_package_key
  from public.ungani_subscriptions where tenant_id = v_tenant_id;

  if v_current_package_key is not null then
    select * into v_current_package from public.ungani_packages where package_key = v_current_package_key;
  end if;

  v_current_base_price := case when v_billing_cycle = 'yearly' then v_current_package.yearly_price_ksh else v_current_package.monthly_price_ksh end;
  v_target_base_price := case when v_billing_cycle = 'yearly' then v_target.yearly_price_ksh else v_target.monthly_price_ksh end;

  -- Downgrade: only when there IS a current package to compare against,
  -- it's genuinely cheaper, and it's actually a different package (picking
  -- the same package again is treated as a renewal, below, not a no-op
  -- downgrade).
  if v_current_package.id is not null
     and v_target.package_key <> v_current_package.package_key
     and v_target_base_price is not null
     and v_current_base_price is not null
     and v_target_base_price < v_current_base_price then

    update public.ungani_subscriptions
    set pending_downgrade_package_key = v_target.package_key,
        pending_downgrade_requested_at = now(),
        updated_at = now()
    where tenant_id = v_tenant_id;

    return jsonb_build_object(
      'ok', true,
      'action', 'scheduled_downgrade',
      'package_key', v_target.package_key,
      'package_name', v_target.package_name,
      'effective_at', (select subscription_ends_at from public.ungani_subscriptions where tenant_id = v_tenant_id),
      'message', 'Your plan will change to ' || v_target.package_name || ' at your next renewal. No payment is needed now, and there is no refund for the current period.'
    );
  end if;

  -- Upgrade or same-package renewal: an active payment already exists for
  -- this exact package with a proof uploaded and awaiting admin review -
  -- hand that back as-is rather than creating a second, confusing pending
  -- row for the same thing.
  select p.id, p.amount into v_pending_with_proof_id, v_pending_with_proof_amount
  from public.ungani_payments p
  where p.tenant_id = v_tenant_id
    and p.package_key = v_target.package_key
    and p.payment_status = 'pending'
    and exists (select 1 from public.ungani_payment_proofs pp where pp.payment_id = p.id)
  order by p.created_at desc
  limit 1;

  if v_pending_with_proof_id is not null then
    return jsonb_build_object(
      'ok', true,
      'action', 'proof_pending_review',
      'payment_id', v_pending_with_proof_id,
      'package_key', v_target.package_key,
      'package_name', v_target.package_name,
      'amount', v_pending_with_proof_amount,
      'currency', 'KES',
      'message', 'Your payment proof for this package is already uploaded and awaiting UNGANI review.'
    );
  end if;

  -- Supersede any other no-proof pending payment this tenant has (an
  -- abandoned earlier click, or a change of mind on which package to pay
  -- for) so repeated visits to the package page never pile up pending
  -- rows in admin. Never touches a payment that already has proof
  -- attached - that one is handled above.
  update public.ungani_payments
  set payment_status = 'cancelled', updated_at = now(),
      notes = coalesce(notes || E'\n', '') || 'Auto-cancelled: superseded by a new package selection.'
  where tenant_id = v_tenant_id
    and payment_status = 'pending'
    and not exists (select 1 from public.ungani_payment_proofs pp where pp.payment_id = ungani_payments.id);

  v_branch_addon := public.ungani_get_branch_addon_amount(v_tenant_id);
  v_billable_branches := public.ungani_get_billable_branch_count(v_tenant_id);
  v_amount := round(coalesce(v_target_base_price, 0) + coalesce(v_branch_addon, 0));

  v_period_start := current_date;
  v_period_end := case when v_billing_cycle = 'yearly' then (v_period_start + interval '1 year')::date else (v_period_start + interval '1 month')::date end;

  -- Picking a NEW/different package to pay for also cancels any
  -- previously scheduled downgrade - an active upgrade/renewal payment
  -- overrides an earlier "change my mind later" choice.
  update public.ungani_subscriptions
  set pending_downgrade_package_key = null,
      pending_downgrade_requested_at = null,
      updated_at = now()
  where tenant_id = v_tenant_id
    and pending_downgrade_package_key is not null;

  insert into public.ungani_payments (
    tenant_id, package_key, amount, branch_addon_amount, billable_branch_count,
    currency, billing_period_start, billing_period_end, due_date,
    payment_status, notes, created_at, updated_at
  ) values (
    v_tenant_id, v_target.package_key, v_amount, coalesce(v_branch_addon, 0), coalesce(v_billable_branches, 0),
    'KES', v_period_start, v_period_end, v_period_end,
    'pending', 'Created from package selection (' || v_target.package_name || ').',
    now(), now()
  )
  returning id into v_payment_id;

  return jsonb_build_object(
    'ok', true,
    'action', 'payment_required',
    'payment_id', v_payment_id,
    'package_key', v_target.package_key,
    'package_name', v_target.package_name,
    'amount', v_amount,
    'currency', 'KES',
    'billing_cycle', v_billing_cycle,
    'billing_period_start', v_period_start,
    'billing_period_end', v_period_end,
    'branch_addon_amount', coalesce(v_branch_addon, 0),
    'billable_branch_count', coalesce(v_billable_branches, 0)
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;


-- ---------------------------------------------------------------------
-- SECTION 6b: get_my_ungani_payment_access_status - found while auditing
-- every live reader of payment_status (per the standing checklist) for
-- 'partial' misclassification. Confirmed via grep this function has ZERO
-- callers anywhere in the codebase today - the real, live gate is
-- client-access-guard.js -> get_my_ungani_access_status ->
-- get_ungani_tenant_access_status, which already correctly returns
-- 'payment_warning' (access allowed) for a 'partial' payment_status, and
-- client-access-guard.js's allowedStatuses list already includes
-- "payment_warning". So this fix has no live effect today - fixing it
-- anyway since it's a one-line change and leaving a known landmine in an
-- unused function is how these bugs resurface later if it's ever wired
-- up. Before: 'partial' fell through every named case into
-- 'review_required' instead of being recognized - the same misreading
-- this round's audit was specifically checking for.
-- ---------------------------------------------------------------------

create or replace function public.get_my_ungani_payment_access_status()
 RETURNS TABLE(tenant_id uuid, package_key text, subscription_status text, payment_status text, payment_access_status text, trial_end_at timestamp with time zone, grace_until timestamp with time zone, suspend_after timestamp with time zone, multi_branch_enabled boolean)
 LANGUAGE sql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  with my_sub as (
    select
      s.tenant_id,
      s.package_key,
      s.subscription_status,
      s.payment_status,
      s.trial_end_at,
      s.multi_branch_enabled
    from public.ungani_subscriptions s
    where s.tenant_id = public.get_my_ungani_tenant_id()
    order by s.trial_start_at desc nulls last
    limit 1
  ),
  safety as (
    select
      coalesce(ss.payment_grace_days, 7) as payment_grace_days,
      coalesce(ss.payment_suspend_days, 30) as payment_suspend_days
    from my_sub ms
    left join public.ungani_tenant_safety_settings ss
      on ss.tenant_id = ms.tenant_id
  )
  select
    ms.tenant_id,
    ms.package_key,
    ms.subscription_status,
    ms.payment_status,
    case
      when ms.subscription_status in ('active', 'trial')
        and coalesce(ms.payment_status, 'paid') in ('paid', 'trial', 'current')
        then 'active'

      -- 'partial' means a period is still in progress with time paid
      -- toward it (early/legitimate partial payment) - not overdue, not
      -- blocked. Matches get_ungani_tenant_access_status's
      -- 'payment_warning' semantics exactly.
      when ms.subscription_status in ('active', 'trial')
        and coalesce(ms.payment_status, '') = 'partial'
        then 'payment_warning'

      when ms.trial_end_at is not null
        and now() <= (ms.trial_end_at + ((select payment_grace_days from safety) || ' days')::interval)
        then 'grace'

      when ms.trial_end_at is not null
        and now() > (ms.trial_end_at + ((select payment_grace_days from safety) || ' days')::interval)
        and now() <= (ms.trial_end_at + ((select payment_suspend_days from safety) || ' days')::interval)
        then 'read_only'

      when ms.subscription_status in ('suspended', 'cancelled')
        then 'suspended'

      else 'review_required'
    end as payment_access_status,
    ms.trial_end_at,
    case
      when ms.trial_end_at is null then null
      else ms.trial_end_at + ((select payment_grace_days from safety) || ' days')::interval
    end as grace_until,
    case
      when ms.trial_end_at is null then null
      else ms.trial_end_at + ((select payment_suspend_days from safety) || ' days')::interval
    end as suspend_after,
    coalesce(ms.multi_branch_enabled, false) as multi_branch_enabled
  from my_sub ms;
$function$;


-- ---------------------------------------------------------------------
-- SECTION 7: Grants. Every function touched or created above, explicit
-- revoke-then-grant - no function relies on a leftover prior grant.
-- ---------------------------------------------------------------------

revoke all on function public.calculate_ungani_subscription_amount(uuid) from public, anon;
grant execute on function public.calculate_ungani_subscription_amount(uuid) to authenticated, service_role;

-- set_ungani_subscription_period_from_payment(uuid, boolean) is granted
-- right after its own CREATE in SECTION 4 - not repeated here, since its
-- signature changed (the old (uuid) grant would error: that exact
-- signature no longer exists after the DROP above).

revoke all on function public.admin_accept_ungani_payment_proof_and_mark_paid(uuid, text, text, text) from public, anon;
grant execute on function public.admin_accept_ungani_payment_proof_and_mark_paid(uuid, text, text, text) to authenticated, service_role;

revoke all on function public.admin_update_ungani_payment_status(uuid, text) from public, anon;
grant execute on function public.admin_update_ungani_payment_status(uuid, text) to authenticated, service_role;

revoke all on function public.mark_admin_ungani_billing_record_paid(uuid) from public, anon;
grant execute on function public.mark_admin_ungani_billing_record_paid(uuid) to authenticated, service_role;

revoke all on function public.queue_ungani_partial_payment_email(uuid, numeric, numeric) from public, anon, authenticated;
grant execute on function public.queue_ungani_partial_payment_email(uuid, numeric, numeric) to service_role;

revoke all on function public.admin_get_ungani_payment_processing_failures() from public, anon;
grant execute on function public.admin_get_ungani_payment_processing_failures() to authenticated;

revoke all on function public.admin_resolve_ungani_payment_processing_failure(uuid, text) from public, anon;
grant execute on function public.admin_resolve_ungani_payment_processing_failure(uuid, text) to authenticated;

revoke all on function public.admin_get_ungani_payment_duplicate_flags() from public, anon;
grant execute on function public.admin_get_ungani_payment_duplicate_flags() to authenticated;

revoke all on function public.admin_resolve_ungani_payment_duplicate(uuid, text, text) from public, anon;
grant execute on function public.admin_resolve_ungani_payment_duplicate(uuid, text, text) to authenticated;

revoke all on function public.get_my_ungani_billing_status() from public, anon;
grant execute on function public.get_my_ungani_billing_status() to authenticated;

revoke all on function public.client_request_ungani_package_payment(text) from public, anon;
grant execute on function public.client_request_ungani_package_payment(text) to authenticated;

revoke all on function public.get_my_ungani_payment_access_status() from public, anon;
grant execute on function public.get_my_ungani_payment_access_status() to authenticated;


-- ---------------------------------------------------------------------
-- SECTION 8: One combined verification SELECT.
-- Expect: functions_created = 14, anon_or_public_exec = null (empty -
-- meaning zero rows have anon/public execute across all 14), grant
-- shape for set_ungani_subscription_period_from_payment shows
-- service_role only, confirmation_email_overload_count = 1 (the old
-- 1-arg version is gone, only the new 3-arg one exists),
-- new_columns_count = 6, new_tables_count = 2.
-- ---------------------------------------------------------------------

select jsonb_build_object(
  'functions_created', (
    select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'calculate_ungani_subscription_amount', 'set_ungani_subscription_period_from_payment',
      'admin_accept_ungani_payment_proof_and_mark_paid', 'admin_update_ungani_payment_status',
      'mark_admin_ungani_billing_record_paid', 'queue_ungani_payment_confirmation_email',
      'queue_ungani_partial_payment_email',
      'admin_get_ungani_payment_processing_failures', 'admin_resolve_ungani_payment_processing_failure',
      'admin_get_ungani_payment_duplicate_flags', 'admin_resolve_ungani_payment_duplicate',
      'get_my_ungani_billing_status', 'client_request_ungani_package_payment',
      'get_my_ungani_payment_access_status'
    )
  ),
  'anon_or_public_exec', (
    select jsonb_agg(p.proname) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname in (
      'calculate_ungani_subscription_amount', 'set_ungani_subscription_period_from_payment',
      'admin_accept_ungani_payment_proof_and_mark_paid', 'admin_update_ungani_payment_status',
      'mark_admin_ungani_billing_record_paid', 'queue_ungani_payment_confirmation_email',
      'queue_ungani_partial_payment_email',
      'admin_get_ungani_payment_processing_failures', 'admin_resolve_ungani_payment_processing_failure',
      'admin_get_ungani_payment_duplicate_flags', 'admin_resolve_ungani_payment_duplicate',
      'get_my_ungani_billing_status', 'client_request_ungani_package_payment',
      'get_my_ungani_payment_access_status'
    ) and (has_function_privilege('anon', p.oid, 'execute') or has_function_privilege('public', p.oid, 'execute'))
  ),
  'set_period_grant_shape', (
    select jsonb_build_object(
      'anon', has_function_privilege('anon', p.oid, 'execute'),
      'authenticated', has_function_privilege('authenticated', p.oid, 'execute'),
      'service_role', has_function_privilege('service_role', p.oid, 'execute')
    )
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'set_ungani_subscription_period_from_payment'
  ),
  'confirmation_email_overload_count', (
    select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'queue_ungani_payment_confirmation_email'
  ),
  'new_columns_count', (
    select count(*) from information_schema.columns
    where table_schema = 'public' and (
      (table_name = 'ungani_subscriptions' and column_name in (
        'period_amount_due_ksh', 'period_amount_paid_ksh', 'credit_balance_ksh',
        'pending_downgrade_package_key', 'pending_downgrade_requested_at'
      ))
      or (table_name = 'ungani_payments' and column_name = 'applied_to_subscription_at')
    )
  ),
  'new_tables_count', (
    select count(*) from information_schema.tables
    where table_schema = 'public' and table_name in ('ungani_payment_processing_failures', 'ungani_payment_duplicate_flags')
  )
) as verification_result;
