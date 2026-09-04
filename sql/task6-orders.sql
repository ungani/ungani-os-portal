-- Task 6: Orders.
--
-- Separate ungani_orders + ungani_order_items tables - not chained off
-- Quotations, not an extension of ungani_customer_invoices. Confirmed via
-- the real schema (task2 invoices, task3 stock tracking, task5
-- quotations - all already-run and live) that neither existing document
-- covers the fulfillment step: a converted Quotation or a sent Invoice
-- never touches business_items.quantity - adjust_ungani_stock() is the
-- only place stock is allowed to move, and nothing calls it today. An
-- Order is the missing middle document: customer has committed, goods
-- haven't shipped/been invoiced yet, and (only when the tenant has Stock
-- Tracking on) fulfilling a line is what should actually deduct
-- inventory - via adjust_ungani_stock() exactly as it already exists,
-- not a second stock-mutation path.
--
-- Per user decision: stand-alone (not Quote -> Order -> Invoice - Orders
-- and Quotations are two independent ways to start a sale, each
-- converting straight to Invoice on its own), and ungated (always
-- visible like Quotations/Customer Invoices, not behind a Settings
-- toggle like Stock Tracking/Debtors & Payables) - the stock-linkage
-- behavior itself already degrades gracefully when Stock Tracking is
-- off, so a second toggle would be redundant.
--
-- Scope line drawn deliberately narrow for v1: convert-to-invoice is
-- only allowed once an order is fully 'fulfilled' (not partially) - so
-- there's exactly one invoice per order, mirroring Quotations' one-shot
-- conversion exactly, rather than inventing multi-invoice-per-order
-- semantics nobody asked for. Cancelling is only allowed before any
-- fulfillment has happened (pending/confirmed) - once stock has moved
-- for a line, there's no reversal path in v1, so cancelling is blocked
-- rather than silently leaving stock inconsistent.
--
-- Also proactively adds ungani_orders to soft_delete_ungani_record() and
-- get_my_ungani_recently_deleted_v2()'s allowlists in this same
-- migration - the same gap Customer Invoicing (Task 2) and Quotations
-- (Task 5) both hit. Extended from sql/task5-quotations.sql's own
-- CREATE OR REPLACE bodies, which the user confirmed are the real, live
-- source (all 4 of that migration's verification checks passed) - not
-- fabricated, since that's the actual current definition of both
-- functions in the database right now.

-- ============================================================
-- PART A: Order numbering sequence.
-- ============================================================

alter table public.tenants
  add column if not exists next_order_number integer not null default 1;

-- ============================================================
-- PART B: Orders.
-- ============================================================

create table if not exists public.ungani_orders (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  order_number text not null,

  customer_person_id uuid references public.client_people(id) on delete set null,
  customer_name text not null,
  customer_address text,
  customer_contact text,

  order_date date not null default current_date,
  expected_fulfillment_date date,
  delivery_address text,
  delivery_date date,

  payment_terms text,
  payment_details text,

  vat_applicable boolean not null default false,
  vat_rate numeric,
  vat_pricing_mode text not null default 'inclusive',
  discount_amount numeric not null default 0,

  subtotal numeric not null default 0,
  vat_amount numeric not null default 0,
  total_amount numeric not null default 0,
  currency text not null default 'KES',

  status text not null default 'pending',
  notes text,

  converted_invoice_id uuid references public.ungani_customer_invoices(id) on delete set null,

  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  deleted_at timestamptz,
  deleted_by uuid,
  delete_reason text,
  restored_at timestamptz,
  restored_by uuid,

  constraint ungani_orders_status_check
    check (status in ('pending', 'confirmed', 'partially_fulfilled', 'fulfilled', 'invoiced', 'cancelled')),
  constraint ungani_orders_number_unique
    unique (tenant_id, order_number)
);

alter table public.ungani_orders enable row level security;

drop policy if exists ungani_orders_tenant_select on public.ungani_orders;
create policy ungani_orders_tenant_select on public.ungani_orders
  for select
  using (tenant_id = public.get_my_ungani_tenant_id());

grant select on public.ungani_orders to authenticated;

-- ============================================================
-- PART C: Order line items.
-- item_id is the one real structural difference from
-- quotation_items/invoice_items - optional link to a real stock item,
-- so a line can be traced back to inventory and (when Stock Tracking is
-- on) deducted on fulfillment. fulfilled_quantity tracks partial
-- shipment per line, independent of ordered quantity.
-- ============================================================

create table if not exists public.ungani_order_items (
  id uuid primary key default gen_random_uuid(),
  order_id uuid not null references public.ungani_orders(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  item_id uuid references public.business_items(id) on delete set null,
  description text not null,
  quantity numeric not null default 1,
  fulfilled_quantity numeric not null default 0,
  unit_price numeric not null default 0,
  line_subtotal numeric not null default 0,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.ungani_order_items enable row level security;

drop policy if exists ungani_order_items_tenant_select on public.ungani_order_items;
create policy ungani_order_items_tenant_select on public.ungani_order_items
  for select
  using (tenant_id = public.get_my_ungani_tenant_id());

grant select on public.ungani_order_items to authenticated;

-- ============================================================
-- PART D: RPCs.
-- ============================================================

-- Create/edit - only allowed pre-fulfillment (order doesn't exist yet,
-- or its current status is 'pending'/'confirmed'). This is what makes
-- the delete-and-reinsert-items approach (same as quotations/invoices)
-- safe here: fulfilled_quantity is guaranteed to be 0 on every line this
-- can ever touch, so reinserting fresh rows never loses fulfillment
-- history - fulfillment itself only ever happens through
-- fulfill_ungani_order_item() below, never through this function.
create or replace function public.owner_upsert_ungani_order(
  p_order_id uuid default null,
  p_customer_person_id uuid default null,
  p_customer_name text default null,
  p_customer_address text default null,
  p_customer_contact text default null,
  p_expected_fulfillment_date date default null,
  p_delivery_address text default null,
  p_delivery_date date default null,
  p_payment_terms text default null,
  p_payment_details text default null,
  p_vat_applicable boolean default false,
  p_vat_rate numeric default null,
  p_vat_pricing_mode text default 'inclusive',
  p_discount_amount numeric default 0,
  p_currency text default 'KES',
  p_notes text default null,
  p_items jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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

  -- Matches owner_upsert_ungani_quotation's / owner_upsert_ungani_customer_invoice's VAT math exactly.
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

    -- Silently drop the link rather than failing the whole save if the
    -- item doesn't belong to this tenant (e.g. stale client-side state) -
    -- the line still saves as a normal free-text line.
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

grant execute on function public.owner_upsert_ungani_order(
  uuid, uuid, text, text, text, date, text, date, text, text, boolean, numeric, text, numeric, text, text, jsonb
) to authenticated;

-- Manual status transitions - deliberately narrow: pending -> confirmed,
-- or (pending/confirmed) -> cancelled. 'partially_fulfilled'/'fulfilled'
-- are only ever set by fulfill_ungani_order_item() below (derived from
-- real line data, not manually settable - same principle as quotations'
-- 'converted'), and 'invoiced' is only set by
-- convert_ungani_order_to_invoice(). Cancelling is blocked once any
-- fulfillment has happened - there's no stock-reversal path in v1, so
-- rather than leave inventory inconsistent, cancellation simply isn't
-- offered past that point.
create or replace function public.update_ungani_order_status(p_order_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_clean_status text;
  v_existing_status text;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
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

grant execute on function public.update_ungani_order_status(uuid, text) to authenticated;

-- The one place an order line's fulfilled_quantity is allowed to move.
-- Only allowed once the order is confirmed (or already partially
-- fulfilled) - not pending, not cancelled/fulfilled/invoiced. When the
-- line is linked to a real stock item AND the tenant has Stock Tracking
-- on, calls the existing adjust_ungani_stock() exactly as-is (movement
-- type 'sale') rather than moving business_items.quantity directly here -
-- that keeps there being exactly one place stock can move, matching
-- Stock Tracking's own design intent. If that call fails (e.g.
-- insufficient stock), the whole fulfillment is rejected and
-- fulfilled_quantity is left untouched - never a partial, inconsistent
-- update.
create or replace function public.fulfill_ungani_order_item(p_order_item_id uuid, p_fulfill_quantity numeric)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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

grant execute on function public.fulfill_ungani_order_item(uuid, numeric) to authenticated;

-- Converts an order into a real invoice - only once fully 'fulfilled'
-- (deliberately not 'partially_fulfilled' - see the header comment on
-- scope). Copies line items over at their ordered quantity (which by
-- definition equals fulfilled_quantity once status is 'fulfilled'),
-- claims a fresh invoice number, new invoice starts as 'draft' so the
-- owner reviews it before sending - conversion never auto-sends.
create or replace function public.convert_ungani_order_to_invoice(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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

grant execute on function public.convert_ungani_order_to_invoice(uuid) to authenticated;

-- List view - computes "overdue" at read-time (not stored) for an order
-- whose expected_fulfillment_date has passed and hasn't been fully
-- fulfilled yet, same pattern as invoices' "overdue"/quotations' "expired".
create or replace function public.get_my_ungani_orders()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_orders jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', o.id,
      'order_number', o.order_number,
      'customer_name', o.customer_name,
      'order_date', o.order_date,
      'expected_fulfillment_date', o.expected_fulfillment_date,
      'total_amount', o.total_amount,
      'currency', o.currency,
      'status', o.status,
      'converted_invoice_id', o.converted_invoice_id,
      'effective_status', case
        when o.status in ('pending', 'confirmed', 'partially_fulfilled')
          and o.expected_fulfillment_date is not null and o.expected_fulfillment_date < current_date
          then 'overdue'
        else o.status
      end
    )
    order by o.created_at desc
  ), '[]'::jsonb)
  into v_orders
  from public.ungani_orders o
  where o.tenant_id = v_tenant_id
    and o.deleted_at is null;

  return jsonb_build_object('ok', true, 'orders', v_orders);
end;
$function$;

grant execute on function public.get_my_ungani_orders() to authenticated;

-- Single-order detail (items, incl. item_id/fulfilled_quantity) for the
-- edit/fulfil/print view.
create or replace function public.get_ungani_order_detail(p_order_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_order jsonb;
  v_items jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select to_jsonb(o) into v_order
  from public.ungani_orders o
  where o.id = p_order_id and o.tenant_id = v_tenant_id;

  if v_order is null then
    return jsonb_build_object('ok', false, 'message', 'Order not found.');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', id, 'item_id', item_id, 'description', description, 'quantity', quantity,
      'fulfilled_quantity', fulfilled_quantity, 'unit_price', unit_price, 'line_subtotal', line_subtotal
    )
    order by sort_order
  ), '[]'::jsonb)
  into v_items
  from public.ungani_order_items
  where order_id = p_order_id;

  return jsonb_build_object('ok', true, 'order', v_order, 'items', v_items);
