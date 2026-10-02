-- =====================================================================
-- Item 1: Subscription billing - FINAL SPEC build.
-- Supersedes sql/item1-subscription-billing-fix.sql (kept for history).
-- Rewritten end-to-end from LIVE definitions pulled this conversation.
--
-- Implements, in one coherent design (rule numbers match the final spec):
--  1. Price = package price for the tenant's billing cycle + branch
--     add-on, rounded to whole KES INSIDE calculate_ungani_subscription_
--     amount itself - every caller gets a pre-rounded number for free.
--  2. A payment's period due is always priced for THAT payment's own
--     package (v_payment_package_key), never the subscription's current
--     package - this was the root bug: pricing used to come from the
--     tenant's CURRENT package regardless of which package the payment
--     was actually for, so an upgrade payment was priced like a renewal.
--  3. Mid-period package switch: a new column, period_package_key, tracks
--     which package the IN-PROGRESS tracked period belongs to (separate
--     from the subscription's currently-ACTIVE package_key - these two
--     can legitimately differ while an upgrade is still being paid off in
--     installments). A payment whose package differs from
--     period_package_key moves whatever was paid toward the old period
--     into credit_balance_ksh and starts the new package's period fresh.
--  4. Fully paid: extend floor(available/due) periods (max 24) from the
--     later of now/paid_at and the existing end date. Package changes
--     immediately. Leftover becomes credit. user_limit synced from the
--     new package. Receipt email gets the new end date + any credit line.
--  5. Partial: no extension, payment_status 'partial', package_key is
--     NEVER touched by a partial payment - only a FULLY paid period ever
--     changes it. access (subscription_status) is untouched.
--  6. Price can't be computed: logged to
--     ungani_payment_processing_failures, payment left with
--     applied_to_subscription_at still null (so it can be retried), NO
--     extension, never silently treated as paid. This replaces the old
--     "v_period_due is null -> treat as fully paid" shortcut entirely.
--  7. Idempotent via ungani_payments.applied_to_subscription_at, guarded
--     by FOR UPDATE locks on both the payment row and the subscription
--     row (prevents lost updates between two simultaneous payments for
--     the same tenant).
--  8. Duplicate payment_reference detection only flags against a twin
--     that is ALREADY applied (avoids a deadlock where two genuinely
--     simultaneous duplicates both flag each other and neither applies).
--     admin_resolve_ungani_payment_duplicate's "apply as extra period"
--     bypasses the check, then VERIFIES applied_to_subscription_at
--     actually got set - if not, rolls the flag back to pending_review
--     instead of falsely reporting success. "Mark for refund" flips the
--     underlying payment's own payment_status to 'refunded', which is
--     what excludes it from admin revenue totals (see code-side fix
--     below for admin-home.html / admin-billing.html).
--  9. Downgrade: scheduled on ungani_subscriptions.pending_downgrade_
--     package_key, no payment taken immediately. calculate_ungani_
--     subscription_amount's own package-key resolution (when no explicit
--     override is given) now prefers a pending downgrade over the
--     subscription's current package - so EVERY caller that prices a
--     plain renewal (the M-Pesa webhook, the monthly billing-automation
--     function patched below, a future STK renewal button) automatically
--     prices and carries the downgraded package with zero per-caller
--     changes. It applies the moment that period is fully paid, via the
--     normal rule-2/rule-4 flow - no special-case branch needed inside
--     set_ungani_subscription_period_from_payment itself anymore.
-- 10. client_request_ungani_package_payment only auto-cancels earlier
--     pending payments it ITSELF created (source = 'package_selection')
--     that have no proof attached - a renewal invoice from billing
--     automation or an admin manual entry is never touched. Re-selecting
--     the same package while a proof is already pending hands that
--     payment back instead of creating a duplicate.
-- 11. Commission: onboarding = onboarding_rate x the due of the first
--     ever FULLY paid period, once (guarded by a partial unique index,
--     not a payment-count guess). Monthly = ongoing_rate x due x however
--     many ADDITIONAL periods this same payment covered, one combined
--     row. Real partner_commissions columns (source_payment_id, amount),
--     real commission_type values ('onboarding'/'monthly').
-- 12. Works when triggered by the M-Pesa webhook (service_role,
--     auth.uid() is null) - calculate_ungani_subscription_amount's access
--     check now only enforces the admin-or-own-tenant rule when there IS
--     a real authenticated caller (auth.uid() is not null); a service-role
--     / internal SECURITY DEFINER-to-SECURITY DEFINER call is a trusted
--     context already gated by the outer function's own grants.
-- 13. Grants: set_ungani_subscription_period_from_payment stays
--     service_role only. client-facing functions: authenticated only.
--     Nothing here is ever granted to anon or public.
-- =====================================================================


