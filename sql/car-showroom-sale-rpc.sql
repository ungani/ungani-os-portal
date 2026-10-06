-- owner_create_ungani_vehicle_sale() - the Sales entry point for Car
-- Showroom. Does NOT touch or duplicate owner_upsert_ungani_customer_invoice()
-- (used by all 19 business types) - it calls that function unmodified,
-- passing trade_in_value through its EXISTING discount_amount parameter
-- (which already nets straight into total_amount, before any payment is
-- ever recorded), then separately stamps the two new audit-only columns
-- (trade_in_item_id/trade_in_value) so reports can tell a trade-in apart
-- from a genuine discount. amount_paid is never touched here - it is
-- only ever incremented by the existing, separate payment-recording RPC,
-- so trade-in value can never be miscounted as cash received.
--
-- Marks the car Sold immediately on sale creation (cash OR instalment -
-- per spec, "car is Sold at agreement"), via the one real status path
-- (owner_set_ungani_vehicle_status) - not a parallel write to
-- business_items. "Owed to you" for an instalment sale needs no new
-- code: it is already total_amount - amount_paid on the invoice, which
-- Debtors/Payables already surfaces for every business type.

begin;

CREATE OR REPLACE FUNCTION public.owner_create_ungani_vehicle_sale(
  p_vehicle_item_id uuid,
  p_customer_name text,
  p_customer_person_id uuid DEFAULT NULL::uuid,
  p_sale_price numeric DEFAULT NULL::numeric,
  p_trade_in_item_id uuid DEFAULT NULL::uuid,
  p_trade_in_value numeric DEFAULT NULL::numeric,
  p_notes text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_vehicle record;
  v_trade_in_tenant_id uuid;
  v_sale_price numeric;
  v_invoice_result jsonb;
  v_invoice_id uuid;
  v_status_result jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select id, item_name, selling_price, current_status, business_type_key
  into v_vehicle
  from public.business_items
  where id = p_vehicle_item_id and tenant_id = v_tenant_id;

  if v_vehicle.id is null then
    return jsonb_build_object('ok', false, 'message', 'Vehicle not found in your workspace.');
  end if;

  if v_vehicle.business_type_key is distinct from 'car_showroom' then
    return jsonb_build_object('ok', false, 'message', 'This record is not a Car Showroom vehicle.');
  end if;

  if v_vehicle.current_status = 'sold' then
    return jsonb_build_object('ok', false, 'message', 'This vehicle is already marked Sold.');
  end if;

  v_sale_price := coalesce(p_sale_price, v_vehicle.selling_price);

  if v_sale_price is null or v_sale_price <= 0 then
    return jsonb_build_object('ok', false, 'message', 'A sale price is required.');
  end if;

  if p_trade_in_item_id is not null then
    if p_trade_in_value is null or p_trade_in_value <= 0 then
      return jsonb_build_object('ok', false, 'message', 'A trade-in value is required when a trade-in vehicle is selected.');
    end if;

    select tenant_id into v_trade_in_tenant_id
    from public.business_items
    where id = p_trade_in_item_id;

    if v_trade_in_tenant_id is null or v_trade_in_tenant_id <> v_tenant_id then
      return jsonb_build_object('ok', false, 'message', 'Trade-in vehicle not found in your workspace.');
    end if;

    if p_trade_in_value >= v_sale_price then
      return jsonb_build_object('ok', false, 'message', 'Trade-in value cannot be greater than or equal to the sale price.');
    end if;
  end if;

  v_invoice_result := public.owner_upsert_ungani_customer_invoice(
    p_customer_person_id := p_customer_person_id,
    p_customer_name := p_customer_name,
    p_discount_amount := coalesce(p_trade_in_value, 0),
    p_notes := p_notes,
    p_items := jsonb_build_array(
      jsonb_build_object(
        'item_id', p_vehicle_item_id,
        'description', v_vehicle.item_name,
        'quantity', 1,
        'unit_price', v_sale_price
      )
    )
  );

  if coalesce((v_invoice_result->>'ok')::boolean, false) is not true then
    return v_invoice_result;
  end if;

  v_invoice_id := (v_invoice_result->>'invoice_id')::uuid;

  update public.ungani_customer_invoices
  set trade_in_item_id = p_trade_in_item_id,
      trade_in_value = p_trade_in_value
  where id = v_invoice_id and tenant_id = v_tenant_id;

  v_status_result := public.owner_set_ungani_vehicle_status(p_vehicle_item_id, 'sold');

  if coalesce((v_status_result->>'ok')::boolean, false) is not true then
    return jsonb_build_object('ok', false, 'message', 'Invoice created but could not mark the vehicle Sold: ' || coalesce(v_status_result->>'message', 'unknown error'));
  end if;

  return jsonb_build_object('ok', true, 'invoice_id', v_invoice_id, 'vehicle_item_id', p_vehicle_item_id, 'message', 'Sale recorded.');
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.owner_create_ungani_vehicle_sale(
  uuid, text, uuid, numeric, uuid, numeric, text
) from public, anon;
grant execute on function public.owner_create_ungani_vehicle_sale(
  uuid, text, uuid, numeric, uuid, numeric, text
) to authenticated;

commit;
