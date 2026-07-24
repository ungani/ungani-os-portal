-- Live read/write check for tenant_integrations, run after confirming
-- the grants fix (sql/fix-tenant-integrations-missing-grants.sql). I
-- have no live authenticated session on production, so this is the most
-- rigorous check possible without one: impersonate a real authenticated
-- user exactly as PostgREST does for a real browser request, then run
-- the exact statement shapes my-integrations.html sends. Everything is
-- wrapped in a transaction that ends in ROLLBACK, so nothing is left
-- behind in real data either way.
--
-- This tests the database layer for real (RLS + grants + constraints) -
-- the one thing it does NOT cover is the actual browser/JS flow, which
-- was already covered separately via mocked Playwright tests before
-- shipping. Together these two forms of testing are full coverage short
-- of an actual logged-in click-through.

-- STEP 1 (read-only) - find a real tenant + user to impersonate. The
-- users table has no auth_user_id/user_id column (confirmed live) -
-- get_my_ungani_tenant_id()'s real source (confirmed live) checks
-- `u.id = v_user_id or u.auth_user_id = v_user_id or lower(email) = ...`,
-- so users.id itself IS the auth.uid() value for the normal case. Pick
-- any row from the result and use its tenant_id / user_id in Step 2.
select t.id as tenant_id, t.business_name, t.business_type_key, u.id as user_id, u.email
from tenants t
join users u on u.tenant_id = t.id
order by t.created_at desc
limit 5;

-- STEP 2 - replace both <TENANT_ID> and <USER_ID> below with values from
-- Step 1's result (same tenant_id used for both occurrences), then run
-- this whole block together.
--
-- All three steps run as ONE statement (a WITH chain), so their combined
-- output is one query result with visible rows - no reliance on a
-- Messages/Logs panel. The `disconnected` CTE below matches on
-- `id = (select id from upserted)` rather than re-querying
-- tenant_id/integration_type - that's a genuine data dependency, which
-- forces Postgres to evaluate `upserted` first and hand its actual
-- returned row to `disconnected`, sidestepping the usual caveat that
-- writable CTEs in one WITH clause don't reliably see each other's
-- effects (they only don't when there's no such dependency).
--
-- ROLLBACK still comes after, as its own statement, so nothing persists
-- either way - if your editor happens to only display the very last
-- statement's result and this still shows "no rows", tell me and I'll
-- restructure again (e.g. two separate runs: one that does the test and
-- shows results, a second you run immediately after to manually restore
-- via the row this query's output gives you).

begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "<USER_ID>", "role": "authenticated"}';

with
  pre_check as (
    -- exactly what loadIntegrations() runs on page load
    select count(*) as existing_row_count
    from tenant_integrations
    where tenant_id = '<TENANT_ID>'
  ),
  upserted as (
    -- exactly what the connect wizard's wizardConfirm() runs
    insert into tenant_integrations (tenant_id, integration_type, provider_name, status, config)
    values ('<TENANT_ID>', 'gps', 'SQL Live-Check Test Provider', 'connected', '{}'::jsonb)
    on conflict (tenant_id, integration_type) do update set provider_name = excluded.provider_name
    returning id, provider_name, status
  ),
  disconnected as (
    -- exactly what disconnectIntegration() runs, matched directly
    -- against upserted's own returned id (the data dependency that
    -- forces correct sequencing)
    update tenant_integrations
    set status = 'disconnected', disconnected_at = now()
    where id = (select id from upserted)
    returning id, provider_name, status, disconnected_at
  )
select '1_pre_check' as step, existing_row_count::text as provider_name, null::text as status, null::text as disconnected_at
from pre_check
union all
select '2_insert_upsert' as step, provider_name, status, null::text as disconnected_at
from upserted
union all
select '3_disconnect_update' as step, provider_name, status, disconnected_at::text
from disconnected
order by step;

rollback; -- undoes the insert/update above - this was a read/write test only.

-- Expected: 3 rows. Row 1 (1_pre_check) shows the existing count before
-- the test (any number, including 0, is fine). Row 2
-- (2_insert_upsert) shows status=connected. Row 3
-- (3_disconnect_update) shows status=disconnected with a non-null
-- disconnected_at. If row 3 is missing entirely, that means the UPDATE
-- matched zero rows - a real bug. If any row is missing due to a
-- permission error instead, that error message itself is the finding.
