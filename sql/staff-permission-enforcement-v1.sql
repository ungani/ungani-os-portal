-- Server-side staff-permission enforcement, v1.
--
-- Closes the gap found while building Approvals & Internal Controls:
-- ungani_staff_section_permissions was only ever enforced client-side
-- (UI hiding forms/buttons) for the transactions table's raw client
-- writes and for 12 write RPCs across Orders/Quotations/Invoices/Price
-- Lists/Stock - a direct call with a staff member's own valid session
-- token would bypass the UI restriction entirely. Everywhere else
-- (business_events, business_items, business_records, client_people,
-- documents, support_issues, tasks) already had real permission-aware
-- RLS via can_access_ungani_section()/can_write_ungani_client_section()
-- - confirmed via a live pg_policies pull, not assumed.
--
-- Orders/Quotations/Invoices/Price Lists were built after the 16-key
-- permission grid existed and have no dedicated section_key of their
-- own - mapped onto 'money' (the closest existing key) rather than
-- adding new ones, which would also require updating role presets and
-- the my-team-access.html permission-grid UI. adjust_ungani_stock maps
-- to 'items'.
--
-- fulfill_ungani_order_item calls adjust_ungani_stock internally when
-- stock tracking is on, so a staff member needs BOTH money/edit and
-- items/edit to fulfil orders in that case - a deliberate choice
-- (confirmed with the user) since fulfillment genuinely does mutate
-- stock, not an oversight.

create or replace function public.ungani_staff_can(p_section_key text, p_action text)
returns boolean
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_access jsonb;
begin
  v_access := public.get_my_ungani_staff_access();

  if v_access is null or coalesce((v_access->>'can_access')::boolean, false) = false then
    return false;
  end if;

  return coalesce(
    (v_access->'permissions'->lower(trim(p_section_key))->>p_action)::boolean,
    false
  );
end;
$function$;

grant execute on function public.ungani_staff_can(text, text) to authenticated;

-- transactions RLS fix. DELETE is already unconditionally blocked by
-- "ungani block direct delete transactions" (restrictive, qual=false) -
-- not touched here.
create policy transactions_permission_restrict_insert
on public.transactions
as restrictive
for insert
to authenticated
with check ( public.ungani_staff_can('money', 'create') );

create policy transactions_permission_restrict_update
on public.transactions
as restrictive
for update
to authenticated
using ( public.ungani_staff_can('money', 'edit') )
with check ( public.ungani_staff_can('money', 'edit') );

