-- Adds forward-looking subscription-period tracking for PAYING tenants
-- (trial tenants already have trial_end_at) and the function that keeps
-- it current whenever a payment is confirmed paid through any of the
-- three admin "mark paid" paths (see sql/fix-payment-confirmation-gap-
-- all-paths.sql, which calls this).
--
-- Design: a payment resets the clock. subscription_ends_at is set to
-- (paid_at + 1 month, or + 1 year if tenants.billing_cycle = 'yearly'),
-- starting fresh from the payment date rather than stacking on top of
-- any existing value - this app has no evidence of automatic recurring
-- billing, so each payment is treated as a discrete top-up, matching
-- how admin already manually flips a tenant to 'active' on payment
-- today.
--
-- This column is the single new piece of schema api/check-trial-
-- warnings.js needs to run the same 7-day/2-3-day/ended/grace-period
-- cadence for paying tenants that trial_end_at already gets. Run this
-- file once in the Supabase SQL editor.

alter table public.ungani_subscriptions
  add column if not exists subscription_ends_at timestamptz;

comment on column public.ungani_subscriptions.subscription_ends_at is 'Forward-looking end of the CURRENT PAID period for a non-trial tenant - set/refreshed by set_ungani_subscription_period_from_payment() whenever a payment is confirmed paid. Null for tenants who have never had a payment go through the unified confirmation flow. Distinct from trial_end_at, which only applies while subscription_status = ''trial''.';

create or replace function public.set_ungani_subscription_period_from_payment(p_payment_id uuid)
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_payment public.ungani_payments;
  v_billing_cycle text;
  v_period_end timestamptz;
begin
  select * into v_payment from public.ungani_payments where id = p_payment_id;

  if v_payment.id is null or v_payment.payment_status <> 'paid' then
    return;
  end if;

  select coalesce(billing_cycle, 'monthly') into v_billing_cycle
  from public.tenants
  where id = v_payment.tenant_id;

  v_period_end := coalesce(v_payment.paid_at, now()) +
    case when v_billing_cycle = 'yearly' then interval '1 year' else interval '1 month' end;

  insert into public.ungani_subscriptions (
    tenant_id,
    package_key,
    subscription_status,
    payment_status,
    subscription_ends_at,
    updated_at
  )
  values (
    v_payment.tenant_id,
    coalesce(v_payment.package_key, 'starter'),
    'active',
    'paid',
    v_period_end,
    now()
  )
  on conflict (tenant_id) do update set
    package_key = coalesce(excluded.package_key, public.ungani_subscriptions.package_key),
    subscription_status = 'active',
    payment_status = 'paid',
    subscription_ends_at = excluded.subscription_ends_at,
    updated_at = now();
exception
  when others then
    raise warning 'Could not update subscription period for payment %: %', p_payment_id, sqlerrm;
end;
$function$;

-- No grant to `authenticated` - same reasoning as queue_ungani_payment_
-- confirmation_email in sql/fix-payment-confirmation-gap-all-paths.sql:
-- internal helper, only ever called from inside already admin-gated
-- SECURITY DEFINER functions.