-- ---------------------------------------------------------------------
-- SECTION 1: New columns.
-- ---------------------------------------------------------------------

alter table public.ungani_subscriptions
  add column if not exists period_amount_due_ksh numeric,
  add column if not exists period_amount_paid_ksh numeric not null default 0,
  add column if not exists credit_balance_ksh numeric not null default 0,
  add column if not exists period_package_key text,
  add column if not exists pending_downgrade_package_key text,
  add column if not exists pending_downgrade_requested_at timestamptz;

alter table public.ungani_payments
  add column if not exists applied_to_subscription_at timestamptz,
  add column if not exists source text;


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
-- SECTION 3: calculate_ungani_subscription_amount.
-- Signature change (adds p_package_key_override) requires an explicit
-- DROP first - CREATE OR REPLACE with a different parameter list creates
-- a second overload rather than replacing the original (the same
-- overload-drift bug class already found once this project in
-- owner_upsert_ungani_team_member). The one live caller
-- (api/mpesa-stk-push.js) only ever passes p_tenant_id, which still
-- resolves correctly against the new signature via the added default.
-- ---------------------------------------------------------------------

drop function if exists public.calculate_ungani_subscription_amount(uuid);

create or replace function public.calculate_ungani_subscription_amount(
  p_tenant_id uuid,
  p_package_key_override text default null
)
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
  -- (12) Only enforce the access gate for a real authenticated caller.
  -- auth.uid() is null for the M-Pesa webhook's service_role client and
  -- for any internal call from another SECURITY DEFINER function - both
  -- are trusted contexts already locked down by their own grants/checks,
  -- not arbitrary callers this check needs to police.
  if auth.uid() is not null
     and not (
       (select public.is_ungani_admin())
       or p_tenant_id = (select public.get_my_ungani_tenant_id())
     )
  then
    raise exception 'Access denied';
  end if;

  if p_package_key_override is not null then
    v_package_key := p_package_key_override;
  else
    -- (9) A plain renewal (no override) prices at a pending downgrade if
    -- one is scheduled - this is the ONE place that decision lives, so
    -- every caller (webhook renewal, monthly billing automation, any
    -- future STK renewal button) inherits it automatically.
    select coalesce(s.pending_downgrade_package_key, s.package_key, 'starter') into v_package_key
    from public.ungani_subscriptions s
    where s.tenant_id = p_tenant_id;

    if v_package_key is null then
      v_package_key := 'starter';
    end if;
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

  -- (1) Rounded to whole KES here, once, so every caller (this function's
  -- own return value, and anything that stores it onto a payment row)
  -- already has an integer amount - no caller needs to remember to round.
  v_total := case when v_base_amount is null then null else round(v_base_amount + coalesce(v_branch_addon, 0)) end;

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

revoke all on function public.calculate_ungani_subscription_amount(uuid, text) from public, anon;
grant execute on function public.calculate_ungani_subscription_amount(uuid, text) to authenticated, service_role;


