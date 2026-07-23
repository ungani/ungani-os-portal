-- Read-only. Continuing the type-mismatch audit into `users`, `payments`,
-- and `upgrade_requests`.
--
-- users: every write path (account.html, admin-settings.html,
-- admin-shared.js's updateAdminPreferences, users.html) writes only
-- foundational, long-established fields - full_name, tenant_id, role,
-- status, preferred_theme/language/currency/timezone, updated_at. Lower
-- risk than the newer feature-specific columns that caused every real bug
-- found so far, but included for completeness.
--
-- payments: billing.html's updatePaymentStatus() writes status/updated_at,
-- with a defensive fallback that retries with just `status` alone if the
-- first update fails - written that way already, suggesting updated_at
-- may have been a problem on this table before. Worth confirming directly.
--
-- upgrade_requests vs ungani_upgrade_requests - REAL SPLIT-BRAIN SUSPECT:
-- billing.html (the page actually linked from the main admin sidebar's
-- "Billing" nav item) reads/writes a table called `upgrade_requests` (no
-- prefix), self-consistently. But the client-facing submission flow
-- (my-package.html -> RPC client_submit_ungani_upgrade_request) and the
-- dedicated admin-upgrade-requests.html page both consistently use
-- `ungani_upgrade_requests` (with prefix). These are either two genuinely
-- separate tables (meaning billing.html's admin view NEVER shows real
-- client-submitted upgrade requests - same shape as the payment-proofs
-- visibility bug, but worse since billing.html is the primary sidebar
-- page) or `upgrade_requests` no longer exists at all (billing.html's
-- queries would then silently return empty, which would explain nobody
-- noticing). The row counts below distinguish the two scenarios.

-- STEP 1: column existence/type check for users/payments/upgrade_requests.
select table_name, column_name, data_type, udt_name, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name in ('users', 'payments', 'upgrade_requests')
  and column_name in (
    -- users
    'full_name', 'tenant_id', 'role', 'status', 'preferred_theme',
    'preferred_language', 'preferred_currency', 'preferred_timezone',
    'updated_at',
    -- payments (status/updated_at already covered above for users;
    -- payments-specific columns only)
    'id',
    -- upgrade_requests
    'requested_package_key', 'current_package_key', 'reason'
  )
order by table_name, column_name;

-- STEP 2: direct existence/type check for the two columns billing.html's
-- fallback pattern suggests may have caused trouble before.
select table_name, column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name in ('payments', 'upgrade_requests')
  and column_name in ('status', 'updated_at')
order by table_name, column_name;

-- STEP 3: does `upgrade_requests` (no prefix) even exist as a table at
-- all, alongside `ungani_upgrade_requests`? Run this and read the result
-- BEFORE running step 4 - step 4 will error if either table is missing.
select table_name
from information_schema.tables
where table_schema = 'public'
  and table_name in ('upgrade_requests', 'ungani_upgrade_requests');

-- STEP 4: ONLY run this if step 3 confirmed BOTH table names exist - it
-- will error otherwise. Row counts settle whether upgrade_requests is a
-- real, separate, currently-in-use table or genuinely dead/empty.
select 'upgrade_requests' as table_name, count(*) from public.upgrade_requests
union all
select 'ungani_upgrade_requests' as table_name, count(*) from public.ungani_upgrade_requests;
