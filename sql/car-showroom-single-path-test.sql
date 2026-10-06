-- Proof that marking a car Sold has exactly ONE path:
-- owner_set_ungani_vehicle_status() - and that sync_ungani_invoice_stock
-- (the generic invoice-stock-sync path) never touches a car's quantity
-- even when an invoice line references the car's item_id directly,
-- because a Car Showroom tenant never has stock_tracking_enabled = true.
--
-- Rolled back entirely - no test rows persist, and the owner's real
-- users.tenant_id is restored by the rollback too.

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
  v_test_tenant uuid;
  v_vehicle_id uuid;
  v_invoice_id uuid;
  v_result jsonb;
  v_quantity numeric;
  v_current_status text;
  v_movement_count int;
begin
  select id into v_owner_id from auth.users where lower(email) = 'ungani0722@gmail.com' limit 1;

  if v_owner_id is null then
    raise exception 'Could not find Billy Logistics owner - aborting test.';
  end if;

  insert into tenants (company_name, business_name, name, slug, is_test, business_type_key, account_status, status, stock_tracking_enabled)
  values ('TEST SHOWROOM (single-path check)', 'TEST SHOWROOM (single-path check)', 'TEST SHOWROOM (single-path check)',
          'test-showroom-single-path-' || substr(gen_random_uuid()::text, 1, 8), true, 'car_showroom', 'trial', 'trial', false)
  returning id into v_test_tenant;

  insert into business_items (tenant_id, item_name, business_type_key, vin_number, condition_type, ownership_type, current_status, quantity, selling_price)
  values (v_test_tenant, 'TEST Toyota Axio (single-path check)', 'car_showroom', 'TESTVIN0001SINGLEPATH', 'used', 'own_stock', 'available', 1, 800000)
  returning id into v_vehicle_id;

  -- Rebind this real owner's tenant context to the test tenant for the
  -- duration of this transaction only - rolled back at the end along
  -- with everything else. get_my_ungani_tenant_id() resolves from
  -- registrations.tenant_id FIRST (matched by auth_user_id/email),
  -- only falling back to users.tenant_id if that misses - Billy's owner
  -- has an approved registration pointing at his real tenant, so both
  -- must be repointed for the resolver to actually return the test
  -- tenant instead.
  update registrations
  set tenant_id = v_test_tenant
  where auth_user_id = v_owner_id
     or lower(coalesce(contact_email, email, '')) = lower((select email from auth.users where id = v_owner_id));

  update users set tenant_id = v_test_tenant where id = v_owner_id;

  insert into test_results (scenario, expected, actual, status) values (
    '0. tenant stock_tracking_enabled is false (never turned on)',
    'false',
    (select coalesce(stock_tracking_enabled, false)::text from tenants where id = v_test_tenant),
    case when (select coalesce(stock_tracking_enabled, false) from tenants where id = v_test_tenant) = false then 'PASS' else 'FAIL' end
  );

  perform set_config('request.jwt.claims', json_build_object('sub', v_owner_id::text, 'role', 'authenticated')::text, true);

  insert into ungani_customer_invoices (tenant_id, invoice_number, customer_name, issue_date, subtotal, vat_amount, total_amount, status)
  values (v_test_tenant, 'TEST-SHOWROOM-INV-1', 'TEST Customer', current_date, 800000, 0, 800000, 'draft')
  returning id into v_invoice_id;

  insert into ungani_customer_invoice_items (invoice_id, tenant_id, description, quantity, unit_price, line_subtotal, item_id)
  values (v_invoice_id, v_test_tenant, 'TEST Toyota Axio (single-path check)', 1, 800000, 800000, v_vehicle_id);

  -------------------------------------------------------------------
  -- 1: an invoice line referencing the car's item_id moves the
  -- invoice to 'sent' - sync_ungani_invoice_stock must be a no-op.
  -------------------------------------------------------------------
  begin
    v_result := sync_ungani_invoice_stock(v_invoice_id, 'sent', 'draft');
    select quantity into v_quantity from business_items where id = v_vehicle_id;

    insert into test_results (scenario, expected, actual, status) values (
      '1. invoice-stock sync is a no-op for a non-tracking showroom tenant',
      'ok=true, message mentions Stock Tracking off, vehicle quantity unchanged (1)',
      'ok=' || (v_result->>'ok') || ', message=' || coalesce(v_result->>'message', 'none') || ', quantity=' || v_quantity,
      case when (v_result->>'ok')::boolean = true and v_result->>'message' ilike '%stock tracking is off%' and v_quantity = 1 then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('1. invoice-stock sync no-op', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- 2: zero rows were ever written to ungani_stock_movements for
  -- this vehicle - confirms adjust_ungani_stock was never reached.
  -------------------------------------------------------------------
  select count(*) into v_movement_count from ungani_stock_movements where item_id = v_vehicle_id;

  insert into test_results (scenario, expected, actual, status) values (
    '2. zero stock_movements rows ever created for this vehicle',
    'count=0',
    'count=' || v_movement_count,
    case when v_movement_count = 0 then 'PASS' else 'FAIL' end
  );

  -------------------------------------------------------------------
  -- 3: the ONE real path - owner_set_ungani_vehicle_status - marks
  -- the car Sold (quantity -> 0).
  -------------------------------------------------------------------
  begin
    v_result := owner_set_ungani_vehicle_status(v_vehicle_id, 'sold');
    select quantity, current_status into v_quantity, v_current_status from business_items where id = v_vehicle_id;

    insert into test_results (scenario, expected, actual, status) values (
      '3. owner_set_ungani_vehicle_status marks the car Sold',
      'ok=true, quantity=0, current_status=sold',
      'ok=' || (v_result->>'ok') || ', quantity=' || v_quantity || ', status=' || v_current_status,
      case when (v_result->>'ok')::boolean = true and v_quantity = 0 and v_current_status = 'sold' then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('3. mark sold', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- 4: calling it AGAIN with the same status is a provable no-op
  -- (idempotent by construction - sets an absolute state, not a delta).
  -------------------------------------------------------------------
  begin
    v_result := owner_set_ungani_vehicle_status(v_vehicle_id, 'sold');
    select quantity, current_status into v_quantity, v_current_status from business_items where id = v_vehicle_id;

    insert into test_results (scenario, expected, actual, status) values (
      '4. calling Sold again is idempotent (no double movement)',
      'ok=true, quantity still=0, current_status still=sold',
      'ok=' || (v_result->>'ok') || ', quantity=' || v_quantity || ', status=' || v_current_status,
      case when (v_result->>'ok')::boolean = true and v_quantity = 0 and v_current_status = 'sold' then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('4. idempotent re-call', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- 5: zero stock_movements rows STILL exist after 2 status calls -
  -- this RPC never touches that ledger at all, by design.
  -------------------------------------------------------------------
  select count(*) into v_movement_count from ungani_stock_movements where item_id = v_vehicle_id;

  insert into test_results (scenario, expected, actual, status) values (
    '5. still zero stock_movements rows after 2 status calls',
    'count=0',
    'count=' || v_movement_count,
    case when v_movement_count = 0 then 'PASS' else 'FAIL' end
  );

  -------------------------------------------------------------------
  -- 6: cancelling a sale/reservation returns it to Available.
  -------------------------------------------------------------------
  begin
    v_result := owner_set_ungani_vehicle_status(v_vehicle_id, 'available');
    select quantity, current_status into v_quantity, v_current_status from business_items where id = v_vehicle_id;

    insert into test_results (scenario, expected, actual, status) values (
      '6. cancelling a sale returns the car to Available',
      'ok=true, quantity=1, current_status=available',
      'ok=' || (v_result->>'ok') || ', quantity=' || v_quantity || ', status=' || v_current_status,
      case when (v_result->>'ok')::boolean = true and v_quantity = 1 and v_current_status = 'available' then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('6. cancel-sale to available', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- 7: an invalid status is rejected (allow-list isn't wide open).
  -------------------------------------------------------------------
  begin
    v_result := owner_set_ungani_vehicle_status(v_vehicle_id, 'not_a_real_status');

    insert into test_results (scenario, expected, actual, status) values (
      '7. invalid status still rejected',
      'ok=false',
      'ok=' || (v_result->>'ok') || ', message=' || coalesce(v_result->>'message', 'none'),
      case when (v_result->>'ok')::boolean = false then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('7. invalid status rejected', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  perform set_config('request.jwt.claims', '', true);
end;
$test$;

select scenario, expected, actual, status from test_results order by seq;

rollback;
