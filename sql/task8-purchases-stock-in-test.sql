-- =====================================================================
-- Task 8 Purchase/Stock-in - scenario test script. Run AFTER
-- sql/task8-purchases-stock-in.sql has been applied.
--
-- Same pattern as sql/item1-subscription-billing-test.sql and
-- sql/invoice-stock-deduction-test.sql: everything happens inside
-- BEGIN ... ROLLBACK, nothing is kept. Uses the REAL Billy Logistics
-- tenant (ungani0722@gmail.com), throwaway test business_items and
-- purchases - all undone by the final ROLLBACK.
--
-- Covers: draft created -> stock untouched; draft -> received -> stock
-- up + payable transaction created; received again -> still once
-- (idempotent); received -> cancelled -> stock reversed + transaction
-- soft-deleted; service line (no item_id) -> no stock change; draft ->
-- cancelled directly (never received) -> no stock or money effect.
-- =====================================================================

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
  v_tenant_id uuid;
  v_owner_id uuid;

  v_item_id uuid;
  v_qty numeric;

  v_purchase_id uuid;
  v_purchase_id_2 uuid;
  v_purchase_id_3 uuid;

  v_result jsonb;
  v_transaction_id uuid;
  v_transaction_count int;
  v_transaction_deleted_at timestamptz;
