-- Read-only. Confirming the real cause of the 500 in
-- admin_update_ungani_subscription: an explicit `is_active = true` check
-- on p_package_key that runs on every call, unrelated to the subscription/
-- payment status being updated.

-- STEP 1: is "starter" (the value admin-profiles.html's fallback always
-- sends) actually active? If false, that's the exception firing.
select package_key, package_name, is_active
from public.ungani_packages
order by sort_order;

-- STEP 2: what is THIS tenant's real current package_key on the tenants
-- table? If it's something other than "starter" (e.g. "growth"), that
-- means admin-profiles.html's fallback is overwriting the tenant's real,
-- possibly-active package with the wrong, possibly-inactive default -
-- a bug in my code, not the RPC. If it's genuinely null/empty, the RPC's
-- design (blocking ANY status update when the current package is
-- inactive, even if the package itself isn't being changed) is the real
-- problem to fix.
select id, business_name, package_key, subscription_status, payment_status
from public.tenants
where id = 'a29af055-e4f0-48cf-af97-f99081a9106b';