-- 1. adjust_ungani_stock - items / edit
CREATE OR REPLACE FUNCTION public.adjust_ungani_stock(p_item_id uuid, p_movement_type text, p_quantity_delta numeric, p_reason text DEFAULT NULL::text, p_reorder_level numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_item record;
  v_clean_type text;
  v_new_quantity numeric;
  v_new_reorder_level numeric;
  v_low_stock boolean;
  v_out_of_stock boolean;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.ungani_staff_can('items', 'edit') then
    return jsonb_build_object('ok', false, 'message', 'You do not have permission to adjust stock.');
  end if;

  if not public.can_write_ungani_client_data() then
    return jsonb_build_object('ok', false, 'message', 'This account is currently read-only.');
  end if;

  v_clean_type := lower(trim(coalesce(p_movement_type, '')));

  if v_clean_type not in ('restock', 'sale', 'adjustment', 'waste') then
    return jsonb_build_object('ok', false, 'message', 'Invalid movement type. Use restock, sale, adjustment, or waste.');
  end if;

  if p_quantity_delta is null or p_quantity_delta = 0 then
    return jsonb_build_object('ok', false, 'message', 'Quantity change must not be zero.');
  end if;

  select id, quantity, reorder_level into v_item
  from public.business_items
  where id = p_item_id and tenant_id = v_tenant_id;

  if v_item.id is null then
    return jsonb_build_object('ok', false, 'message', 'Item not found.');
  end if;

  v_new_quantity := coalesce(v_item.quantity, 0) + p_quantity_delta;

  if v_new_quantity < 0 then
    return jsonb_build_object('ok', false, 'message', 'This would take stock below zero.');
  end if;

  v_new_reorder_level := case when p_reorder_level is not null then p_reorder_level else v_item.reorder_level end;

  update public.business_items
  set quantity = v_new_quantity, reorder_level = v_new_reorder_level
  where id = p_item_id;

  insert into public.ungani_stock_movements (
    tenant_id, item_id, movement_type, quantity_delta, quantity_before, quantity_after, reason, created_by
  )
  values (
    v_tenant_id, p_item_id, v_clean_type, p_quantity_delta, coalesce(v_item.quantity, 0), v_new_quantity,
    nullif(trim(coalesce(p_reason, '')), ''), auth.uid()
  );

  v_out_of_stock := v_new_quantity = 0;
  v_low_stock := (not v_out_of_stock) and v_new_reorder_level is not null and v_new_quantity <= v_new_reorder_level;

  return jsonb_build_object(
    'ok', true,
    'message', 'Stock adjusted.',
    'quantity', v_new_quantity,
    'reorder_level', v_new_reorder_level,
    'out_of_stock', v_out_of_stock,
    'low_stock', v_low_stock
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

-- 2. convert_ungani_order_to_invoice - money / create
CREATE OR REPLACE FUNCTION public.convert_ungani_order_to_invoice(p_order_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_order record;
  v_invoice_id uuid;
  v_invoice_number text;
  v_next_number integer;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.ungani_staff_can('money', 'create') then
    return jsonb_build_object('ok', false, 'message', 'You do not have permission to create invoices.');
  end if;

  select * into v_order
  from public.ungani_orders
  where id = p_order_id and tenant_id = v_tenant_id;

  if v_order.id is null then
    return jsonb_build_object('ok', false, 'message', 'Order not found.');
  end if;

  if v_order.status <> 'fulfilled' then
    return jsonb_build_object('ok', false, 'message', 'Only a fully fulfilled order can be converted to an invoice.');
  end if;

  update public.tenants
  set next_invoice_number = next_invoice_number + 1
  where id = v_tenant_id
  returning next_invoice_number - 1 into v_next_number;

  v_invoice_number := 'INV-' || to_char(current_date, 'YYYY') || '-' || lpad(v_next_number::text, 4, '0');

  insert into public.ungani_customer_invoices (
    tenant_id, invoice_number, customer_person_id, customer_name, customer_address,
    customer_contact, delivery_address, delivery_date, payment_terms,
    payment_details, vat_applicable, vat_rate, vat_pricing_mode, discount_amount,
    subtotal, vat_amount, total_amount, currency, status, notes, created_by
  )
  values (
    v_tenant_id, v_invoice_number, v_order.customer_person_id, v_order.customer_name,
    v_order.customer_address, v_order.customer_contact, v_order.delivery_address,
    v_order.delivery_date, v_order.payment_terms, v_order.payment_details,
    v_order.vat_applicable, v_order.vat_rate, v_order.vat_pricing_mode,
    v_order.discount_amount, v_order.subtotal, v_order.vat_amount, v_order.total_amount,
    v_order.currency, 'draft',
    trim(both from coalesce('Converted from ' || v_order.order_number || '. ', '') || coalesce(v_order.notes, '')),
    auth.uid()
  )
  returning id into v_invoice_id;

  insert into public.ungani_customer_invoice_items (
    invoice_id, tenant_id, description, quantity, unit_price, line_subtotal, sort_order
  )
  select v_invoice_id, v_tenant_id, description, quantity, unit_price, line_subtotal, sort_order
  from public.ungani_order_items
  where order_id = p_order_id;

  update public.ungani_orders
  set status = 'invoiced', converted_invoice_id = v_invoice_id, updated_at = now()
  where id = p_order_id;

  return jsonb_build_object('ok', true, 'invoice_id', v_invoice_id, 'invoice_number', v_invoice_number);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

-- 3. convert_ungani_quotation_to_invoice - money / create
CREATE OR REPLACE FUNCTION public.convert_ungani_quotation_to_invoice(p_quotation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_quotation record;
  v_invoice_id uuid;
  v_invoice_number text;
  v_next_number integer;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.ungani_staff_can('money', 'create') then
    return jsonb_build_object('ok', false, 'message', 'You do not have permission to create invoices.');
  end if;

  select * into v_quotation
  from public.ungani_quotations
  where id = p_quotation_id and tenant_id = v_tenant_id;

  if v_quotation.id is null then
    return jsonb_build_object('ok', false, 'message', 'Quotation not found.');
  end if;

  if v_quotation.status not in ('sent', 'accepted') then
    return jsonb_build_object('ok', false, 'message', 'Only a sent or accepted quotation can be converted to an invoice.');
  end if;

  update public.tenants
  set next_invoice_number = next_invoice_number + 1
  where id = v_tenant_id
  returning next_invoice_number - 1 into v_next_number;

  v_invoice_number := 'INV-' || to_char(current_date, 'YYYY') || '-' || lpad(v_next_number::text, 4, '0');

  insert into public.ungani_customer_invoices (
    tenant_id, invoice_number, customer_person_id, customer_name, customer_address,
    customer_contact, delivery_address, delivery_date, payment_terms,
    payment_details, vat_applicable, vat_rate, vat_pricing_mode, discount_amount,
    subtotal, vat_amount, total_amount, currency, status, notes, created_by
  )
  values (
    v_tenant_id, v_invoice_number, v_quotation.customer_person_id, v_quotation.customer_name,
    v_quotation.customer_address, v_quotation.customer_contact, v_quotation.delivery_address,
    v_quotation.delivery_date, v_quotation.payment_terms, v_quotation.payment_details,
    v_quotation.vat_applicable, v_quotation.vat_rate, v_quotation.vat_pricing_mode,
    v_quotation.discount_amount, v_quotation.subtotal, v_quotation.vat_amount, v_quotation.total_amount,
    v_quotation.currency, 'draft',
    trim(both from coalesce('Converted from ' || v_quotation.quotation_number || '. ', '') || coalesce(v_quotation.notes, '')),
    auth.uid()
  )
  returning id into v_invoice_id;

  insert into public.ungani_customer_invoice_items (
    invoice_id, tenant_id, description, quantity, unit_price, line_subtotal, sort_order
  )
  select v_invoice_id, v_tenant_id, description, quantity, unit_price, line_subtotal, sort_order
  from public.ungani_quotation_items
  where quotation_id = p_quotation_id;

  update public.ungani_quotations
  set status = 'converted', converted_invoice_id = v_invoice_id, updated_at = now()
  where id = p_quotation_id;

  return jsonb_build_object('ok', true, 'invoice_id', v_invoice_id, 'invoice_number', v_invoice_number);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

-- 4. fulfill_ungani_order_item - money / edit (also requires items/edit
-- internally via adjust_ungani_stock when stock tracking is on -
-- deliberate, confirmed with the user)
CREATE OR REPLACE FUNCTION public.fulfill_ungani_order_item(p_order_item_id uuid, p_fulfill_quantity numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_stock_tracking_enabled boolean;
  v_line record;
  v_order_status text;
  v_new_fulfilled numeric;
  v_stock_result jsonb;
  v_total_ordered numeric;
  v_total_fulfilled numeric;
  v_new_order_status text;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.ungani_staff_can('money', 'edit') then
    return jsonb_build_object('ok', false, 'message', 'You do not have permission to fulfil orders.');
  end if;

  if p_fulfill_quantity is null or p_fulfill_quantity <= 0 then
    return jsonb_build_object('ok', false, 'message', 'Fulfil quantity must be greater than zero.');
  end if;

  select oi.id, oi.order_id, oi.item_id, oi.quantity, oi.fulfilled_quantity, o.status, o.order_number
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

  v_new_fulfilled := v_line.fulfilled_quantity + p_fulfill_quantity;

  if v_new_fulfilled > v_line.quantity then
    return jsonb_build_object('ok', false, 'message', 'That would fulfil more than was ordered on this line.');
  end if;

  select stock_tracking_enabled into v_stock_tracking_enabled
  from public.tenants where id = v_tenant_id;

  if v_line.item_id is not null and coalesce(v_stock_tracking_enabled, false) then
    v_stock_result := public.adjust_ungani_stock(
      v_line.item_id, 'sale', -p_fulfill_quantity, 'Order fulfillment: ' || v_line.order_number
    );

    if coalesce((v_stock_result->>'ok')::boolean, false) is not true then
      return jsonb_build_object('ok', false, 'message', coalesce(v_stock_result->>'message', 'Could not adjust stock.'));
    end if;
  end if;

  update public.ungani_order_items
  set fulfilled_quantity = v_new_fulfilled
  where id = p_order_item_id;

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

  return jsonb_build_object(
    'ok', true,
    'fulfilled_quantity', v_new_fulfilled,
    'order_status', v_new_order_status
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

-- 5. owner_upsert_ungani_customer_invoice - money / create OR edit, split at the branch point
CREATE OR REPLACE FUNCTION public.owner_upsert_ungani_customer_invoice(p_invoice_id uuid DEFAULT NULL::uuid, p_customer_person_id uuid DEFAULT NULL::uuid, p_customer_name text DEFAULT NULL::text, p_customer_address text DEFAULT NULL::text, p_customer_contact text DEFAULT NULL::text, p_due_date date DEFAULT NULL::date, p_delivery_address text DEFAULT NULL::text, p_delivery_date date DEFAULT NULL::date, p_payment_terms text DEFAULT NULL::text, p_payment_details text DEFAULT NULL::text, p_vat_applicable boolean DEFAULT false, p_vat_rate numeric DEFAULT NULL::numeric, p_vat_pricing_mode text DEFAULT 'inclusive'::text, p_discount_amount numeric DEFAULT 0, p_currency text DEFAULT 'KES'::text, p_notes text DEFAULT NULL::text, p_items jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_invoice_id uuid;
  v_invoice_number text;
  v_next_number integer;
  v_subtotal numeric := 0;
  v_vat_amount numeric := 0;
  v_total numeric := 0;
  v_clean_name text;
  v_item jsonb;
  v_line_subtotal numeric;
  v_sort integer := 0;
  v_existing_status text;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  v_clean_name := nullif(trim(coalesce(p_customer_name, '')), '');

  if v_clean_name is null then
    return jsonb_build_object('ok', false, 'message', 'Customer name is required.');
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_line_subtotal := coalesce((v_item->>'quantity')::numeric, 1) * coalesce((v_item->>'unit_price')::numeric, 0);
    v_subtotal := v_subtotal + v_line_subtotal;
  end loop;

  v_subtotal := v_subtotal - coalesce(p_discount_amount, 0);

  if p_vat_applicable and p_vat_rate is not null and p_vat_rate > 0 then
    if p_vat_pricing_mode = 'exclusive' then
      v_vat_amount := round(v_subtotal * p_vat_rate / 100, 2);
      v_total := round(v_subtotal + v_vat_amount, 2);
    else
      v_vat_amount := round(v_subtotal * p_vat_rate / (100 + p_vat_rate), 2);
      v_total := v_subtotal;
    end if;
  else
    v_vat_amount := 0;
    v_total := v_subtotal;
  end if;

  if p_invoice_id is not null then
    if not public.ungani_staff_can('money', 'edit') then
      return jsonb_build_object('ok', false, 'message', 'You do not have permission to edit invoices.');
    end if;

    select status into v_existing_status
    from public.ungani_customer_invoices
    where id = p_invoice_id and tenant_id = v_tenant_id;

    if v_existing_status is null then
      return jsonb_build_object('ok', false, 'message', 'Invoice not found.');
    end if;

    if v_existing_status not in ('draft', 'sent') then
      return jsonb_build_object('ok', false, 'message', 'Only draft or sent invoices can be edited.');
    end if;

    update public.ungani_customer_invoices
    set customer_person_id = p_customer_person_id,
        customer_name = v_clean_name,
        customer_address = nullif(trim(coalesce(p_customer_address, '')), ''),
        customer_contact = nullif(trim(coalesce(p_customer_contact, '')), ''),
        due_date = p_due_date,
        delivery_address = nullif(trim(coalesce(p_delivery_address, '')), ''),
        delivery_date = p_delivery_date,
        payment_terms = nullif(trim(coalesce(p_payment_terms, '')), ''),
        payment_details = nullif(trim(coalesce(p_payment_details, '')), ''),
        vat_applicable = coalesce(p_vat_applicable, false),
        vat_rate = p_vat_rate,
        vat_pricing_mode = coalesce(p_vat_pricing_mode, 'inclusive'),
        discount_amount = coalesce(p_discount_amount, 0),
        subtotal = v_subtotal,
        vat_amount = v_vat_amount,
        total_amount = v_total,
        currency = coalesce(p_currency, 'KES'),
        notes = nullif(trim(coalesce(p_notes, '')), ''),
        updated_at = now()
    where id = p_invoice_id and tenant_id = v_tenant_id
    returning id into v_invoice_id;

    delete from public.ungani_customer_invoice_items where invoice_id = v_invoice_id;
  else
    if not public.ungani_staff_can('money', 'create') then
      return jsonb_build_object('ok', false, 'message', 'You do not have permission to create invoices.');
    end if;

    update public.tenants
    set next_invoice_number = next_invoice_number + 1
    where id = v_tenant_id
    returning next_invoice_number - 1 into v_next_number;

    v_invoice_number := 'INV-' || to_char(current_date, 'YYYY') || '-' || lpad(v_next_number::text, 4, '0');

    insert into public.ungani_customer_invoices (
      tenant_id, invoice_number, customer_person_id, customer_name, customer_address,
      customer_contact, due_date, delivery_address, delivery_date, payment_terms,
      payment_details, vat_applicable, vat_rate, vat_pricing_mode, discount_amount,
      subtotal, vat_amount, total_amount, currency, status, notes, created_by
    )
    values (
      v_tenant_id, v_invoice_number, p_customer_person_id, v_clean_name,
      nullif(trim(coalesce(p_customer_address, '')), ''),
      nullif(trim(coalesce(p_customer_contact, '')), ''),
      p_due_date, nullif(trim(coalesce(p_delivery_address, '')), ''), p_delivery_date,
      nullif(trim(coalesce(p_payment_terms, '')), ''), nullif(trim(coalesce(p_payment_details, '')), ''),
      coalesce(p_vat_applicable, false), p_vat_rate, coalesce(p_vat_pricing_mode, 'inclusive'),
      coalesce(p_discount_amount, 0), v_subtotal, v_vat_amount, v_total,
      coalesce(p_currency, 'KES'), 'draft', nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
    )
    returning id into v_invoice_id;
  end if;

  v_sort := 0;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_line_subtotal := coalesce((v_item->>'quantity')::numeric, 1) * coalesce((v_item->>'unit_price')::numeric, 0);

    insert into public.ungani_customer_invoice_items (
      invoice_id, tenant_id, description, quantity, unit_price, line_subtotal, sort_order
    )
    values (
      v_invoice_id, v_tenant_id, coalesce(v_item->>'description', ''),
      coalesce((v_item->>'quantity')::numeric, 1), coalesce((v_item->>'unit_price')::numeric, 0),
      v_line_subtotal, v_sort
    );

    v_sort := v_sort + 1;
  end loop;

  return jsonb_build_object('ok', true, 'id', v_invoice_id, 'invoice_id', v_invoice_id);
end;
$function$;

-- 6. owner_upsert_ungani_order - money / create OR edit, split at the branch point
CREATE OR REPLACE FUNCTION public.owner_upsert_ungani_order(p_order_id uuid DEFAULT NULL::uuid, p_customer_person_id uuid DEFAULT NULL::uuid, p_customer_name text DEFAULT NULL::text, p_customer_address text DEFAULT NULL::text, p_customer_contact text DEFAULT NULL::text, p_expected_fulfillment_date date DEFAULT NULL::date, p_delivery_address text DEFAULT NULL::text, p_delivery_date date DEFAULT NULL::date, p_payment_terms text DEFAULT NULL::text, p_payment_details text DEFAULT NULL::text, p_vat_applicable boolean DEFAULT false, p_vat_rate numeric DEFAULT NULL::numeric, p_vat_pricing_mode text DEFAULT 'inclusive'::text, p_discount_amount numeric DEFAULT 0, p_currency text DEFAULT 'KES'::text, p_notes text DEFAULT NULL::text, p_items jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_order_id uuid;
  v_order_number text;
  v_next_number integer;
  v_subtotal numeric := 0;
  v_vat_amount numeric := 0;
  v_total numeric := 0;
  v_clean_name text;
  v_item jsonb;
  v_item_id uuid;
  v_line_subtotal numeric;
  v_sort integer := 0;
  v_existing_status text;
  v_item_tenant_check uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  v_clean_name := nullif(trim(coalesce(p_customer_name, '')), '');

  if v_clean_name is null then
    return jsonb_build_object('ok', false, 'message', 'Customer name is required.');
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_line_subtotal := coalesce((v_item->>'quantity')::numeric, 1) * coalesce((v_item->>'unit_price')::numeric, 0);
    v_subtotal := v_subtotal + v_line_subtotal;
  end loop;

  v_subtotal := v_subtotal - coalesce(p_discount_amount, 0);

  if p_vat_applicable and p_vat_rate is not null and p_vat_rate > 0 then
    if p_vat_pricing_mode = 'exclusive' then
      v_vat_amount := round(v_subtotal * p_vat_rate / 100, 2);
      v_total := round(v_subtotal + v_vat_amount, 2);
    else
      v_vat_amount := round(v_subtotal * p_vat_rate / (100 + p_vat_rate), 2);
      v_total := v_subtotal;
    end if;
  else
    v_vat_amount := 0;
    v_total := v_subtotal;
  end if;

  if p_order_id is not null then
    if not public.ungani_staff_can('money', 'edit') then
      return jsonb_build_object('ok', false, 'message', 'You do not have permission to edit orders.');
    end if;

    select status into v_existing_status
    from public.ungani_orders
    where id = p_order_id and tenant_id = v_tenant_id;

    if v_existing_status is null then
      return jsonb_build_object('ok', false, 'message', 'Order not found.');
    end if;

    if v_existing_status not in ('pending', 'confirmed') then
      return jsonb_build_object('ok', false, 'message', 'This order has already started fulfillment and can no longer be edited.');
    end if;

    update public.ungani_orders
    set customer_person_id = p_customer_person_id,
        customer_name = v_clean_name,
        customer_address = nullif(trim(coalesce(p_customer_address, '')), ''),
        customer_contact = nullif(trim(coalesce(p_customer_contact, '')), ''),
        expected_fulfillment_date = p_expected_fulfillment_date,
        delivery_address = nullif(trim(coalesce(p_delivery_address, '')), ''),
        delivery_date = p_delivery_date,
        payment_terms = nullif(trim(coalesce(p_payment_terms, '')), ''),
        payment_details = nullif(trim(coalesce(p_payment_details, '')), ''),
        vat_applicable = coalesce(p_vat_applicable, false),
        vat_rate = p_vat_rate,
        vat_pricing_mode = coalesce(p_vat_pricing_mode, 'inclusive'),
        discount_amount = coalesce(p_discount_amount, 0),
        subtotal = v_subtotal,
        vat_amount = v_vat_amount,
        total_amount = v_total,
        currency = coalesce(p_currency, 'KES'),
        notes = nullif(trim(coalesce(p_notes, '')), ''),
        updated_at = now()
    where id = p_order_id and tenant_id = v_tenant_id
    returning id into v_order_id;

    delete from public.ungani_order_items where order_id = v_order_id;
  else
    if not public.ungani_staff_can('money', 'create') then
      return jsonb_build_object('ok', false, 'message', 'You do not have permission to create orders.');
    end if;

    update public.tenants
    set next_order_number = next_order_number + 1
    where id = v_tenant_id
    returning next_order_number - 1 into v_next_number;

    v_order_number := 'ORD-' || to_char(current_date, 'YYYY') || '-' || lpad(v_next_number::text, 4, '0');

    insert into public.ungani_orders (
      tenant_id, order_number, customer_person_id, customer_name, customer_address,
      customer_contact, expected_fulfillment_date, delivery_address, delivery_date, payment_terms,
      payment_details, vat_applicable, vat_rate, vat_pricing_mode, discount_amount,
      subtotal, vat_amount, total_amount, currency, status, notes, created_by
    )
    values (
      v_tenant_id, v_order_number, p_customer_person_id, v_clean_name,
      nullif(trim(coalesce(p_customer_address, '')), ''),
      nullif(trim(coalesce(p_customer_contact, '')), ''),
      p_expected_fulfillment_date, nullif(trim(coalesce(p_delivery_address, '')), ''), p_delivery_date,
      nullif(trim(coalesce(p_payment_terms, '')), ''), nullif(trim(coalesce(p_payment_details, '')), ''),
      coalesce(p_vat_applicable, false), p_vat_rate, coalesce(p_vat_pricing_mode, 'inclusive'),
      coalesce(p_discount_amount, 0), v_subtotal, v_vat_amount, v_total,
      coalesce(p_currency, 'KES'), 'pending', nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
    )
    returning id into v_order_id;
  end if;

  v_sort := 0;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_line_subtotal := coalesce((v_item->>'quantity')::numeric, 1) * coalesce((v_item->>'unit_price')::numeric, 0);

    v_item_id := nullif(v_item->>'item_id', '')::uuid;

    if v_item_id is not null then
      select id into v_item_tenant_check
      from public.business_items
      where id = v_item_id and tenant_id = v_tenant_id;

      if v_item_tenant_check is null then
        v_item_id := null;
      end if;
    end if;

    insert into public.ungani_order_items (
      order_id, tenant_id, item_id, description, quantity, unit_price, line_subtotal, sort_order
    )
    values (
      v_order_id, v_tenant_id, v_item_id, coalesce(v_item->>'description', ''),
      coalesce((v_item->>'quantity')::numeric, 1), coalesce((v_item->>'unit_price')::numeric, 0),
      v_line_subtotal, v_sort
    );

    v_sort := v_sort + 1;
  end loop;

  return jsonb_build_object('ok', true, 'id', v_order_id, 'order_id', v_order_id);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

-- 7. owner_upsert_ungani_price_list - money / create OR edit, split at the branch point
CREATE OR REPLACE FUNCTION public.owner_upsert_ungani_price_list(p_price_list_id uuid DEFAULT NULL::uuid, p_name text DEFAULT NULL::text, p_description text DEFAULT NULL::text, p_entries jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_price_list_id uuid;
  v_clean_name text;
  v_entry jsonb;
  v_item_id uuid;
  v_price numeric;
  v_item_tenant_check uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  v_clean_name := nullif(trim(coalesce(p_name, '')), '');

  if v_clean_name is null then
    return jsonb_build_object('ok', false, 'message', 'A name is required for this price list.');
  end if;

  if p_price_list_id is not null then
    if not public.ungani_staff_can('money', 'edit') then
      return jsonb_build_object('ok', false, 'message', 'You do not have permission to edit price lists.');
    end if;

    update public.ungani_price_lists
    set name = v_clean_name,
        description = nullif(trim(coalesce(p_description, '')), ''),
        updated_at = now()
    where id = p_price_list_id and tenant_id = v_tenant_id
    returning id into v_price_list_id;

    if v_price_list_id is null then
      return jsonb_build_object('ok', false, 'message', 'Price list not found.');
    end if;

    delete from public.ungani_price_list_items where price_list_id = v_price_list_id;
  else
    if not public.ungani_staff_can('money', 'create') then
      return jsonb_build_object('ok', false, 'message', 'You do not have permission to create price lists.');
    end if;

    insert into public.ungani_price_lists (tenant_id, name, description, created_by)
    values (v_tenant_id, v_clean_name, nullif(trim(coalesce(p_description, '')), ''), auth.uid())
    returning id into v_price_list_id;
  end if;

  for v_entry in select * from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb))
  loop
    v_item_id := nullif(v_entry->>'item_id', '')::uuid;
    v_price := nullif(v_entry->>'price', '')::numeric;

    if v_item_id is null or v_price is null then
      continue;
    end if;

    select id into v_item_tenant_check
    from public.business_items
    where id = v_item_id and tenant_id = v_tenant_id;

    if v_item_tenant_check is null then
      continue;
    end if;

    insert into public.ungani_price_list_items (price_list_id, tenant_id, item_id, price)
    values (v_price_list_id, v_tenant_id, v_item_id, v_price)
    on conflict (price_list_id, item_id) do update set price = excluded.price;
  end loop;

  return jsonb_build_object('ok', true, 'id', v_price_list_id, 'price_list_id', v_price_list_id);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'message', 'You already have a price list with that name.');
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

-- 8. owner_upsert_ungani_quotation - money / create OR edit, split at the branch point
CREATE OR REPLACE FUNCTION public.owner_upsert_ungani_quotation(p_quotation_id uuid DEFAULT NULL::uuid, p_customer_person_id uuid DEFAULT NULL::uuid, p_customer_name text DEFAULT NULL::text, p_customer_address text DEFAULT NULL::text, p_customer_contact text DEFAULT NULL::text, p_valid_until date DEFAULT NULL::date, p_delivery_address text DEFAULT NULL::text, p_delivery_date date DEFAULT NULL::date, p_payment_terms text DEFAULT NULL::text, p_payment_details text DEFAULT NULL::text, p_vat_applicable boolean DEFAULT false, p_vat_rate numeric DEFAULT NULL::numeric, p_vat_pricing_mode text DEFAULT 'inclusive'::text, p_discount_amount numeric DEFAULT 0, p_currency text DEFAULT 'KES'::text, p_notes text DEFAULT NULL::text, p_items jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_quotation_id uuid;
  v_quotation_number text;
  v_next_number integer;
  v_subtotal numeric := 0;
  v_vat_amount numeric := 0;
  v_total numeric := 0;
  v_clean_name text;
  v_item jsonb;
  v_line_subtotal numeric;
  v_sort integer := 0;
  v_existing_status text;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  v_clean_name := nullif(trim(coalesce(p_customer_name, '')), '');

  if v_clean_name is null then
    return jsonb_build_object('ok', false, 'message', 'Customer name is required.');
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_line_subtotal := coalesce((v_item->>'quantity')::numeric, 1) * coalesce((v_item->>'unit_price')::numeric, 0);
    v_subtotal := v_subtotal + v_line_subtotal;
  end loop;

  v_subtotal := v_subtotal - coalesce(p_discount_amount, 0);

  if p_vat_applicable and p_vat_rate is not null and p_vat_rate > 0 then
    if p_vat_pricing_mode = 'exclusive' then
      v_vat_amount := round(v_subtotal * p_vat_rate / 100, 2);
      v_total := round(v_subtotal + v_vat_amount, 2);
    else
      v_vat_amount := round(v_subtotal * p_vat_rate / (100 + p_vat_rate), 2);
      v_total := v_subtotal;
    end if;
  else
    v_vat_amount := 0;
    v_total := v_subtotal;
  end if;

  if p_quotation_id is not null then
    if not public.ungani_staff_can('money', 'edit') then
      return jsonb_build_object('ok', false, 'message', 'You do not have permission to edit quotations.');
    end if;

    select status into v_existing_status
    from public.ungani_quotations
    where id = p_quotation_id and tenant_id = v_tenant_id;

    if v_existing_status is null then
      return jsonb_build_object('ok', false, 'message', 'Quotation not found.');
    end if;

    if v_existing_status not in ('draft', 'sent') then
      return jsonb_build_object('ok', false, 'message', 'Only draft or sent quotations can be edited.');
    end if;

    update public.ungani_quotations
    set customer_person_id = p_customer_person_id,
        customer_name = v_clean_name,
        customer_address = nullif(trim(coalesce(p_customer_address, '')), ''),
        customer_contact = nullif(trim(coalesce(p_customer_contact, '')), ''),
        valid_until = p_valid_until,
        delivery_address = nullif(trim(coalesce(p_delivery_address, '')), ''),
        delivery_date = p_delivery_date,
        payment_terms = nullif(trim(coalesce(p_payment_terms, '')), ''),
        payment_details = nullif(trim(coalesce(p_payment_details, '')), ''),
        vat_applicable = coalesce(p_vat_applicable, false),
        vat_rate = p_vat_rate,
        vat_pricing_mode = coalesce(p_vat_pricing_mode, 'inclusive'),
        discount_amount = coalesce(p_discount_amount, 0),
        subtotal = v_subtotal,
        vat_amount = v_vat_amount,
        total_amount = v_total,
        currency = coalesce(p_currency, 'KES'),
        notes = nullif(trim(coalesce(p_notes, '')), ''),
        updated_at = now()
    where id = p_quotation_id and tenant_id = v_tenant_id
    returning id into v_quotation_id;

    delete from public.ungani_quotation_items where quotation_id = v_quotation_id;
  else
    if not public.ungani_staff_can('money', 'create') then
      return jsonb_build_object('ok', false, 'message', 'You do not have permission to create quotations.');
    end if;

    update public.tenants
    set next_quotation_number = next_quotation_number + 1
    where id = v_tenant_id
    returning next_quotation_number - 1 into v_next_number;

    v_quotation_number := 'QUO-' || to_char(current_date, 'YYYY') || '-' || lpad(v_next_number::text, 4, '0');

    insert into public.ungani_quotations (
      tenant_id, quotation_number, customer_person_id, customer_name, customer_address,
      customer_contact, valid_until, delivery_address, delivery_date, payment_terms,
      payment_details, vat_applicable, vat_rate, vat_pricing_mode, discount_amount,
      subtotal, vat_amount, total_amount, currency, status, notes, created_by
    )
    values (
      v_tenant_id, v_quotation_number, p_customer_person_id, v_clean_name,
      nullif(trim(coalesce(p_customer_address, '')), ''),
      nullif(trim(coalesce(p_customer_contact, '')), ''),
      p_valid_until, nullif(trim(coalesce(p_delivery_address, '')), ''), p_delivery_date,
      nullif(trim(coalesce(p_payment_terms, '')), ''), nullif(trim(coalesce(p_payment_details, '')), ''),
      coalesce(p_vat_applicable, false), p_vat_rate, coalesce(p_vat_pricing_mode, 'inclusive'),
      coalesce(p_discount_amount, 0), v_subtotal, v_vat_amount, v_total,
      coalesce(p_currency, 'KES'), 'draft', nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
    )
    returning id into v_quotation_id;
  end if;

  v_sort := 0;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_line_subtotal := coalesce((v_item->>'quantity')::numeric, 1) * coalesce((v_item->>'unit_price')::numeric, 0);

    insert into public.ungani_quotation_items (
      quotation_id, tenant_id, description, quantity, unit_price, line_subtotal, sort_order
    )
    values (
      v_quotation_id, v_tenant_id, coalesce(v_item->>'description', ''),
      coalesce((v_item->>'quantity')::numeric, 1), coalesce((v_item->>'unit_price')::numeric, 0),
      v_line_subtotal, v_sort
    );

    v_sort := v_sort + 1;
  end loop;

  return jsonb_build_object('ok', true, 'id', v_quotation_id, 'quotation_id', v_quotation_id);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

-- 9. record_ungani_invoice_payment - money / create
CREATE OR REPLACE FUNCTION public.record_ungani_invoice_payment(p_invoice_id uuid, p_amount numeric, p_paid_at date DEFAULT CURRENT_DATE, p_method text DEFAULT NULL::text, p_reference text DEFAULT NULL::text, p_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_invoice record;
  v_new_paid numeric;
  v_new_status text;
  v_payment_id uuid;
  v_transaction_id uuid;
  v_vat_for_payment numeric := 0;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.ungani_staff_can('money', 'create') then
    return jsonb_build_object('ok', false, 'message', 'You do not have permission to record payments.');
  end if;

  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object('ok', false, 'message', 'Payment amount must be greater than zero.');
  end if;

  select * into v_invoice
  from public.ungani_customer_invoices
  where id = p_invoice_id and tenant_id = v_tenant_id;

  if v_invoice.id is null then
    return jsonb_build_object('ok', false, 'message', 'Invoice not found.');
  end if;

  if v_invoice.status = 'cancelled' then
    return jsonb_build_object('ok', false, 'message', 'Cannot record a payment against a cancelled invoice.');
  end if;

  insert into public.ungani_customer_invoice_payments (
    invoice_id, tenant_id, amount, paid_at, method, reference, notes, created_by
  )
  values (
    p_invoice_id, v_tenant_id, p_amount, coalesce(p_paid_at, current_date), p_method, p_reference, p_notes, auth.uid()
  )
  returning id into v_payment_id;

  v_new_paid := v_invoice.amount_paid + p_amount;
  v_new_status := case
    when v_new_paid >= v_invoice.total_amount then 'paid'
    when v_new_paid > 0 then 'partially_paid'
    else v_invoice.status
  end;

  update public.ungani_customer_invoices
  set amount_paid = v_new_paid, status = v_new_status, updated_at = now()
  where id = p_invoice_id;

  if v_invoice.currency = 'KES' then
    if v_invoice.total_amount > 0 then
      v_vat_for_payment := round(p_amount * v_invoice.vat_amount / v_invoice.total_amount, 2);
    else
      v_vat_for_payment := 0;
    end if;

    insert into public.transactions (
      tenant_id, transaction_type, amount, currency, amount_kes,
      payment_status, payment_method, payment_reference, transaction_date,
      category, description, notes,
      vat_applicable, vat_rate, vat_amount, vat_amount_kes, vat_pricing_mode,
      related_person_id, related_invoice_id, related_invoice_payment_id,
      created_by
    )
    values (
      v_tenant_id, 'income', p_amount, 'KES', p_amount,
      'paid', p_method, p_reference, coalesce(p_paid_at, current_date),
      'Invoice Payment',
      'Payment for Invoice ' || v_invoice.invoice_number,
      'Customer: ' || v_invoice.customer_name,
      v_invoice.vat_applicable, v_invoice.vat_rate, v_vat_for_payment, v_vat_for_payment, v_invoice.vat_pricing_mode,
      v_invoice.customer_person_id, p_invoice_id, v_payment_id,
      auth.uid()
    )
    returning id into v_transaction_id;

    return jsonb_build_object(
      'ok', true,
      'amount_paid', v_new_paid,
      'status', v_new_status,
      'transaction_created', true,
      'transaction_id', v_transaction_id
    );
  end if;

  return jsonb_build_object(
    'ok', true,
    'amount_paid', v_new_paid,
    'status', v_new_status,
    'transaction_created', false,
    'transaction_skipped_reason', 'Invoice currency is ' || v_invoice.currency || ', not KES - Money sync for non-KES invoices is not yet supported.'
  );
end;
$function$;

-- 10. update_ungani_invoice_status - money / edit
CREATE OR REPLACE FUNCTION public.update_ungani_invoice_status(p_invoice_id uuid, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_clean_status text;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.ungani_staff_can('money', 'edit') then
    return jsonb_build_object('ok', false, 'message', 'You do not have permission to edit invoices.');
  end if;

  v_clean_status := lower(trim(coalesce(p_status, '')));

  if v_clean_status not in ('draft', 'sent', 'cancelled') then
    return jsonb_build_object('ok', false, 'message', 'Invalid status. Use draft, sent, or cancelled.');
  end if;

  update public.ungani_customer_invoices
  set status = v_clean_status, updated_at = now()
  where id = p_invoice_id and tenant_id = v_tenant_id
    and status not in ('partially_paid', 'paid');

  if not found then
    return jsonb_build_object('ok', false, 'message', 'Invoice not found, or already has payments recorded against it.');
  end if;

  return jsonb_build_object('ok', true);
end;
$function$;

-- 11. update_ungani_order_status - money / edit
CREATE OR REPLACE FUNCTION public.update_ungani_order_status(p_order_id uuid, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_clean_status text;
  v_existing_status text;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.ungani_staff_can('money', 'edit') then
    return jsonb_build_object('ok', false, 'message', 'You do not have permission to edit orders.');
  end if;

  v_clean_status := lower(trim(coalesce(p_status, '')));

  if v_clean_status not in ('confirmed', 'cancelled') then
    return jsonb_build_object('ok', false, 'message', 'Invalid status. Use confirmed or cancelled.');
  end if;

  select status into v_existing_status
  from public.ungani_orders
  where id = p_order_id and tenant_id = v_tenant_id;

  if v_existing_status is null then
    return jsonb_build_object('ok', false, 'message', 'Order not found.');
  end if;

  if v_clean_status = 'confirmed' and v_existing_status <> 'pending' then
    return jsonb_build_object('ok', false, 'message', 'Only a pending order can be confirmed.');
  end if;

  if v_clean_status = 'cancelled' and v_existing_status not in ('pending', 'confirmed') then
    return jsonb_build_object('ok', false, 'message', 'This order has already started fulfillment and can no longer be cancelled.');
  end if;

  update public.ungani_orders
  set status = v_clean_status, updated_at = now()
  where id = p_order_id and tenant_id = v_tenant_id;

  return jsonb_build_object('ok', true);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

-- 12. update_ungani_quotation_status - money / edit
CREATE OR REPLACE FUNCTION public.update_ungani_quotation_status(p_quotation_id uuid, p_status text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_clean_status text;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.ungani_staff_can('money', 'edit') then
    return jsonb_build_object('ok', false, 'message', 'You do not have permission to edit quotations.');
  end if;

  v_clean_status := lower(trim(coalesce(p_status, '')));

  if v_clean_status not in ('draft', 'sent', 'accepted', 'rejected', 'cancelled') then
    return jsonb_build_object('ok', false, 'message', 'Invalid status. Use draft, sent, accepted, rejected, or cancelled.');
  end if;

  update public.ungani_quotations
  set status = v_clean_status, updated_at = now()
  where id = p_quotation_id and tenant_id = v_tenant_id
    and status <> 'converted';

  if not found then
    return jsonb_build_object('ok', false, 'message', 'Quotation not found, or it has already been converted to an invoice.');
  end if;

  return jsonb_build_object('ok', true);
end;
$function$;
