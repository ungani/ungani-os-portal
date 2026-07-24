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

-- STEP 1 (read-only) - find a real tenant + linked auth user to
-- impersonate. Pick any row from the result and use its tenant_id /
-- auth_user_id in Step 2 below.
select t.id as tenant_id, t.business_name, t.business_type_key, u.auth_user_id, u.email
from tenants t
join users u on u.tenant_id = t.id
where u.auth_user_id is not null
order by t.created_at desc
limit 5;

-- STEP 2 - replace both <TENANT_ID> and <AUTH_USER_ID> below with values
-- from Step 1's result (same tenant_id used for both occurrences), then
-- run this whole block together.

begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "<AUTH_USER_ID>", "role": "authenticated"}';

-- 2a. SELECT - exactly what loadIntegrations() runs on page load.
select * from tenant_integrations where tenant_id = '<TENANT_ID>';

-- 2b. INSERT/UPSERT - exactly what the connect wizard's wizardConfirm()
--     runs when a client finishes the 3-step flow.
insert into tenant_integrations (tenant_id, integration_type, provider_name, status, config)
values ('<TENANT_ID>', 'gps', 'SQL Live-Check Test Provider', 'connected', '{}'::jsonb)
on conflict (tenant_id, integration_type) do update set provider_name = excluded.provider_name
returning *;

-- 2c. UPDATE - exactly what disconnectIntegration() runs.
update tenant_integrations
set status = 'disconnected', disconnected_at = now()
where tenant_id = '<TENANT_ID>' and integration_type = 'gps'
returning *;

rollback; -- undoes 2a-2c above - this was a read/write test only.

-- Expected outcome: 2a returns rows (or zero rows if this tenant has
-- never connected anything - not an error either way), 2b returns the
-- one inserted/updated row with provider_name = 'SQL Live-Check Test
-- Provider', 2c returns that same row with status = 'disconnected'. No
-- permission-denied errors anywhere. If any step errors, that's the
-- real bug to report back - not a false positive from this being a
-- test, since ROLLBACK only undoes data changes, not query results.