-- ---------------------------------------------------------------------
-- SECTION 4: set_ungani_subscription_period_from_payment - full rewrite.
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
  v_payment_package_key text;
  v_new_user_limit int;
  v_period_interval interval;

  v_expected jsonb;
  v_expected_total numeric;
  v_billable_branches int;

  v_package_changed_mid_period boolean;
  v_need_fresh_price boolean;
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
  -- (7) Lock this payment row first - a repeat/concurrent call for the
  -- SAME payment id blocks here until the first call commits.
  select * into v_payment from public.ungani_payments where id = p_payment_id for update;

  if v_payment.id is null or v_payment.payment_status <> 'paid' then
    return;
  end if;

  if v_payment.applied_to_subscription_at is not null then
    return;
  end if;

  -- (7) Ensure the subscription row exists, then lock it. Two payments
  -- for the SAME tenant arriving at once now serialize here - whichever
  -- call wins the lock applies first; the second correctly sees the
  -- first as already-applied.
  insert into public.ungani_subscriptions (tenant_id) values (v_payment.tenant_id)
  on conflict (tenant_id) do nothing;

  select * into v_sub from public.ungani_subscriptions where tenant_id = v_payment.tenant_id for update;

  -- (8) Only flag against a twin that is ALREADY applied - two genuinely
  -- simultaneous duplicates no longer both see "the other" as applied and
  -- both bail; the subscription-row lock above means whichever call wins
  -- applies first, and the second correctly flags against it.
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

  -- (1, 2) "A payment row carries its package_key and amount from
  -- creation" - trust it directly. The fallback chain only covers a
  -- legacy/defensive case where a payment row genuinely has no
  -- package_key at all.
  v_payment_package_key := coalesce(v_payment.package_key, v_sub.package_key, v_tenant_package_key, 'starter');

  -- (3) Is this payment for a DIFFERENT package than the one the
  -- currently in-progress tracked period belongs to? period_package_key
  -- (not the subscription's active package_key) is the right comparison
  -- - an upgrade can be mid-way through being paid off in installments
  -- while the ACTIVE package is still the old one.
  v_package_changed_mid_period := v_sub.period_amount_due_ksh is not null
    and v_sub.period_package_key is not null
    and v_sub.period_package_key <> v_payment_package_key;

  v_need_fresh_price := v_sub.period_amount_due_ksh is null or v_package_changed_mid_period;

  if v_need_fresh_price then
    begin
      v_expected := public.calculate_ungani_subscription_amount(v_payment.tenant_id, v_payment_package_key);
      v_expected_total := (v_expected->>'total_amount')::numeric;
      v_billable_branches := coalesce((v_expected->>'billable_branch_count')::int, 0);
    exception
      when others then
        insert into public.ungani_payment_processing_failures (payment_id, tenant_id, failure_stage, error_message)
        values (p_payment_id, v_payment.tenant_id, 'amount_calculation', sqlerrm);
        v_expected_total := null;
        v_billable_branches := 0;
    end;

    if v_expected_total is null then
      -- (6) Price can't be computed - log, leave unapplied (no update to
      -- applied_to_subscription_at below, since we return here), no
      -- extension. NEVER treat this as paid.
      insert into public.ungani_payment_processing_failures (payment_id, tenant_id, failure_stage, error_message)
      values (
        p_payment_id, v_payment.tenant_id, 'amount_calculation',
        'Could not determine a price for package "' || coalesce(v_payment_package_key, '(none)') || '" - payment left unapplied for admin review.'
      );
      return;
    end if;

    v_period_due := v_expected_total;
  else
    -- Continuing the same in-progress period for the same package - keep
    -- the price already locked in; a mid-period price change shouldn't
    -- move the goalposts. Still try a fresh calc purely for the
    -- drift-detection mismatch check below - a failure here is NOT fatal
    -- (unlike the branch above), since we already know what's due.
    v_period_due := v_sub.period_amount_due_ksh;

    begin
      v_expected := public.calculate_ungani_subscription_amount(v_payment.tenant_id, v_payment_package_key);
      v_expected_total := (v_expected->>'total_amount')::numeric;
      v_billable_branches := coalesce((v_expected->>'billable_branch_count')::int, 0);
    exception
      when others then
        v_expected_total := null;
        v_billable_branches := 0;
    end;
  end if;

  -- (3) A package switch moves whatever was paid toward the OLD period
  -- into credit and starts the new package's period fresh with just this
  -- payment counting toward it.
  if v_package_changed_mid_period then
    v_credit := coalesce(v_sub.credit_balance_ksh, 0) + coalesce(v_sub.period_amount_paid_ksh, 0);
    v_period_paid_so_far := v_payment.amount;
  else
    v_credit := coalesce(v_sub.credit_balance_ksh, 0);
    v_period_paid_so_far := coalesce(v_sub.period_amount_paid_ksh, 0) + v_payment.amount;
  end if;

  v_available := v_period_paid_so_far + v_credit;

  if v_available >= v_period_due then
    -- (4) Fully paid.
    if v_period_due <= 0 then
      -- A genuinely-priced free/zero package - any payment covers 1
      -- period outright. Distinct from rule 6 (price UNKNOWN, which
      -- already returned above) - this is a price KNOWN to be zero.
      v_periods_covered := 1;
      v_leftover := v_available;
    else
      v_periods_covered := least(floor(v_available / v_period_due)::int, 24);
      v_leftover := v_available - (v_periods_covered * v_period_due);
    end if;

    v_new_ends_at := greatest(coalesce(v_sub.subscription_ends_at, v_payment.paid_at), coalesce(v_payment.paid_at, now()))
      + (v_period_interval * v_periods_covered);

    select p.user_limit into v_new_user_limit
    from public.ungani_packages p
    where p.package_key = v_payment_package_key;

    insert into public.ungani_subscriptions (
      tenant_id, package_key, subscription_status, payment_status,
      subscription_ends_at, period_amount_due_ksh, period_amount_paid_ksh, period_package_key, credit_balance_ksh,
      user_limit, pending_downgrade_package_key, pending_downgrade_requested_at, updated_at
    ) values (
      v_payment.tenant_id, v_payment_package_key, 'active', 'paid',
      v_new_ends_at, null, 0, null, v_leftover,
      coalesce(v_new_user_limit, 2), null, null, now()
    )
    on conflict (tenant_id) do update set
      package_key = excluded.package_key,
      subscription_status = 'active',
      payment_status = 'paid',
      subscription_ends_at = excluded.subscription_ends_at,
      period_amount_due_ksh = null,
      period_amount_paid_ksh = 0,
      period_package_key = null,
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

    begin
      if v_expected_total is not null and round(v_expected_total) <> round(v_period_due) then
        insert into public.ungani_billing_amount_mismatches (
          tenant_id, payment_id, package_key, billing_cycle,
          expected_amount, actual_amount, difference, billable_branch_count
        ) values (
          v_payment.tenant_id, p_payment_id, v_payment_package_key, v_billing_cycle,
          round(v_expected_total), round(v_period_due), round(v_expected_total) - round(v_period_due), v_billable_branches
        );
      end if;
    exception
      when others then
        insert into public.ungani_payment_processing_failures (payment_id, tenant_id, failure_stage, error_message)
        values (p_payment_id, v_payment.tenant_id, 'billing_mismatch_check', sqlerrm);
    end;

    -- (11) Onboarding = rate x ONE period's due, only on the tenant's
    -- first-ever completed period (driven by whether an onboarding
    -- commission already exists for this partner/tenant pair). Any
    -- ADDITIONAL periods covered by THIS SAME payment earn the monthly
    -- rate instead, as one combined row.
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
                 round(v_period_due * v_onboarding_rate / 100, 2), 'owed')
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
                 round(v_period_due * v_additional_periods * v_ongoing_rate / 100, 2), 'owed')
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
    -- (5) Partial - accumulate, notify, do NOT extend, do NOT fire
    -- commission, do NOT log a mismatch, and - critically - do NOT touch
    -- package_key. subscription_status is also left untouched (access
    -- unchanged); payment_status moves to 'partial', never
    -- 'overdue'/'unpaid'/'failed'.
    update public.ungani_subscriptions
    set
      payment_status = 'partial',
      period_amount_due_ksh = v_period_due,
      period_amount_paid_ksh = v_period_paid_so_far,
      period_package_key = v_payment_package_key,
      credit_balance_ksh = v_credit,
      updated_at = now()
    where tenant_id = v_payment.tenant_id;

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
-- SECTION 5: The 3 admin "mark paid" wrappers - unchanged from the live
-- version except removing the direct, unconditional
-- queue_ungani_payment_confirmation_email call (that decision now
-- belongs solely to set_ungani_subscription_period_from_payment).
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
-- SECTION 5b: queue_ungani_payment_confirmation_email - unchanged from
-- the prior round (DROP+recreate for the same overload-safety reason).
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
-- SECTION 6: Supporting functions - partial-payment email, failure/
-- duplicate admin RPCs, billing-status readback, and the new package-
-- change-via-payment entry point.
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