end;
$function$;

grant execute on function public.get_ungani_order_detail(uuid) to authenticated;

-- ============================================================
-- PART E: soft_delete_ungani_record() allowlist addition.
-- Extended from sql/task5-quotations.sql's own body (confirmed live) -
-- only the two additions below (allowlist entry + title branch), every
-- other line is unchanged from that confirmed-run version.
-- ============================================================

CREATE OR REPLACE FUNCTION public.soft_delete_ungani_record(p_table_name text, p_record_id uuid, p_delete_reason text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_table text;
  v_tenant_id uuid;
  v_record_tenant_id uuid;
  v_record_title text;
  v_record_subtitle text;
  v_deleted_count integer := 0;
  v_recently_deleted_id uuid;
begin
  v_table := lower(trim(coalesce(p_table_name, '')));

  if v_table not in (
    'tasks',
    'business_items',
    'business_records',
    'documents',
    'support_issues',
    'client_people',
    'business_events',
    'transactions',
    'ungani_customer_invoices',
    'ungani_quotations',
    'ungani_orders'
  ) then
    return jsonb_build_object(
      'ok', false,
      'message', 'This table is not supported for safe delete.'
    );
  end if;

  begin
    v_tenant_id := public.get_my_ungani_current_tenant_id_v16();
  exception
    when others then
      begin
        v_tenant_id := public.get_my_ungani_tenant_id();
      exception
        when others then
          v_tenant_id := null;
      end;
  end;

  if v_tenant_id is null and not public.is_ungani_admin() then
    return jsonb_build_object(
      'ok', false,
      'message', 'No tenant account found.'
    );
  end if;

  if not public.can_write_ungani_client_data() and not public.is_ungani_admin() then
    return jsonb_build_object(
      'ok', false,
      'message', 'This account is currently read-only.'
    );
  end if;

  execute format('select tenant_id from public.%I where id = $1 limit 1', v_table)
  into v_record_tenant_id
  using p_record_id;

  if v_record_tenant_id is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'Record not found.'
    );
  end if;

  if not public.is_ungani_admin() and v_record_tenant_id <> v_tenant_id then
    return jsonb_build_object(
      'ok', false,
      'message', 'You do not have access to delete this record.'
    );
  end if;

  if v_table = 'transactions' then
    select
      coalesce(category_name, category, transaction_type, 'Money record'),
      coalesce(
        transaction_type || ' · KSh ' || to_char(coalesce(amount, 0)::numeric, 'FM999,999,999,999') || ' · ' || coalesce(transaction_date::text, created_at::date::text),
        'Money record'
      )
    into v_record_title, v_record_subtitle
    from public.transactions
    where id = p_record_id
    limit 1;
  elsif v_table = 'tasks' then
    select coalesce(title, task_title, 'Task'), coalesce(status, priority, 'Task record')
    into v_record_title, v_record_subtitle
    from public.tasks
    where id = p_record_id
    limit 1;
  elsif v_table = 'business_items' then
    select coalesce(item_name, name, title, 'Item / Asset'), coalesce(status, item_status, property_status, 'Item record')
    into v_record_title, v_record_subtitle
    from public.business_items
    where id = p_record_id
    limit 1;
  elsif v_table = 'business_records' then
    select coalesce(record_title, title, name, 'Business record'), coalesce(record_type, category, status, 'Business record')
    into v_record_title, v_record_subtitle
    from public.business_records
    where id = p_record_id
    limit 1;
  elsif v_table = 'documents' then
    select coalesce(file_name, document_title, title, 'Document'), coalesce(document_type, file_type, status, 'Document')
    into v_record_title, v_record_subtitle
    from public.documents
    where id = p_record_id
    limit 1;
  elsif v_table = 'support_issues' then
    select coalesce(issue_title, subject, 'Support issue'), coalesce(status, priority, 'Support issue')
    into v_record_title, v_record_subtitle
    from public.support_issues
    where id = p_record_id
    limit 1;
  elsif v_table = 'client_people' then
    select coalesce(full_name, 'Person'), coalesce(status, relationship_status, lead_status, 'Person record')
    into v_record_title, v_record_subtitle
    from public.client_people
    where id = p_record_id
    limit 1;
  elsif v_table = 'business_events' then
    select coalesce(event_title, title, 'Calendar event'), coalesce(status, event_type, 'Calendar event')
    into v_record_title, v_record_subtitle
    from public.business_events
    where id = p_record_id
    limit 1;
  elsif v_table = 'ungani_customer_invoices' then
    select coalesce(invoice_number, 'Customer invoice'), coalesce(customer_name, 'Customer invoice')
    into v_record_title, v_record_subtitle
    from public.ungani_customer_invoices
    where id = p_record_id
    limit 1;
  elsif v_table = 'ungani_quotations' then
    select coalesce(quotation_number, 'Quotation'), coalesce(customer_name, 'Quotation')
    into v_record_title, v_record_subtitle
    from public.ungani_quotations
    where id = p_record_id
    limit 1;
  elsif v_table = 'ungani_orders' then
    select coalesce(order_number, 'Order'), coalesce(customer_name, 'Order')
    into v_record_title, v_record_subtitle
    from public.ungani_orders
    where id = p_record_id
    limit 1;
  end if;

  execute format(
    'update public.%I
     set deleted_at = now(),
         deleted_by = auth.uid(),
         delete_reason = $2
     where id = $1
       and deleted_at is null',
    v_table
  )
  using p_record_id, nullif(trim(coalesce(p_delete_reason, '')), '');

  get diagnostics v_deleted_count = row_count;

  if v_deleted_count = 0 then
    return jsonb_build_object(
      'ok', false,
      'message', 'Record was not deleted. It may already be deleted.'
    );
  end if;

  insert into public.ungani_recently_deleted (
    tenant_id,
    source_table,
    source_record_id,
    table_name,
    record_snapshot,
    delete_reason,
    deleted_by,
    deleted_at,
    recover_until
  )
  values (
    v_record_tenant_id,
    v_table,
    p_record_id,
    v_table,
    jsonb_build_object(
      'title', coalesce(v_record_title, initcap(replace(v_table, '_', ' '))),
      'subtitle', coalesce(v_record_subtitle, 'Deleted record')
    ),
    nullif(trim(coalesce(p_delete_reason, '')), ''),
    auth.uid(),
    now(),
    now() + interval '30 days'
  )
  returning id into v_recently_deleted_id;

  begin
    perform public.log_my_ungani_smart_action(
      'safe_delete',
      'Record safely deleted',
      'A record was moved to Recently Deleted instead of being permanently removed.',
      v_table,
      p_record_id,
      'completed',
      jsonb_build_object(
        'table_name', v_table,
        'record_id', p_record_id,
        'recently_deleted_id', v_recently_deleted_id,
        'delete_reason', p_delete_reason
      )
    );
  exception
    when others then
      null;
  end;

  return jsonb_build_object(
    'ok', true,
    'message', 'Record moved to Recently Deleted.',
    'table_name', v_table,
    'record_id', p_record_id,
    'recently_deleted_id', v_recently_deleted_id
  );
