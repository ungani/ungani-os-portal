-- =====================================================================
-- Invoice stock-deduction - scenario test script. Run AFTER
-- sql/invoice-stock-deduction.sql has been applied.
--
-- Same pattern as sql/item1-subscription-billing-test.sql: everything
-- happens inside BEGIN ... ROLLBACK, nothing is kept. Uses the REAL
-- Billy Logistics tenant (ungani0722@gmail.com), a throwaway test
-- business_item, throwaway test invoices/orders - all undone by the
-- final ROLLBACK. Billy's real stock_tracking_enabled flag is forced to
-- true for the duration (restored by the rollback, not a real change).
--
-- Covers the 5 scenarios for invoice stock deduction: sent once ->
-- deducted once; sent twice -> still once; cancelled -> restored;
-- service line -> no stock change; order converted then fulfilled -> no
-- double deduction. (Purchase/Stock-in scenarios are a separate test
-- file, added when that feature is built - item 8 in the approved
-- order, not yet started.)
--
-- One honest caveat before you run this: scenario 5's setup inserts
-- directly into ungani_orders/ungani_order_items. I only have CONFIRMED
-- LIVE column names for the specific columns convert_ungani_order_to_
-- invoice's body actually reads (tenant_id, order_number, customer_
-- name/address/contact, delivery_address/date, payment_terms/details,
-- vat_applicable/rate/pricing_mode, discount_amount, subtotal/vat_
-- amount/total_amount, currency, status, notes, customer_person_id,
-- converted_invoice_id) - NOT the full column list `my-orders.html`'s
-- own create path might set. If scenario 5 errors with a column-name
-- mismatch, the "actual" column below will show the exact Postgres
-- error - paste that back and I'll fix the test (not the migration)
-- without guessing.
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

  v_invoice_id uuid;
  v_invoice_id_2 uuid;
  v_order_id uuid;
  v_order_item_id uuid;
  v_conv_invoice_id uuid;

  v_result jsonb;
  v_linked_lines_on_converted int;
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

  update public.tenants set stock_tracking_enabled = true where id = v_tenant_id;

  insert into public.business_items (tenant_id, item_name, quantity, item_status)
  values (v_tenant_id, 'TEST STOCK ITEM (invoice deduction test)', 50, 'available')
  returning id into v_item_id;

  -------------------------------------------------------------------
  -- S1 + S2: sent once -> deducted once; sent twice -> still once.
  -------------------------------------------------------------------
  begin
    v_result := public.owner_upsert_ungani_customer_invoice(
      p_customer_name := 'Test Customer',
      p_items := jsonb_build_array(jsonb_build_object('description', 'Test stock line', 'quantity', 5, 'unit_price', 100, 'item_id', v_item_id))
    );
    v_invoice_id := (v_result->>'invoice_id')::uuid;

    select quantity into v_qty from public.business_items where id = v_item_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S0 draft invoice created, stock untouched',
      'invoice created ok, quantity=50',
      'ok=' || (v_result->>'ok') || ', quantity=' || v_qty,
      case when (v_result->>'ok')::boolean = true and v_qty = 50 then 'PASS' else 'FAIL' end
    );

    v_result := public.update_ungani_invoice_status(v_invoice_id, 'sent');
    select quantity into v_qty from public.business_items where id = v_item_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S1 invoice sent -> deducted once (50 -> 45)',
      'ok=true, quantity=45',
      'ok=' || (v_result->>'ok') || ', quantity=' || v_qty,
      case when (v_result->>'ok')::boolean = true and v_qty = 45 then 'PASS' else 'FAIL' end
    );

    -- Re-send the same invoice (already 'sent') - must not deduct again.
    v_result := public.update_ungani_invoice_status(v_invoice_id, 'sent');
    select quantity into v_qty from public.business_items where id = v_item_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S2 invoice sent again -> still 45, not 40',
      'ok=true, quantity=45',
      'ok=' || (v_result->>'ok') || ', quantity=' || v_qty,
      case when (v_result->>'ok')::boolean = true and v_qty = 45 then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S1/S2 send + resend', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S3: cancelled -> restored.
  -------------------------------------------------------------------
  begin
    v_result := public.update_ungani_invoice_status(v_invoice_id, 'cancelled');
    select quantity into v_qty from public.business_items where id = v_item_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S3 sent invoice cancelled -> restored (45 -> 50)',
      'ok=true, quantity=50',
      'ok=' || (v_result->>'ok') || ', quantity=' || v_qty,
      case when (v_result->>'ok')::boolean = true and v_qty = 50 then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S3 cancel restores stock', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S4: service line (no item_id) -> no stock change.
  -------------------------------------------------------------------
  begin
    v_result := public.owner_upsert_ungani_customer_invoice(
      p_customer_name := 'Test Customer 2',
      p_items := jsonb_build_array(jsonb_build_object('description', 'Service line, no item', 'quantity', 1, 'unit_price', 1000))
    );
    v_invoice_id_2 := (v_result->>'invoice_id')::uuid;

    v_result := public.update_ungani_invoice_status(v_invoice_id_2, 'sent');
    select quantity into v_qty from public.business_items where id = v_item_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S4 service-line invoice sent -> no stock change',
      'ok=true, quantity unchanged=50',
      'ok=' || (v_result->>'ok') || ', quantity=' || v_qty,
      case when (v_result->>'ok')::boolean = true and v_qty = 50 then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S4 service line', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  -------------------------------------------------------------------
  -- S5: order converted then fulfilled -> no double deduction.
  -------------------------------------------------------------------
  begin
    insert into public.ungani_orders (
      tenant_id, order_number, customer_name, status, subtotal, vat_amount, total_amount, currency
    ) values (
      v_tenant_id, 'TEST-ORD-' || gen_random_uuid(), 'Test Order Customer', 'confirmed', 300, 0, 300, 'KES'
    ) returning id into v_order_id;

    insert into public.ungani_order_items (
      tenant_id, order_id, item_id, description, quantity, unit_price, line_subtotal, sort_order
    ) values (
      v_tenant_id, v_order_id, v_item_id, 'Test order line', 3, 100, 300, 0
    ) returning id into v_order_item_id;

    v_result := public.fulfill_ungani_order_item(v_order_item_id, 3, 'TEST-FULFILL-' || gen_random_uuid()::text);
    select quantity into v_qty from public.business_items where id = v_item_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S5a order fulfilled -> deducted once (50 -> 47)',
      'ok=true, quantity=47',
      'ok=' || (v_result->>'ok') || ', quantity=' || v_qty,
      case when (v_result->>'ok')::boolean = true and v_qty = 47 then 'PASS' else 'FAIL' end
    );

    v_result := public.convert_ungani_order_to_invoice(v_order_id);
    v_conv_invoice_id := (v_result->>'invoice_id')::uuid;

    select count(*) into v_linked_lines_on_converted
    from public.ungani_customer_invoice_items
    where invoice_id = v_conv_invoice_id and item_id is not null;

    insert into test_results (scenario, expected, actual, status) values (
      'S5b converted invoice lines carry no item_id (by design)',
      'ok=true, item_id-linked line count=0',
      'ok=' || (v_result->>'ok') || ', item_id-linked line count=' || v_linked_lines_on_converted,
      case when (v_result->>'ok')::boolean = true and v_linked_lines_on_converted = 0 then 'PASS' else 'FAIL' end
    );

    v_result := public.update_ungani_invoice_status(v_conv_invoice_id, 'sent');
    select quantity into v_qty from public.business_items where id = v_item_id;

    insert into test_results (scenario, expected, actual, status) values (
      'S5c converted invoice sent -> no double deduction (still 47)',
      'ok=true, quantity=47',
      'ok=' || (v_result->>'ok') || ', quantity=' || v_qty,
      case when (v_result->>'ok')::boolean = true and v_qty = 47 then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('S5 order->invoice no double deduction', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  perform set_config('request.jwt.claims', '', true);
end;
$test$;

select scenario, expected, actual, status from test_results order by seq;

rollback;