-- (8) "Apply as extra period" now VERIFIES the apply actually succeeded
-- (checking applied_to_subscription_at directly, since the core function
-- swallows its own errors and always returns void either way) and rolls
-- the flag back to pending_review with the real error message if it
-- didn't - never reports success for something that silently failed.
-- "Mark for refund" now also flips the underlying payment's own
-- payment_status to 'refunded', which is what excludes it from admin
-- revenue totals (see the admin-home.html / admin-billing.html fix
-- notes at the end of this file - both already filter strictly on
-- payment_status = 'paid', so 'refunded' drops out for free).
create or replace function public.admin_resolve_ungani_payment_duplicate(p_flag_id uuid, p_resolution text, p_note text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_flag public.ungani_payment_duplicate_flags;
  v_applied_at timestamptz;
  v_last_failure text;
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
    perform public.set_ungani_subscription_period_from_payment(v_flag.payment_id, true);

    select applied_to_subscription_at into v_applied_at
    from public.ungani_payments
    where id = v_flag.payment_id;

    if v_applied_at is null then
      select error_message into v_last_failure
      from public.ungani_payment_processing_failures
      where payment_id = v_flag.payment_id
      order by occurred_at desc
      limit 1;

      update public.ungani_payment_duplicate_flags
      set status = 'pending_review', resolved_at = null, resolved_by = null,
          resolution_note = coalesce(p_note, resolution_note)
      where id = p_flag_id;

      return jsonb_build_object(
        'ok', false,
        'message', 'Could not apply this payment: ' || coalesce(v_last_failure, 'unknown error - check ungani_payment_processing_failures.')
      );
    end if;
  elsif p_resolution = 'marked_for_refund' then
    update public.ungani_payments
    set payment_status = 'refunded', updated_at = now()
    where id = v_flag.payment_id;
  end if;

  return jsonb_build_object('ok', true, 'resolution', p_resolution);
exception
  when others then
    if v_flag.id is not null and p_resolution = 'applied_as_extra_period' then
      update public.ungani_payment_duplicate_flags
      set status = 'pending_review', resolved_at = null, resolved_by = null
      where id = p_flag_id and status = p_resolution;
    end if;
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

-- (10) Replaces the "why do you want to upgrade" form/admin-approval
-- flow entirely. One call, one decision:
--  - Target cheaper than current: schedule it (pending_downgrade_
--    package_key), no payment now, no refund for the current period.
--  - Target same price or more (upgrade, or a plain renewal of the same
--    package): create/reuse a pending ungani_payments row with
--    source='package_selection', carrying the chosen package_key and its
--    real price (via calculate_ungani_subscription_amount, the same
--    canonical pricing function everything else uses now - no separate
--    inline price computation to drift out of sync).
-- Auto-cancel and the proof-pending lookup are BOTH scoped to
-- source='package_selection' - a renewal invoice created by billing
-- automation or an admin manual entry is never touched by either.
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
  v_current_computed jsonb;
  v_target_computed jsonb;
  v_current_total numeric;
  v_target_total numeric;
  v_amount numeric;
  v_branch_addon numeric;
  v_billable_branches int;
  v_pending_with_proof_id uuid;
  v_pending_with_proof_amount numeric;
  v_payment_id uuid;
  v_billing_cycle text;
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

  -- Compare against the CURRENTLY ACTIVE package's price explicitly (an
  -- override, not a bare call) - a bare call would price at any already-
  -- pending downgrade instead, which would wrongly answer "is this an
  -- upgrade or downgrade" relative to a future price, not today's.
  if v_current_package_key is not null then
    v_current_computed := public.calculate_ungani_subscription_amount(v_tenant_id, v_current_package_key);
    v_current_total := (v_current_computed->>'total_amount')::numeric;
  end if;

  v_target_computed := public.calculate_ungani_subscription_amount(v_tenant_id, v_target.package_key);
  v_target_total := (v_target_computed->>'total_amount')::numeric;

  if v_current_package_key is not null
     and v_target.package_key <> v_current_package_key
     and v_target_total is not null
     and v_current_total is not null
     and v_target_total < v_current_total then

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

  select p.id, p.amount into v_pending_with_proof_id, v_pending_with_proof_amount
  from public.ungani_payments p
  where p.tenant_id = v_tenant_id
    and p.package_key = v_target.package_key
    and p.payment_status = 'pending'
    and p.source = 'package_selection'
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

  -- (10) Only supersede OUR OWN earlier package-selection pending
  -- payments with no proof attached - never a renewal invoice created by
  -- billing automation or an admin manual entry.
  update public.ungani_payments
  set payment_status = 'cancelled', updated_at = now(),
      notes = coalesce(notes || E'\n', '') || 'Auto-cancelled: superseded by a new package selection.'
  where tenant_id = v_tenant_id
    and payment_status = 'pending'
    and source = 'package_selection'
    and not exists (select 1 from public.ungani_payment_proofs pp where pp.payment_id = ungani_payments.id);

  v_amount := v_target_total;
  v_branch_addon := coalesce((v_target_computed->>'branch_addon_amount')::numeric, 0);
  v_billable_branches := coalesce((v_target_computed->>'billable_branch_count')::int, 0);

  if v_amount is null then
    return jsonb_build_object('ok', false, 'message', 'This package has no price configured yet - contact UNGANI support.');
  end if;

  v_period_start := current_date;
  v_period_end := case when v_billing_cycle = 'yearly' then (v_period_start + interval '1 year')::date else (v_period_start + interval '1 month')::date end;

  update public.ungani_subscriptions
  set pending_downgrade_package_key = null,
      pending_downgrade_requested_at = null,
      updated_at = now()
  where tenant_id = v_tenant_id
    and pending_downgrade_package_key is not null;

  insert into public.ungani_payments (
    tenant_id, package_key, amount, branch_addon_amount, billable_branch_count,
    currency, billing_period_start, billing_period_end, due_date,
    payment_status, source, notes, created_at, updated_at
  ) values (
    v_tenant_id, v_target.package_key, v_amount, v_branch_addon, v_billable_branches,
    'KES', v_period_start, v_period_end, v_period_end,
    'pending', 'package_selection', 'Created from package selection (' || v_target.package_name || ').',
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
    'branch_addon_amount', v_branch_addon,
    'billable_branch_count', v_billable_branches
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

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

revoke all on function public.get_my_ungani_payment_access_status() from public, anon;
grant execute on function public.get_my_ungani_payment_access_status() to authenticated;


-- ---------------------------------------------------------------------
-- SECTION 6b: run_ungani_create_monthly_billing_records - minimal patch
-- for rule 9. Body is otherwise BYTE-IDENTICAL to the live version
-- pulled via discovery this conversation - only the v_package resolution
-- line changes, to prefer a pending downgrade over the stored package,
-- same as calculate_ungani_subscription_amount now does. This is the
-- automation path rule 9 explicitly calls out ("however it's created:
-- automation, STK renewal, package page").
-- ---------------------------------------------------------------------

create or replace function public.run_ungani_create_monthly_billing_records()
 RETURNS TABLE(payment_id uuid, tenant_id uuid, package_key text, amount numeric, billing_period_start date, billing_period_end date, due_date date, result_message text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  r record;

  v_month_start date;
  v_month_end date;
  v_period_start date;
  v_period_end date;
  v_due_date date;

  v_amount numeric;
  v_payment_id uuid;
  v_package text;
  v_subscription_status text;
  v_payment_status text;
  v_trial_end_date date;
begin
  v_month_start := date_trunc('month', current_date)::date;
  v_month_end := (date_trunc('month', current_date)::date + interval '1 month - 1 day')::date;

  for r in
    select distinct on (s.tenant_id)
      s.id as subscription_id,
      s.tenant_id,
      lower(coalesce(s.pending_downgrade_package_key, s.package_key, 'starter')) as package_key,
      lower(coalesce(s.subscription_status, 'trial')) as subscription_status,
      lower(coalesce(s.payment_status, 'pending')) as payment_status,
      s.trial_start_at,
      s.trial_end_at,
      s.user_limit,
      s.updated_at,
      s.created_at
    from public.ungani_subscriptions s
    where s.tenant_id is not null
    order by s.tenant_id, s.updated_at desc nulls last, s.created_at desc nulls last
  loop
    v_payment_id := null;
    v_package := lower(coalesce(r.package_key, 'starter'));
    v_subscription_status := lower(coalesce(r.subscription_status, 'trial'));
    v_payment_status := lower(coalesce(r.payment_status, 'pending'));

    -- Skip cancelled/suspended clients.
    if v_subscription_status in ('cancelled', 'canceled', 'suspended') then
      continue;
    end if;

    -- Skip custom package because custom pricing should be handled manually.
    if v_package = 'custom' then
      continue;
    end if;

    v_amount := public.get_ungani_package_monthly_amount(v_package);

    if v_amount is null then
      continue;
    end if;

    -- Trial handling:
    -- If trial_end_at is in the future, do not bill yet.
    if r.trial_end_at is not null then
      v_trial_end_date := r.trial_end_at::date;

      if v_trial_end_date >= current_date
         and v_subscription_status = 'trial' then
        continue;
      end if;

      -- If trial ended inside this month, billing period starts the day after trial.
      if v_trial_end_date >= v_month_start
         and v_trial_end_date <= v_month_end then
        v_period_start := v_trial_end_date + 1;
      else
        v_period_start := v_month_start;
      end if;
    else
      v_period_start := v_month_start;
    end if;

    v_period_end := v_month_end;

    -- Due date:
    -- If billing starts after the normal 7th, give 7 days from period start.
    -- Otherwise use the 7th day of the month.
    if v_period_start > (v_month_start + 6) then
      v_due_date := v_period_start + 6;
    else
      v_due_date := v_month_start + 6;
    end if;

    -- Avoid duplicate billing record for same tenant/package/month.
    if exists (
      select 1
      from public.ungani_payments p
      where p.tenant_id = r.tenant_id
        and lower(coalesce(p.package_key, 'starter')) = v_package
        and p.billing_period_start = v_period_start
        and p.billing_period_end = v_period_end
        and lower(coalesce(p.payment_status, 'pending')) not in ('cancelled', 'canceled')
    ) then
      continue;
    end if;

    insert into public.ungani_payments (
      tenant_id,
      subscription_id,
      package_key,
      amount,
      currency,
      billing_period_start,
      billing_period_end,
      due_date,
      payment_status,
      payment_method,
      payment_reference,
      notes,
      created_at,
      updated_at
    )
    values (
      r.tenant_id,
      r.subscription_id,
      v_package,
      v_amount,
      'KES',
      v_period_start,
      v_period_end,
      v_due_date,
      'pending',
      null,
      null,
      'Automatically generated monthly UNGANI OS billing record for '
        || public.get_ungani_package_display_name(v_package)
        || ' package.',
      now(),
      now()
    )
    returning id into v_payment_id;

    payment_id := v_payment_id;
    tenant_id := r.tenant_id;
    package_key := v_package;
    amount := v_amount;
    billing_period_start := v_period_start;
    billing_period_end := v_period_end;
    due_date := v_due_date;
    result_message :=
      'Monthly billing record created for '
      || public.get_ungani_package_display_name(v_package)
      || ' package: '
      || public.format_ungani_payment_amount(v_amount, 'KES')
      || '. Due date: '
      || to_char(v_due_date, 'DD Mon YYYY')
      || '.';

    return next;
  end loop;
end;
$function$;


-- ---------------------------------------------------------------------
-- SECTION 7: Grants. Every function touched or created above, explicit
-- revoke-then-grant - no function relies on a leftover prior grant.
-- (13) set_ungani_subscription_period_from_payment: service_role only.
-- Client-facing functions: authenticated only. Nothing to anon/public.
-- ---------------------------------------------------------------------

-- calculate_ungani_subscription_amount(uuid, text) granted right after
-- its own CREATE in SECTION 3.
-- set_ungani_subscription_period_from_payment(uuid, boolean) granted
-- right after its own CREATE in SECTION 4.
-- queue_ungani_payment_confirmation_email(uuid, timestamptz, numeric)
-- granted right after its own CREATE in SECTION 5b.
-- get_my_ungani_payment_access_status() granted right after its own
-- CREATE in SECTION 6.

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


-- ---------------------------------------------------------------------
-- SECTION 8: One combined verification SELECT.
-- Expect: functions_created = 15, anon_or_public_exec = null (empty),
-- set_period_grant_shape = service_role only, calc_amount_grant_shape =
-- authenticated+service_role (no anon), confirmation_email_overload_count
-- = 1, calc_amount_overload_count = 1, new_columns_count = 8,
-- new_tables_count = 2.
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
      'get_my_ungani_payment_access_status', 'run_ungani_create_monthly_billing_records'
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
  'calc_amount_grant_shape', (
    select jsonb_build_object(
      'anon', has_function_privilege('anon', p.oid, 'execute'),
      'authenticated', has_function_privilege('authenticated', p.oid, 'execute'),
      'service_role', has_function_privilege('service_role', p.oid, 'execute')
    )
    from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'calculate_ungani_subscription_amount'
  ),
  'confirmation_email_overload_count', (
    select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'queue_ungani_payment_confirmation_email'
  ),
  'calc_amount_overload_count', (
    select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'calculate_ungani_subscription_amount'
  ),
  'set_period_overload_count', (
    select count(*) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public' and p.proname = 'set_ungani_subscription_period_from_payment'
  ),
  'new_columns_count', (
    select count(*) from information_schema.columns
    where table_schema = 'public' and (
      (table_name = 'ungani_subscriptions' and column_name in (
        'period_amount_due_ksh', 'period_amount_paid_ksh', 'credit_balance_ksh', 'period_package_key',
        'pending_downgrade_package_key', 'pending_downgrade_requested_at'
      ))
      or (table_name = 'ungani_payments' and column_name in ('applied_to_subscription_at', 'source'))
    )
  ),
  'new_tables_count', (
    select count(*) from information_schema.tables
    where table_schema = 'public' and table_name in ('ungani_payment_processing_failures', 'ungani_payment_duplicate_flags')
  )
) as verification_result;