exception
  when others then
    return jsonb_build_object(
      'ok', false,
      'message', sqlerrm
    );
end;
$function$;

-- ============================================================
-- PART F: get_my_ungani_recently_deleted_v2() allowlist addition.
-- Extended from sql/task5-quotations.sql's own body (confirmed live) -
-- only the additions below (table array entry, label, title candidates,
-- and the same combined-title exception invoices/quotations got), every
-- other line is unchanged from that confirmed-run version.
-- ============================================================

CREATE OR REPLACE FUNCTION public.get_my_ungani_recently_deleted_v2(p_limit_each integer DEFAULT 50, p_limit_total integer DEFAULT 200)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid := null;

  v_tables text[] := array[
    'transactions',
    'tasks',
    'business_items',
    'business_records',
    'documents',
    'support_issues',
    'client_people',
    'business_events',
    'ungani_customer_invoices',
    'ungani_quotations',
    'ungani_orders'
  ];

  v_table text;
  v_label text;
  v_title_candidates text[];

  v_table_exists boolean := false;
  v_has_id boolean := false;
  v_has_tenant_id boolean := false;
  v_has_deleted_at boolean := false;
  v_has_restored_at boolean := false;
  v_has_delete_reason boolean := false;
  v_has_deleted_by boolean := false;

  v_title_parts text := null;
  v_title_expr text := null;
  v_reason_expr text := 'null::text';
  v_deleted_by_expr text := 'null::text';
  v_restore_filter text := '';

  v_sql text;
  v_rows jsonb := '[]'::jsonb;
  v_all_rows jsonb := '[]'::jsonb;
  v_sorted_rows jsonb := '[]'::jsonb;
  v_skipped jsonb := '[]'::jsonb;
