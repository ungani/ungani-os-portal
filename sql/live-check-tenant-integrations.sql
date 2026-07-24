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
-- Uses a DO block with RAISE NOTICE for each step's outcome rather than
-- three separate result grids, for two reasons: (1) Supabase's SQL
-- editor typically only displays the LAST statement's result grid, so
-- three separate top-level statements make the first two invisible -
-- RAISE NOTICE output all shows up together in the Messages panel
-- regardless. (2) plain sequential PL/pgSQL statements guarantee the
-- UPDATE actually sees the INSERT's row within the same transaction -
-- three separate writable CTEs would NOT be guaranteed to (CTEs in one
-- WITH clause share a single snapshot, they don't see each other's
-- effects unless explicitly chained).

begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "<USER_ID>", "role": "authenticated"}';

do $$
declare
  v_select_count int;
  v_insert_row record;
  v_update_row record;
begin
  -- exactly what loadIntegrations() runs on page load
  select count(*) into v_select_count
  from tenant_integrations
  where tenant_id = '<TENANT_ID>';

  raise notice 'SELECT: % existing row(s) for this tenant', v_select_count;

  -- exactly what the connect wizard's wizardConfirm() runs
  insert into tenant_integrations (tenant_id, integration_type, provider_name, status, config)
  values ('<TENANT_ID>', 'gps', 'SQL Live-Check Test Provider', 'connected', '{}'::jsonb)
  on conflict (tenant_id, integration_type) do update set provider_name = excluded.provider_name
  returning * into v_insert_row;

  raise notice 'INSERT/UPSERT: id=%, provider_name=%, status=%', v_insert_row.id, v_insert_row.provider_name, v_insert_row.status;

  -- exactly what disconnectIntegration() runs
  update tenant_integrations
  set status = 'disconnected', disconnected_at = now()
  where tenant_id = '<TENANT_ID>' and integration_type = 'gps'
  returning * into v_update_row;

  if v_update_row is null then
    raise notice 'UPDATE: no row matched - this would be a real bug (the INSERT above should have made this row visible to the UPDATE)';
  else
    raise notice 'UPDATE: id=%, provider_name=%, status=%, disconnected_at=%', v_update_row.id, v_update_row.provider_name, v_update_row.status, v_update_row.disconnected_at;
  end if;
end $$;

rollback; -- undoes the insert/update above - this was a read/write test only.

-- Expected: three NOTICE lines in the Messages panel - SELECT (any
-- count, zero is fine), INSERT/UPSERT with status=connected, UPDATE
-- with status=disconnected and a non-null disconnected_at. No
-- permission-denied errors anywhere. If any step errors or the UPDATE
-- notice says "no row matched", that's the real bug to report back.