begin
  -------------------------------------------------------------------
  -- SETUP
  -------------------------------------------------------------------
  select id into v_owner_id from auth.users where lower(email) = 'ungani0722@gmail.com' limit 1;

  if v_owner_id is null then
    raise exception 'Could not find Billy Logistics owner (ungani0722@gmail.com) in auth.users - aborting test.';
  end if;

  perform set_config('request.jwt.claims', json_build_object('sub', v_owner_id::text, 'role', 'authenticated')::text, true);

  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    raise exception 'Could not resolve a tenant_id for the Billy Logistics owner - aborting test.';
  end if;

  insert into public.business_items (tenant_id, item_name, quantity, item_status)
  values (v_tenant_id, 'TEST STOCK ITEM (purchase test)', 20, 'available')
  returning id into v_item_id;

  -------------------------------------------------------------------
  -- S0: draft purchase created -> stock untouched.
  -------------------------------------------------------------------
  begin
    v_result := public.owner_upsert_ungani_purchase(
      p_supplier_name := 'Test Supplier Ltd',
      p_items := jsonb_build_array(jsonb_build_object('description', 'Test stock line', 'quantity', 10, 'unit_cost', 50, 'item_id', v_item_id))
    );
    v_purchase_id := (v_result->>'purchase_id')::uuid;

    select quantity into v_qty from public.business_items where id = v_item_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S0 draft purchase created, stock untouched',
      'ok=true, quantity=20',
      'ok=' || (v_result->>'ok') || ', quantity=' || v_qty,
      case when (v_result->>'ok')::boolean = true and v_qty = 20 then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S0 draft purchase created', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S1 + S2: draft -> received -> stock up + payable transaction;
  -- received again -> still once (idempotent, no double transaction).
  -------------------------------------------------------------------
  begin
    v_result := public.update_ungani_purchase_status(v_purchase_id, 'received');
    select quantity into v_qty from public.business_items where id = v_item_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S1 purchase received -> stock up (20 -> 30)',
      'ok=true, quantity=30',
      'ok=' || (v_result->>'ok') || ', quantity=' || v_qty,
      case when (v_result->>'ok')::boolean = true and v_qty = 30 then 'PASS' else 'FAIL' end
    );

    select count(*) into v_transaction_count
    from public.transactions
    where related_purchase_id = v_purchase_id and deleted_at is null;

    select id into v_transaction_id
    from public.transactions
    where related_purchase_id = v_purchase_id and deleted_at is null
    order by created_at desc
    limit 1;

    insert into test_results (scenario, expected, actual, status) values (
      'S1b one payable expense transaction created for the total (500)',
      'count=1, amount=500',
      'count=' || v_transaction_count || ', amount=' || (select amount from public.transactions where id = v_transaction_id),
      case when v_transaction_count = 1 and (select amount from public.transactions where id = v_transaction_id) = 500 then 'PASS' else 'FAIL' end
    );

    -- Re-receive the same purchase (already 'received') - must not
    -- double the stock or create a second transaction.
    v_result := public.update_ungani_purchase_status(v_purchase_id, 'received');
    select quantity into v_qty from public.business_items where id = v_item_id;
    select count(*) into v_transaction_count from public.transactions where related_purchase_id = v_purchase_id and deleted_at is null;

    insert into test_results (scenario, expected, actual, status) values (
      'S2 purchase received again -> still 30, still 1 transaction',
      'ok=true, quantity=30, transaction_count=1',
      'ok=' || (v_result->>'ok') || ', quantity=' || v_qty || ', transaction_count=' || v_transaction_count,
      case when (v_result->>'ok')::boolean = true and v_qty = 30 and v_transaction_count = 1 then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S1/S2 receive + re-receive', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S3: received -> cancelled -> stock reversed, transaction soft-deleted.
  -------------------------------------------------------------------
  begin
    v_result := public.update_ungani_purchase_status(v_purchase_id, 'cancelled');
    select quantity into v_qty from public.business_items where id = v_item_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S3 received purchase cancelled -> stock reversed (30 -> 20)',
      'ok=true, quantity=20',
      'ok=' || (v_result->>'ok') || ', quantity=' || v_qty,
      case when (v_result->>'ok')::boolean = true and v_qty = 20 then 'PASS' else 'FAIL' end
    );

    select deleted_at into v_transaction_deleted_at from public.transactions where id = v_transaction_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S3b linked transaction soft-deleted on cancel',
      'deleted_at is not null',
      'deleted_at=' || coalesce(v_transaction_deleted_at::text, 'NULL'),
      case when v_transaction_deleted_at is not null then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S3 cancel reverses stock + transaction', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S4: service line (no item_id) -> received -> no stock change.
  -------------------------------------------------------------------
  begin
    v_result := public.owner_upsert_ungani_purchase(
      p_supplier_name := 'Test Supplier 2',
      p_items := jsonb_build_array(jsonb_build_object('description', 'Service line, no item', 'quantity', 1, 'unit_cost', 1000))
    );
    v_purchase_id_2 := (v_result->>'purchase_id')::uuid;

    v_result := public.update_ungani_purchase_status(v_purchase_id_2, 'received');
    select quantity into v_qty from public.business_items where id = v_item_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S4 service-line purchase received -> no stock change',
      'ok=true, quantity unchanged=20',
      'ok=' || (v_result->>'ok') || ', quantity=' || v_qty,
      case when (v_result->>'ok')::boolean = true and v_qty = 20 then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S4 service line', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S5: draft -> cancelled directly (never received) -> no stock or
  -- money effect at all.
  -------------------------------------------------------------------
  begin
    v_result := public.owner_upsert_ungani_purchase(
      p_supplier_name := 'Test Supplier 3',
      p_items := jsonb_build_array(jsonb_build_object('description', 'Never received', 'quantity', 5, 'unit_cost', 20, 'item_id', v_item_id))
    );
    v_purchase_id_3 := (v_result->>'purchase_id')::uuid;

    v_result := public.update_ungani_purchase_status(v_purchase_id_3, 'cancelled');
    select quantity into v_qty from public.business_items where id = v_item_id;
    select count(*) into v_transaction_count from public.transactions where related_purchase_id = v_purchase_id_3;

    insert into test_results (scenario, expected, actual, status) values (
      'S5 draft cancelled directly -> no stock or transaction effect',
      'ok=true, quantity=20, transaction_count=0',
      'ok=' || (v_result->>'ok') || ', quantity=' || v_qty || ', transaction_count=' || v_transaction_count,
      case when (v_result->>'ok')::boolean = true and v_qty = 20 and v_transaction_count = 0 then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S5 draft cancelled directly', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  perform set_config('request.jwt.claims', '', true);
end;
$test$;

select scenario, expected, actual, status from test_results order by seq;

rollback;
