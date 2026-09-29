-- =====================================================================
-- Stock atomicity/idempotency Phase 2 (RUN AND VERIFIED LIVE): makes
-- p_sale_id and p_fulfillment_event_id required (drops their defaults)
-- now that the live JS (my-quick-sale.html, my-orders.html) always sends
-- both. See sql/stock-atomicity-and-idempotency-fix.sql for Phase 1 and
-- the full history of corrections that led to this design.
--
-- Only change from the live Phase 1 versions:
--   1. p_sale_id / p_fulfillment_event_id no longer have a default -
--      they are now required arguments.
--   2. The v_has_sale_id / v_has_event_id booleans and their "if v_has_x
--      then ... end if;" guards are removed - the code they guarded now
--      always runs unconditionally.
--   3. record_ungani_pos_sale's parameter order changes: p_sale_id moves
--      to the 2nd position (right after p_customer_name) because
--      PostgreSQL requires every parameter after one with a default to
--      also have a default. p_customer_person_id / p_payment_method /
--      p_items keep their existing defaults in the same relative order.
--      This is invisible to the caller because my-quick-sale.html calls
--      the RPC with named parameters, not positional ones.
--   4. fulfill_ungani_order_item's parameter order is unchanged -
--      p_fulfillment_event_id was already last with nothing after it.
--
-- Everything else - permission checks, the atomic UPDATE guards, the
-- claim-first insert order, the replay/unique_violation handling, the
-- exception-based rollback behavior, and the final result-backfill
-- UPDATE - is copied verbatim from the live Phase 1 definitions.
--
-- Verification (run by Chris): all overload counts = 1, anon_exec =
-- false for both, authenticated_exec = true for both, neither parameter
-- has a default, defaults_count = 3 for record_ungani_pos_sale and 0 for
-- fulfill_ungani_order_item. Post-Phase-2 regression suite (concurrent
-- last unit, repeated sale id, double-click fulfil, partial fulfilments
-- + over-fulfil rejection, same item on two lines) all passed, plus
-- confirmed omitting either id now fails loudly (no fallback overload).
-- =====================================================================

-- ---------------------------------------------------------------------
-- record_ungani_pos_sale
-- ---------------------------------------------------------------------

drop function if exists public.record_ungani_pos_sale(text, uuid, text, jsonb, text);

