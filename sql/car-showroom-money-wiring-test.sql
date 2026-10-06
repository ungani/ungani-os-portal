-- Proof for Car Showroom Money wiring: trade-in nets into total_amount
-- but is never counted as cash received; vehicle costs ride on
-- transactions.related_item_id (no new ledger, no double-counting);
-- instalment "Owed to you" is just total_amount - amount_paid, already
-- correct with zero new code. Rolled back entirely.

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
  v_trade_in_id uuid;
  v_sale_result jsonb;
  v_invoice_id uuid;
  v_total_amount numeric;
  v_amount_paid numeric;
  v_trade_in_value numeric;
  v_payment_result jsonb;
  v_current_status text;
  v_quantity numeric;
  v_cash_tx_amount numeric;
  v_cost_tx_count int;
  v_owed numeric;
begin
  select id into v_owner_id from auth.users where lower(email) = 'ungani0722@gmail.com' limit 1;

  if v_owner_id is null then
    raise exception 'Could not find Billy Logistics owner - aborting test.';
  end if;

  insert into tenants (company_name, business_name, name, slug, is_test, business_type_key, account_status, status, stock_tracking_enabled)
  values ('TEST SHOWROOM (money wiring check)', 'TEST SHOWROOM (money wiring check)', 'TEST SHOWROOM (money wiring check)',
          'test-showroom-money-' || substr(gen_random_uuid()::text, 1, 8), true, 'car_showroom', 'trial', 'trial', false)
  returning id into v_test_tenant;

  update registrations
  set tenant_id = v_test_tenant
  where auth_user_id = v_owner_id
     or lower(coalesce(contact_email, email, '')) = lower((select email from auth.users where id = v_owner_id));

  update users set tenant_id = v_test_tenant where id = v_owner_id;

  perform set_config('request.jwt.claims', json_build_object('sub', v_owner_id::text, 'role', 'authenticated')::text, true);

  insert into business_items (tenant_id, item_name, business_type_key, vin_number, condition_type, ownership_type, current_status, quantity, selling_price)
  values (v_test_tenant, 'TEST Toyota Prado (money check)', 'car_showroom', 'TESTVIN0002MONEY', 'used', 'own_stock', 'available', 1, 1000000)
  returning id into v_vehicle_id;

  -------------------------------------------------------------------
  -- 1: sale with a trade-in - total nets correctly, amount_paid is
  -- ZERO (trade-in is not cash), vehicle marked Sold immediately.
  -------------------------------------------------------------------
  insert into business_items (tenant_id, item_name, business_type_key, vin_number, condition_type, ownership_type, current_status, quantity, selling_price)
  values (v_test_tenant, 'TEST Customer Trade-in Honda Fit', 'car_showroom', 'TESTVIN0003TRADEIN', 'used', 'own_stock', 'available', 1, 0)
  returning id into v_trade_in_id;

  begin
    v_sale_result := owner_create_ungani_vehicle_sale(v_vehicle_id, 'TEST Customer', null, null, v_trade_in_id, 200000, 'Trade-in deal');

    insert into test_results (scenario, expected, actual, status) values (
      '1. sale with trade-in succeeds',
      'ok=true',
      'ok=' || (v_sale_result->>'ok') || ', message=' || coalesce(v_sale_result->>'message', 'none'),
      case when (v_sale_result->>'ok')::boolean = true then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('1. sale with trade-in', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  v_invoice_id := (v_sale_result->>'invoice_id')::uuid;

  select total_amount, amount_paid, trade_in_value into v_total_amount, v_amount_paid, v_trade_in_value
  from ungani_customer_invoices where id = v_invoice_id;

  insert into test_results (scenario, expected, actual, status) values (
    '2. total_amount nets the trade-in (1,000,000 - 200,000 = 800,000), amount_paid is 0',
    'total=800000, amount_paid=0, trade_in_value=200000',
    'total=' || v_total_amount || ', amount_paid=' || v_amount_paid || ', trade_in_value=' || v_trade_in_value,
    case when v_total_amount = 800000 and v_amount_paid = 0 and v_trade_in_value = 200000 then 'PASS' else 'FAIL' end
  );

  select current_status, quantity into v_current_status, v_quantity from business_items where id = v_vehicle_id;

  insert into test_results (scenario, expected, actual, status) values (
    '3. vehicle marked Sold immediately at sale agreement (not deferred to payment)',
    'current_status=sold, quantity=0',
    'current_status=' || v_current_status || ', quantity=' || v_quantity,
    case when v_current_status = 'sold' and v_quantity = 0 then 'PASS' else 'FAIL' end
  );

  -------------------------------------------------------------------
  -- 4: a real cash payment for the full remaining balance (800,000) -
  -- amount_paid and the resulting transactions row must show 800,000,
  -- NEVER the 1,000,000 full price or the 200,000 trade-in value.
  -------------------------------------------------------------------
  begin
    v_payment_result := record_ungani_invoice_payment(v_invoice_id, 800000, current_date, 'cash', 'TEST-CASH-1', 'Full cash balance');

    insert into test_results (scenario, expected, actual, status) values (
      '4. full cash payment recorded, invoice flips to paid',
      'ok=true, amount_paid=800000, status=paid',
      'ok=' || (v_payment_result->>'ok') || ', amount_paid=' || (v_payment_result->>'amount_paid') || ', status=' || (v_payment_result->>'status'),
      case when (v_payment_result->>'ok')::boolean = true and (v_payment_result->>'amount_paid')::numeric = 800000 and v_payment_result->>'status' = 'paid' then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('4. cash payment', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  select amount into v_cash_tx_amount
  from transactions
  where related_invoice_id = v_invoice_id and transaction_type = 'income'
  order by created_at desc limit 1;

  insert into test_results (scenario, expected, actual, status) values (
    '5. the Money transaction created equals cash received only (800,000), never 1,000,000 or 200,000',
    '800000',
    coalesce(v_cash_tx_amount::text, 'NULL - no transaction found'),
    case when v_cash_tx_amount = 800000 then 'PASS' else 'FAIL' end
  );

  -------------------------------------------------------------------
  -- 6: vehicle costs ride on transactions.related_item_id - no new
  -- table, shows in Money, usable for profit-per-car with zero
  -- double-counting risk (same ledger Money already reconciles).
  -------------------------------------------------------------------
  insert into transactions (tenant_id, transaction_type, amount, currency, amount_kes, category, description, related_item_id, transaction_date)
  values (v_test_tenant, 'expense', 45000, 'KES', 45000, 'Vehicle Duty', 'Import duty for TEST Toyota Prado', v_vehicle_id, current_date);

  insert into transactions (tenant_id, transaction_type, amount, currency, amount_kes, category, description, related_item_id, transaction_date)
  values (v_test_tenant, 'expense', 15000, 'KES', 15000, 'Vehicle Repairs', 'Pre-sale repairs for TEST Toyota Prado', v_vehicle_id, current_date);

  select count(*) into v_cost_tx_count from transactions where related_item_id = v_vehicle_id and transaction_type = 'expense';

  insert into test_results (scenario, expected, actual, status) values (
    '6. vehicle costs recorded as expense transactions linked via related_item_id',
    'count=2 (duty + repairs)',
    'count=' || v_cost_tx_count,
    case when v_cost_tx_count = 2 then 'PASS' else 'FAIL' end
  );

  -------------------------------------------------------------------
  -- 7: a SECOND sale, this time instalment (no trade-in) - car marked
  -- Sold at agreement, partial payment leaves a correct "Owed to you".
  -------------------------------------------------------------------
  declare
    v_vehicle2_id uuid;
    v_sale2_result jsonb;
    v_invoice2_id uuid;
  begin
    insert into business_items (tenant_id, item_name, business_type_key, vin_number, condition_type, ownership_type, current_status, quantity, selling_price)
    values (v_test_tenant, 'TEST Nissan X-Trail (instalment check)', 'car_showroom', 'TESTVIN0004INSTALMENT', 'used', 'own_stock', 'available', 1, 1500000)
    returning id into v_vehicle2_id;

    v_sale2_result := owner_create_ungani_vehicle_sale(v_vehicle2_id, 'TEST Instalment Customer', null, null, null, null, 'Instalment deal');
    v_invoice2_id := (v_sale2_result->>'invoice_id')::uuid;

    perform record_ungani_invoice_payment(v_invoice2_id, 500000, current_date, 'mpesa', 'TEST-DEPOSIT-1', 'Deposit');

    select (total_amount - amount_paid) into v_owed from ungani_customer_invoices where id = v_invoice2_id;
    select current_status into v_current_status from business_items where id = v_vehicle2_id;

    insert into test_results (scenario, expected, actual, status) values (
      '7. instalment sale: car Sold at agreement, deposit recorded, Owed to you = 1,000,000',
      'current_status=sold, owed=1000000',
      'current_status=' || v_current_status || ', owed=' || v_owed,
      case when v_current_status = 'sold' and v_owed = 1000000 then 'PASS' else 'FAIL' end
    );
  end;

  -------------------------------------------------------------------
  -- 8: guardrails - trade-in >= sale price is rejected; re-selling an
  -- already-sold vehicle is rejected.
  -------------------------------------------------------------------
  begin
    v_sale_result := owner_create_ungani_vehicle_sale(v_vehicle_id, 'TEST Customer', null, null, v_trade_in_id, 2000000, 'Bad trade-in');

    insert into test_results (scenario, expected, actual, status) values (
      '8. trade-in value >= sale price is rejected',
      'ok=false',
      'ok=' || (v_sale_result->>'ok') || ', message=' || coalesce(v_sale_result->>'message', 'none'),
      case when (v_sale_result->>'ok')::boolean = false then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('8. bad trade-in rejected', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  begin
    v_sale_result := owner_create_ungani_vehicle_sale(v_vehicle_id, 'TEST Another Customer', null, 900000, null, null, 'Re-selling an already-sold car');

    insert into test_results (scenario, expected, actual, status) values (
      '9. re-selling an already-sold vehicle is rejected',
      'ok=false',
      'ok=' || (v_sale_result->>'ok') || ', message=' || coalesce(v_sale_result->>'message', 'none'),
      case when (v_sale_result->>'ok')::boolean = false then 'PASS' else 'FAIL' end
    );
  exception when others then
    insert into test_results (scenario, expected, actual, status) values ('9. re-sell rejected', 'no error', 'ERROR: ' || sqlerrm, 'FAIL');
  end;

  perform set_config('request.jwt.claims', '', true);
end;
$test$;

select scenario, expected, actual, status from test_results order by seq;

rollback;