begin
  v_tenant_id := public.get_my_ungani_current_tenant_id_v16();

  if v_tenant_id is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'No tenant found for this user.',
      'items', '[]'::jsonb,
      'records', '[]'::jsonb
    );
  end if;

  foreach v_table in array v_tables
  loop
    v_label := case v_table
      when 'transactions' then 'Money record'
      when 'tasks' then 'Task'
      when 'business_items' then 'Item / Asset'
      when 'business_records' then 'Business record'
      when 'documents' then 'Document'
      when 'support_issues' then 'Support issue'
      when 'client_people' then 'Person / Contact'
      when 'business_events' then 'Calendar event'
      when 'ungani_customer_invoices' then 'Customer invoice'
      when 'ungani_quotations' then 'Quotation'
      when 'ungani_orders' then 'Order'
      else 'Record'
    end;

    v_title_candidates := case v_table
      when 'transactions' then array[
        'description',
        'transaction_description',
        'transaction_reference',
        'payment_reference',
        'category',
        'category_name',
        'transaction_type'
      ]
      when 'tasks' then array[
        'task_title',
        'title',
        'task_name',
        'name',
        'description',
        'notes'
      ]
      when 'business_items' then array[
        'item_name',
        'asset_name',
        'property_name',
        'stock_name',
        'name',
        'title',
        'description'
      ]
      when 'business_records' then array[
        'record_title',
        'title',
        'record_name',
        'name',
        'description',
        'notes'
      ]
      when 'documents' then array[
        'file_name',
        'document_name',
        'title',
        'name',
        'description'
      ]
      when 'support_issues' then array[
        'issue_title',
        'subject',
        'title',
        'message',
        'description'
      ]
      when 'client_people' then array[
        'full_name',
        'person_name',
        'contact_name',
        'business_name',
        'name',
        'email',
        'phone'
      ]
      when 'business_events' then array[
        'event_title',
        'title',
        'event_name',
        'name',
        'description'
      ]
      when 'ungani_customer_invoices' then array[
        'invoice_number'
      ]
      when 'ungani_quotations' then array[
        'quotation_number'
      ]
      when 'ungani_orders' then array[
        'order_number'
      ]
      else array['title', 'name', 'description']
    end;

    select exists (
      select 1
      from information_schema.tables
      where table_schema = 'public'
        and table_name = v_table
    )
    into v_table_exists;

    if not v_table_exists then
      v_skipped := v_skipped || jsonb_build_array(
        jsonb_build_object(
          'table_name', v_table,
          'reason', 'Table does not exist.'
        )
      );
      continue;
    end if;

    select exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = v_table
        and column_name = 'id'
    )
    into v_has_id;

    select exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = v_table
        and column_name = 'tenant_id'
    )
    into v_has_tenant_id;

    select exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = v_table
        and column_name = 'deleted_at'
    )
    into v_has_deleted_at;

    select exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = v_table
        and column_name = 'restored_at'
    )
    into v_has_restored_at;

    select exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = v_table
        and column_name = 'delete_reason'
    )
    into v_has_delete_reason;

    select exists (
      select 1
      from information_schema.columns
      where table_schema = 'public'
        and table_name = v_table
        and column_name = 'deleted_by'
    )
    into v_has_deleted_by;

    if not (v_has_id and v_has_tenant_id and v_has_deleted_at) then
      v_skipped := v_skipped || jsonb_build_array(
        jsonb_build_object(
          'table_name', v_table,
          'reason', 'Required columns missing.',
          'has_id', v_has_id,
          'has_tenant_id', v_has_tenant_id,
          'has_deleted_at', v_has_deleted_at
        )
      );
      continue;
    end if;

    select string_agg(
      format('nullif(trim(%I::text), '''')', column_name),
      ', '
      order by array_position(v_title_candidates, column_name)
    )
    into v_title_parts
    from information_schema.columns
    where table_schema = 'public'
      and table_name = v_table
      and column_name = any(v_title_candidates);

    if v_title_parts is null or trim(v_title_parts) = '' then
      v_title_expr := format('%L', v_label || ' record');
    else
      v_title_expr := format(
        'coalesce(%s, %L)',
        v_title_parts,
        v_label || ' record'
      );
    end if;

    -- Invoices, quotations, and orders all need their number AND the
    -- customer name to be meaningful in this list - the same deliberate
    -- exception to the generic single-column-priority title above.
    if v_table = 'ungani_customer_invoices' then
      v_title_expr := $ov$coalesce(invoice_number, 'Customer invoice') || coalesce(' · ' || nullif(trim(customer_name), ''), '')$ov$;
    elsif v_table = 'ungani_quotations' then
      v_title_expr := $ov$coalesce(quotation_number, 'Quotation') || coalesce(' · ' || nullif(trim(customer_name), ''), '')$ov$;
    elsif v_table = 'ungani_orders' then
      v_title_expr := $ov$coalesce(order_number, 'Order') || coalesce(' · ' || nullif(trim(customer_name), ''), '')$ov$;
    end if;

    if v_has_delete_reason then
      v_reason_expr := 'delete_reason::text';
    else
      v_reason_expr := 'null::text';
    end if;

    if v_has_deleted_by then
      v_deleted_by_expr := 'deleted_by::text';
    else
      v_deleted_by_expr := 'null::text';
    end if;

    if v_has_restored_at then
      v_restore_filter := 'and restored_at is null';
    else
      v_restore_filter := '';
    end if;

    v_sql := format(
      $f$
        select coalesce(
          jsonb_agg(
            jsonb_build_object(
              'id', x.record_id,
              'record_id', x.record_id,
              'table_name', %L,
              'record_type', %L,
              'title', x.title,
              'delete_reason', x.delete_reason,
              'deleted_by', x.deleted_by,
              'deleted_at', x.deleted_at,
              'restore_rpc', 'restore_my_ungani_deleted_record_v2'
            )
            order by x.deleted_at desc
          ),
          '[]'::jsonb
        )
        from (
          select
            id::text as record_id,
            %s as title,
            %s as delete_reason,
            %s as deleted_by,
            deleted_at
          from public.%I
          where tenant_id = $1
            and deleted_at is not null
            %s
          order by deleted_at desc
          limit $2
        ) x
      $f$,
      v_table,
      v_label,
      v_title_expr,
      v_reason_expr,
      v_deleted_by_expr,
      v_table,
      v_restore_filter
    );

    begin
      execute v_sql
      using v_tenant_id, greatest(1, least(coalesce(p_limit_each, 50), 200))
      into v_rows;

      v_all_rows := v_all_rows || coalesce(v_rows, '[]'::jsonb);
    exception
      when others then
        v_skipped := v_skipped || jsonb_build_array(
          jsonb_build_object(
            'table_name', v_table,
            'reason', sqlerrm
          )
        );
    end;
  end loop;

  begin
    select coalesce(jsonb_agg(value order by (value ->> 'deleted_at')::timestamptz desc), '[]'::jsonb)
    into v_sorted_rows
    from (
      select value
      from jsonb_array_elements(v_all_rows) value
      order by (value ->> 'deleted_at')::timestamptz desc
      limit greatest(1, least(coalesce(p_limit_total, 200), 500))
    ) s;
  exception
    when others then
      v_sorted_rows := v_all_rows;
  end;

  return jsonb_build_object(
    'ok', true,
    'message', 'Recently deleted records loaded.',
    'tenant_id', v_tenant_id,
    'items', v_sorted_rows,
    'records', v_sorted_rows,
    'count', jsonb_array_length(coalesce(v_sorted_rows, '[]'::jsonb)),
    'skipped', v_skipped,
    'loaded_at', now()
  );
exception
  when others then
    return jsonb_build_object(
      'ok', false,
      'message', sqlerrm,
      'items', '[]'::jsonb,
      'records', '[]'::jsonb
    );
end;
$function$;

-- ============================================================
-- VERIFICATION - run and paste back the output.
-- ============================================================

select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name in ('ungani_orders', 'ungani_order_items')
order by table_name, column_name;

select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'tenants' and column_name = 'next_order_number';

select routine_name from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'owner_upsert_ungani_order',
    'update_ungani_order_status',
    'fulfill_ungani_order_item',
    'convert_ungani_order_to_invoice',
    'get_my_ungani_orders',
    'get_ungani_order_detail'
  )
order by routine_name;

select pg_get_functiondef(p.oid) like '%ungani_orders%' as soft_delete_allowlist_updated
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'soft_delete_ungani_record';

select pg_get_functiondef(p.oid) like '%ungani_orders%' as recently_deleted_allowlist_updated
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'get_my_ungani_recently_deleted_v2';