create or replace function public.record_ungani_pos_sale(
  p_customer_name text,
  p_sale_id text,
  p_customer_person_id uuid default null::uuid,
  p_payment_method text default 'cash'::text,
  p_items jsonb default '[]'::jsonb
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_package_key text;
  v_pos_included boolean;
  v_pos_enabled boolean;
  v_stock_tracking_enabled boolean;
  v_payment_method text;
  v_invoice_result jsonb;
  v_invoice_id uuid;
  v_invoice_number text;
  v_total_amount numeric;
  v_item jsonb;
  v_line_index int;
  v_stock_result jsonb;
  v_result jsonb;
  v_existing_result jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.can_write_ungani_client_data() then
    return jsonb_build_object('ok', false, 'message', 'This account is currently read-only.');
  end if;

  if not public.ungani_staff_can('money', 'create') then
    return jsonb_build_object('ok', false, 'message', 'You do not have permission to record sales.');
  end if;

  -- Claimed FIRST, before any other validation or the invoice is
  -- created, so a retry with the same sale id never creates a second
  -- invoice.
  begin
    insert into public.ungani_pos_sale_events (tenant_id, sale_id)
    values (v_tenant_id, p_sale_id);
  exception
    when unique_violation then
      select result into v_existing_result
      from public.ungani_pos_sale_events
      where tenant_id = v_tenant_id and sale_id = p_sale_id;

      if v_existing_result is null then
        return jsonb_build_object('ok', false, 'message', 'This sale is already being processed - please check Money in a moment.');
      end if;

      return v_existing_result || jsonb_build_object('replay', true);
  end;

  select stock_tracking_enabled, pos_enabled
  into v_stock_tracking_enabled, v_pos_enabled
  from public.tenants
  where id = v_tenant_id;

  if coalesce(v_pos_enabled, false) is not true then
    raise exception 'Point of Sale is not turned on for this business. Enable it in Settings.';
  end if;

  select package_key into v_package_key
  from public.ungani_subscriptions
  where tenant_id = v_tenant_id;

  select coalesce(p.pos_included, false) into v_pos_included
  from public.ungani_packages p
  where p.package_key = v_package_key;

  if coalesce(v_pos_included, false) is not true then
    raise exception 'Your package does not include Point of Sale. Upgrade to Business or Custom to use Quick Sale.';
  end if;

  v_payment_method := lower(trim(coalesce(p_payment_method, 'cash')));
  if v_payment_method not in ('cash', 'mpesa', 'mpesa_manual') then
    raise exception 'Invalid payment method.';
  end if;

  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
    raise exception 'Add at least one item to the sale.';
  end if;

  -- Raising here (rather than returning v_invoice_result directly) rolls
  -- back the sale-id claim above too, so a corrected retry isn't
  -- permanently blocked by a failed attempt.
  v_invoice_result := public.owner_upsert_ungani_customer_invoice(
    p_customer_name := p_customer_name,
    p_customer_person_id := p_customer_person_id,
    p_items := p_items
  );

  if coalesce((v_invoice_result->>'ok')::boolean, false) is not true then
    raise exception '%', coalesce(v_invoice_result->>'message', 'Could not create invoice.');
  end if;

  v_invoice_id := (v_invoice_result->>'invoice_id')::uuid;

  select invoice_number, total_amount into v_invoice_number, v_total_amount
  from public.ungani_customer_invoices
  where id = v_invoice_id;

  if v_payment_method in ('cash', 'mpesa_manual') then
    -- source_reference is computed directly from p_sale_id and this
    -- loop's own index - no invoice-line lookup needed at all.
    for v_item, v_line_index in
      select value, (ordinality - 1)::int
      from jsonb_array_elements(p_items) with ordinality as t(value, ordinality)
    loop
      if v_item->>'item_id' is not null and coalesce(v_stock_tracking_enabled, false) then
        v_stock_result := public.adjust_ungani_stock(
          (v_item->>'item_id')::uuid,
          'sale',
          -coalesce((v_item->>'quantity')::numeric, 1),
          'POS sale: ' || v_invoice_number,
          null,
          p_sale_id || ':' || v_line_index
        );

        if coalesce((v_stock_result->>'ok')::boolean, false) is not true then
          raise exception '%', coalesce(v_stock_result->>'message', 'Could not adjust stock.');
        end if;
      end if;
    end loop;

    perform public.record_ungani_invoice_payment(
      p_invoice_id := v_invoice_id,
      p_amount := v_total_amount,
      p_method := case when v_payment_method = 'mpesa_manual' then 'M-Pesa' else 'cash' end,
      p_notes := case when v_payment_method = 'mpesa_manual' then 'Quick Sale - customer paid M-Pesa directly' else 'Quick Sale' end
    );

    v_result := jsonb_build_object(
      'ok', true, 'invoice_id', v_invoice_id, 'invoice_number', v_invoice_number,
      'total_amount', v_total_amount, 'status', 'paid', 'payment_method', v_payment_method
    );
  else
    v_result := jsonb_build_object(
      'ok', true, 'invoice_id', v_invoice_id, 'invoice_number', v_invoice_number,
      'total_amount', v_total_amount, 'status', 'draft', 'payment_method', 'mpesa'
    );
  end if;

  -- Fill in the real outcome (and invoice_id) on the claim row so a later
  -- replay - after this call has already committed - returns the true
  -- original result instead of a placeholder.
  update public.ungani_pos_sale_events
  set invoice_id = v_invoice_id, result = v_result
  where tenant_id = v_tenant_id and sale_id = p_sale_id;

  return v_result;
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.record_ungani_pos_sale(text, text, uuid, text, jsonb) from public, anon;
grant execute on function public.record_ungani_pos_sale(text, text, uuid, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- fulfill_ungani_order_item
-- ---------------------------------------------------------------------

drop function if exists public.fulfill_ungani_order_item(uuid, numeric);
drop function if exists public.fulfill_ungani_order_item(uuid, numeric, text);

create or replace function public.fulfill_ungani_order_item(
  p_order_item_id uuid,
  p_fulfill_quantity numeric,
  p_fulfillment_event_id text
)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_stock_tracking_enabled boolean;
  v_line record;
  v_new_fulfilled numeric;
  v_stock_result jsonb;
  v_total_ordered numeric;
  v_total_fulfilled numeric;
  v_new_order_status text;
  v_result jsonb;
  v_existing_result jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.ungani_staff_can('money', 'edit') then
    return jsonb_build_object('ok', false, 'message', 'You do not have permission to fulfil orders.');
  end if;

  if not public.can_write_ungani_client_data() then
    return jsonb_build_object('ok', false, 'message', 'This account is currently read-only.');
  end if;

  if p_fulfill_quantity is null or p_fulfill_quantity <= 0 then
    return jsonb_build_object('ok', false, 'message', 'Fulfil quantity must be greater than zero.');
  end if;

  select oi.id, oi.order_id, oi.item_id, oi.quantity, o.status, o.order_number
  into v_line
  from public.ungani_order_items oi
  join public.ungani_orders o on o.id = oi.order_id
  where oi.id = p_order_item_id and oi.tenant_id = v_tenant_id;

  if v_line.id is null then
    return jsonb_build_object('ok', false, 'message', 'Order line not found.');
  end if;

  if v_line.status not in ('confirmed', 'partially_fulfilled') then
    return jsonb_build_object('ok', false, 'message', 'This order must be confirmed before it can be fulfilled.');
  end if;

  -- Claimed FIRST, before fulfilled_quantity changes at all, so every
  -- fulfilment is protected regardless of whether the line has a linked
  -- item or Stock Tracking is on.
  insert into public.ungani_order_fulfillment_events (
    tenant_id, order_item_id, fulfillment_event_id, fulfill_quantity
  )
  values (
    v_tenant_id, p_order_item_id, p_fulfillment_event_id, p_fulfill_quantity
  );

  -- Single atomic statement - no prior SELECT of fulfilled_quantity, so
  -- two concurrent fulfil calls on the same line can never both compute
  -- from the same stale value. The WHERE clause makes exceeding the
  -- ordered quantity structurally impossible: a row that would exceed it
  -- doesn't match, so this affects zero rows and the exception below
  -- fires instead of ever writing an over-fulfilled value.
  -- coalesce(fulfilled_quantity, 0) treats a never-initialized value as 0
  -- rather than failing on NULL.
  update public.ungani_order_items
  set fulfilled_quantity = coalesce(fulfilled_quantity, 0) + p_fulfill_quantity
  where id = p_order_item_id
    and tenant_id = v_tenant_id
    and coalesce(fulfilled_quantity, 0) + p_fulfill_quantity <= quantity
  returning fulfilled_quantity
  into v_new_fulfilled;

  if not found then
    -- Raising here (rather than a manual compensating update) rolls back
    -- the fulfilment-event claim above automatically, so a corrected
    -- retry under the same event id is never permanently blocked.
    raise exception 'That would fulfil more than was ordered on this line.';
  end if;

  select stock_tracking_enabled into v_stock_tracking_enabled
  from public.tenants where id = v_tenant_id;

  if v_line.item_id is not null and coalesce(v_stock_tracking_enabled, false) then
    v_stock_result := public.adjust_ungani_stock(
      v_line.item_id, 'sale', -p_fulfill_quantity, 'Order fulfillment: ' || v_line.order_number,
      null, 'fulfil:' || p_fulfillment_event_id
    );

    if coalesce((v_stock_result->>'ok')::boolean, false) is not true then
      -- Raising here rolls back both the fulfilled_quantity update above
      -- and the fulfilment-event claim, in one automatic step.
      raise exception '%', coalesce(v_stock_result->>'message', 'Could not adjust stock.');
    end if;
  end if;

  select coalesce(sum(quantity), 0), coalesce(sum(fulfilled_quantity), 0)
  into v_total_ordered, v_total_fulfilled
  from public.ungani_order_items
  where order_id = v_line.order_id;

  v_new_order_status := case
    when v_total_fulfilled >= v_total_ordered then 'fulfilled'
    when v_total_fulfilled > 0 then 'partially_fulfilled'
    else v_line.status
  end;

  update public.ungani_orders
  set status = v_new_order_status, updated_at = now()
  where id = v_line.order_id;

  v_result := jsonb_build_object(
    'ok', true,
    'fulfilled_quantity', v_new_fulfilled,
    'order_status', v_new_order_status
  );

  -- Fill in the real outcome on the claim row so a later replay (after
  -- this call has already committed) returns the true original result
  -- instead of a placeholder.
  update public.ungani_order_fulfillment_events
  set result = v_result
  where tenant_id = v_tenant_id and fulfillment_event_id = p_fulfillment_event_id;

  return v_result;
exception
  when unique_violation then
    -- The fulfilment-event insert lost a race (or this is a plain retry)
    -- - nothing else in this call has touched real data yet, since the
    -- claim is the very first write. Return the original outcome instead
    -- of re-applying.
    select result into v_existing_result
    from public.ungani_order_fulfillment_events
    where tenant_id = v_tenant_id and fulfillment_event_id = p_fulfillment_event_id;

    if v_existing_result is null then
      -- The original call claimed the id but hasn't finished yet (a true
      -- millisecond-level race, not a simple double-click) - there is no
      -- recorded outcome to replay.
      return jsonb_build_object('ok', false, 'message', 'This fulfilment is already being processed - please check the order in a moment.');
    end if;

    return v_existing_result || jsonb_build_object('replay', true);
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.fulfill_ungani_order_item(uuid, numeric, text) from public, anon;
grant execute on function public.fulfill_ungani_order_item(uuid, numeric, text) to authenticated;
