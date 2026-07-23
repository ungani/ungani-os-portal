-- Read-only. Tracing the real 500 error from admin_update_ungani_subscription
-- (called from admin-profiles.html's Active/Trial/Suspend buttons).
--
-- Working theory: admin-profiles.html's fallback chain assumed
-- tenants.package_key / tenants.payment_status / tenants.trial_end_at
-- exist (copying admin-subscriptions.html's `sub.x || tenant.x` code
-- pattern) but this was never actually confirmed against the real schema -
-- exactly the "code consistency isn't proof" trap this audit exists to
-- catch. If these don't exist, every call falls through to hardcoded
-- defaults (p_package_key: "starter", p_trial_end_at: null) regardless of
-- the tenant's real state, which may be exactly what the RPC chokes on.

-- STEP 1: do these fallback columns actually exist on tenants?
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'tenants'
  and column_name in (
    'package_key', 'payment_status', 'subscription_status',
    'trial_start_at', 'trial_end_at', 'notes'
  )
order by column_name;

-- STEP 2: is "starter" a real, valid package_key in the catalog the RPC
-- likely validates against? If admin-profiles.html's fallback sent
-- "starter" and it's not in this list, that's a strong candidate for the
-- 500 (invalid value where a real package_key was expected).
select package_key, package_name
from public.ungani_packages
order by sort_order;

-- STEP 3: explains the 403 - what RLS policies exist on ungani_subscriptions,
-- and for which roles. Confirms (doesn't fix) that direct client-side
-- SELECT from the admin dashboard's role isn't granted, only via RPC.
select schemaname, tablename, policyname, roles, cmd, qual
from pg_policies
where schemaname = 'public'
  and tablename = 'ungani_subscriptions';
