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
-- A prior version of this file chained pre_check/upserted/disconnected
-- as three CTEs in one WITH clause, matching the UPDATE on
-- `id = (select id from upserted)` to try to force correct sequencing.
-- That doesn't actually work - confirmed live (the UPDATE matched zero
-- rows). Per Postgres's documented behavior, ALL writable CTEs in one
-- WITH clause share the single snapshot taken at the start of the
-- query - RETURNING is the only channel between them, so `disconnected`
-- had the right id value to look for, but its own UPDATE still scanned
-- the table as it looked BEFORE `upserted`'s insert, where that row
-- didn't exist yet. There's no way to fix this within one statement.
--
-- This version uses a DO block instead, where each statement is
-- genuinely sequential (not snapshot-shared) and correctly sees the
-- prior statement's write. Results are captured into a temp table and
-- surfaced via a plain SELECT as visible rows - confirmed live that a
-- row-returning SELECT followed by ROLLBACK still displays correctly in
-- your editor (the previous run showed rows 1 and 2 this same way).

begin;

set local role authenticated;
set local request.jwt.claims = '{"sub": "<USER_ID>", "role": "authenticated"}';

create temporary table _live_check_results (
  step text,
  provider_name text,
  status text,
  disconnected_at text
) on commit drop;

do $$
declare
  v_existing_count int;
  v_insert_row record;
  v_update_row record;
begin
  -- 1. exactly what loadIntegrations() runs on page load
  select count(*) into v_existing_count
  from tenant_integrations
  where tenant_id = '<TENANT_ID>';

  insert into _live_check_results values ('1_pre_check', v_existing_count::text, null, null);

  -- 2. exactly what the connect wizard's wizardConfirm() runs
  insert into tenant_integrations (tenant_id, integration_type, provider_name, status, config)
  values ('<TENANT_ID>', 'gps', 'SQL Live-Check Test Provider', 'connected', '{}'::jsonb)
  on conflict (tenant_id, integration_type) do update set provider_name = excluded.provider_name
  returning id, provider_name, status into v_insert_row;

  insert into _live_check_results values ('2_insert_upsert', v_insert_row.provider_name, v_insert_row.status, null);

  -- 3. exactly what disconnectIntegration() runs - a genuinely separate
  --    sequential statement, so it correctly sees step 2's write (this
  --    is the part the CTE version couldn't do).
  update tenant_integrations
  set status = 'disconnected', disconnected_at = now()
  where id = v_insert_row.id
  returning id, provider_name, status, disconnected_at::text into v_update_row;

  if v_update_row is null then
    insert into _live_check_results values ('3_disconnect_update', 'NO ROW MATCHED', 'ERROR', null);
  else
    insert into _live_check_results values ('3_disconnect_update', v_update_row.provider_name, v_update_row.status, v_update_row.disconnected_at);
  end if;
end $$;

select * from _live_check_results order by step;

rollback; -- undoes the insert/update (and the temp table) above - this was a read/write test only.

-- Expected: 3 rows. Row 1 (1_pre_check) shows the existing count before
-- the test (any number, including 0, is fine). Row 2
-- (2_insert_upsert) shows status=connected. Row 3
-- (3_disconnect_update) shows status=disconnected with a non-null
-- disconnected_at. If row 3 says "NO ROW MATCHED", that's now a real
-- bug worth reporting (this version removes the snapshot issue that
-- caused the previous false negative). If any row is missing due to a
-- permission error instead, that error message itself is the finding.
