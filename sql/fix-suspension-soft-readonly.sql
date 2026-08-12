-- Softens 'suspended'/'cancelled'/'canceled' from a hard lockout (full
-- page replaced with "Workspace Access Restricted", only
-- my-account-status.html reachable) to the same read-only treatment
-- trial-expiry already gets (full viewing, no create/edit/delete) -
-- matches the intended business behavior: don't lock a lapsed customer
-- out of their own data, just stop them from changing it until they pay.
--
-- 'blocked' and 'restricted' are left untouched - still a genuine hard
-- lock (abuse/policy-level restriction, not a billing-lapse state).
--
-- Why this alone is sufficient, no JS changes needed: client-access-
-- guard.js's allow-check is
--   `if (access.can_access === true || allowedStatuses.includes(status))`
-- - an OR with can_access checked first. Returning can_access: true for
-- these 3 statuses bypasses the hard-lock branch entirely regardless of
-- what access_status string comes back. The actual write-blocking is
-- already handled correctly, unconditionally, by the SEPARATE
-- get_my_ungani_subscription_access()/get_my_ungani_read_only_notice()
-- pair (can_write=false for these exact same 3 statuses, confirmed
-- already correct in the pulled source - not touched here).
--
-- Reproduced verbatim from the real, current source (pulled directly,
-- not guessed) except the one if-block being split in two.

create or replace function public.get_ungani_tenant_access_status(p_tenant_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_sub record;
  v_subscription_status text;
  v_payment_status text;
  v_trial_end_at timestamptz;
begin
  if p_tenant_id is null then
    return jsonb_build_object(
      'ok', false,
      'can_access', false,
      'access_status', 'restricted',
      'status', 'restricted',
      'message', 'Tenant ID is required.'
    );
  end if;
  select *
  into v_sub
  from public.ungani_subscriptions
  where tenant_id = p_tenant_id
  order by created_at desc
  limit 1;
  if v_sub is null then
    return jsonb_build_object(
      'ok', true,
      'can_access', true,
      'access_status', 'warning',
      'status', 'warning',
      'message', 'No subscription found, but access is allowed for now.'
    );
  end if;
  v_subscription_status := lower(trim(coalesce(v_sub.subscription_status, 'trial')));
  v_payment_status := lower(trim(coalesce(v_sub.payment_status, 'pending')));
  v_trial_end_at := v_sub.trial_end_at;
  if v_subscription_status in ('blocked', 'restricted') then
    return jsonb_build_object(
      'ok', true,
      'can_access', false,
      'access_status', v_subscription_status,
      'status', v_subscription_status,
      'subscription_status', v_subscription_status,
      'payment_status', v_payment_status,
      'trial_end_at', v_trial_end_at,
      'message', 'Workspace access is restricted.'
    );
  end if;
  -- NEW: a lapsed/suspended/cancelled billing status is a read-only
  -- state, not a lockout - can_access stays true (write-blocking is
  -- handled separately, correctly, by the subscription-access RPC pair).
  if v_subscription_status in ('suspended', 'cancelled', 'canceled') then
    return jsonb_build_object(
      'ok', true,
      'can_access', true,
      'access_status', 'restricted_readonly',
      'status', 'restricted_readonly',
      'subscription_status', v_subscription_status,
      'payment_status', v_payment_status,
      'trial_end_at', v_trial_end_at,
      'message', 'Your subscription is ' || v_subscription_status || '. You can view your data, but adding, editing, or deleting is turned off until this is resolved.'
    );
  end if;
  if v_subscription_status = 'trial' then
    return jsonb_build_object(
      'ok', true,
      'can_access', true,
      'access_status', 'trial',
      'status', 'trial',
      'subscription_status', v_subscription_status,
      'payment_status', v_payment_status,
      'trial_end_at', v_trial_end_at,
      'message', 'Trial account access allowed.'
    );
  end if;
  if v_subscription_status in ('active', 'approved', 'enabled') then
    return jsonb_build_object(
      'ok', true,
      'can_access', true,
      'access_status', 'active',
      'status', 'active',
      'subscription_status', v_subscription_status,
      'payment_status', v_payment_status,
      'trial_end_at', v_trial_end_at,
      'message', 'Workspace access allowed.'
    );
  end if;
  if v_payment_status in ('pending', 'partial', 'overdue') then
    return jsonb_build_object(
      'ok', true,
      'can_access', true,
      'access_status', 'payment_warning',
      'status', 'payment_warning',
      'subscription_status', v_subscription_status,
      'payment_status', v_payment_status,
      'trial_end_at', v_trial_end_at,
      'message', 'Payment warning. Access allowed.'
    );
  end if;
  return jsonb_build_object(
    'ok', true,
    'can_access', true,
    'access_status', coalesce(v_subscription_status, 'allowed'),
    'status', coalesce(v_subscription_status, 'allowed'),
    'subscription_status', v_subscription_status,
    'payment_status', v_payment_status,
    'trial_end_at', v_trial_end_at,
    'message', 'Workspace access allowed.'
  );
end;
$function$;

-- Verify the redefinition landed and reads back as expected.
select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'get_ungani_tenant_access_status';
