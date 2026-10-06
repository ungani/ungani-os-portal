-- Rolled-back proof for the commitments "generic" type fix. Covers:
-- regression (the 3 original types still work), the new "generic" type
-- now succeeds (covers all 15 of 19 business types that weren't
-- Real Estate/Gym/Security/Cleaning), and a truly invalid type is still
-- rejected (allow-list isn't wide open).

begin;

create temp table test_results (
  seq int generated always as identity,
  scenario text,
  expected text,
  actual text,
  status text
) on commit drop;

do $test$
declare
  v_owner_id uuid;
  v_result jsonb;
  v_commitment_id uuid;
begin
  select id into v_owner_id from auth.users where lower(email) = 'ungani0722@gmail.com' limit 1;

  if v_owner_id is null then
    raise exception 'Could not find Billy Logistics owner - aborting test.';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_owner_id::text, 'role', 'authenticated')::text, true);

  -------------------------------------------------------------------
  -- 1-3: regression - the 3 original types still work.
  -------------------------------------------------------------------
  begin
    v_result := public.owner_upsert_ungani_commitment(p_commitment_type := 'lease', p_plan_name := 'TEST lease regression', p_start_date := current_date);
    insert into test_results (scenario, expected, actual, status) values (
      '1. lease type still works (regression)', 'ok=true',
      'ok=' || (v_result->>'ok'),
      case when (v_result->>'ok')::boolean = true then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('1. lease regression', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  begin
    v_result := public.owner_upsert_ungani_commitment(p_commitment_type := 'membership', p_plan_name := 'TEST membership regression', p_start_date := current_date);
    insert into test_results (scenario, expected, actual, status) values (
      '2. membership type still works (regression)', 'ok=true',
      'ok=' || (v_result->>'ok'),
      case when (v_result->>'ok')::boolean = true then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('2. membership regression', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  begin
    v_result := public.owner_upsert_ungani_commitment(p_commitment_type := 'service_contract', p_plan_name := 'TEST service_contract regression', p_start_date := current_date);
    insert into test_results (scenario, expected, actual, status) values (
      '3. service_contract type still works (regression)', 'ok=true',
      'ok=' || (v_result->>'ok'),
      case when (v_result->>'ok')::boolean = true then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('3. service_contract regression', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- 4: the actual bug - "generic" now works (this is the exact save
  -- Billy Logistics' owner hit in the live Playwright test that failed
  -- with "A valid commitment type is required.").
  -------------------------------------------------------------------
  begin
    v_result := public.owner_upsert_ungani_commitment(p_commitment_type := 'generic', p_plan_name := 'TEST generic type (was: A valid commitment type is required)', p_start_date := current_date);
    v_commitment_id := (v_result->>'commitment_id')::uuid;

    insert into test_results (scenario, expected, actual, status) values (
      '4. generic type now works (was the live bug)', 'ok=true, id returned',
      'ok=' || (v_result->>'ok') || ', id=' || coalesce(v_commitment_id::text, 'NULL'),
      case when (v_result->>'ok')::boolean = true and v_commitment_id is not null then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('4. generic type works', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- 5: a truly invalid type is still rejected (allow-list isn't wide open).
  -------------------------------------------------------------------
  begin
    v_result := public.owner_upsert_ungani_commitment(p_commitment_type := 'not_a_real_type', p_plan_name := 'TEST invalid type', p_start_date := current_date);

    insert into test_results (scenario, expected, actual, status) values (
      '5. invalid type still rejected', 'ok=false',
      'ok=' || (v_result->>'ok') || ', message=' || coalesce(v_result->>'message', 'none'),
      case when (v_result->>'ok')::boolean = false then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('5. invalid type rejected', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- 6: generic commitment soft-deletes cleanly too (reuses the earlier
  -- allowlist fix - confirms the two fixes compose correctly together).
  -------------------------------------------------------------------
  begin
    v_result := public.soft_delete_ungani_record('ungani_commitments', v_commitment_id, 'Test cleanup');

    insert into test_results (scenario, expected, actual, status) values (
      '6. generic commitment soft-deletes cleanly', 'ok=true',
      'ok=' || (v_result->>'ok'),
      case when (v_result->>'ok')::boolean = true then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('6. generic commitment soft-delete', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  perform set_config('request.jwt.claims', '', true);
end;
$test$;

select scenario, expected, actual, status from test_results order by seq;

rollback;
