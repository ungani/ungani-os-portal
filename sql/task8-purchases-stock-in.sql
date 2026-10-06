-- =====================================================================
-- Task 8: Purchase / Stock-in feature.
--
-- Mirrors the confirmed-live owner_upsert_ungani_customer_invoice shape
-- (pasted by the user via pg_get_functiondef, not guessed) for the
-- purchase document itself: tenant_id resolution, p_purchase_id-present
-- means edit, jsonb items array, next_purchase_number counter exactly
-- like next_invoice_number, item_id optional per line via the same
-- nullif(...,'')::uuid pattern. The confirmed-live adjust_ungani_stock
-- body is reused UNCHANGED (called, not modified) for every stock
-- movement here - its own internal ungani_staff_can('items','edit') +
-- can_write_ungani_client_data() gate and idempotent source_reference
-- replay protection both apply automatically to every restock/reversal
-- this file triggers.
--
-- Status model (mirrors invoice draft/sent/cancelled, substituting
-- "received" for "sent" since a purchase has no customer-facing send
-- step): draft (created, no stock/money effect) -> received (stock up
-- per item-linked line, one payable transaction for the total) ->
-- cancelled (from draft: no-op; from received: stock reversed, the
-- linked transaction soft-deleted). update_ungani_purchase_status()
-- carries its own explicit ungani_staff_can/can_write_ungani_client_data
-- gate (not just relying on the embedded adjust_ungani_stock calls),
-- because a purchase with only service/non-stock lines (item_id null
-- throughout) would otherwise flip status with zero permission check.
--
-- Money side: the linked transactions row is only written for
-- currency = 'KES', explicitly skipped otherwise - the exact same
-- documented gap record_ungani_invoice_payment already has for non-KES
-- invoices, not a new limitation introduced here. transactions.status
-- is deliberately left to its column default (not guessed) since its
-- real allowed values were not confirmed live - if the verification
-- block below fails on this, that will show as a clear error to fix,
-- not a silent wrong value.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Purchase numbering counter - mirrors tenants.next_invoice_number.
-- ---------------------------------------------------------------------
alter table public.tenants add column if not exists next_purchase_number integer not null default 1;

-- ---------------------------------------------------------------------
-- 2. ungani_purchases - mirrors ungani_customer_invoices' shape with
-- supplier_* replacing customer_*.
-- ---------------------------------------------------------------------
create table if not exists public.ungani_purchases (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  purchase_number text not null,
  supplier_person_id uuid references public.client_people(id),
  supplier_name text not null,
  purchase_date date not null default current_date,
  status text not null default 'draft' check (status in ('draft', 'received', 'cancelled')),
  vat_applicable boolean not null default false,
  vat_rate numeric,
  vat_pricing_mode text not null default 'exclusive' check (vat_pricing_mode in ('inclusive', 'exclusive')),
  subtotal numeric not null default 0,
  vat_amount numeric not null default 0,
  total_amount numeric not null default 0,
  currency text not null default 'KES',
  notes text,
  related_transaction_id uuid,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz
);

create table if not exists public.ungani_purchase_items (
  id uuid primary key default gen_random_uuid(),
  purchase_id uuid not null references public.ungani_purchases(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id),
  item_id uuid references public.business_items(id),
  description text not null,
  quantity numeric not null default 1,
  unit_cost numeric not null default 0,
  line_subtotal numeric not null default 0,
  sort_order integer not null default 0
);

-- Same "Related X" linking pattern as transactions.related_invoice_id -
-- confirmed live column, new related_purchase_id mirrors it exactly.
alter table public.transactions add column if not exists related_purchase_id uuid references public.ungani_purchases(id);

-- ---------------------------------------------------------------------
-- 3. RLS - standard tenant-isolation pattern used across the app
-- (tenant_id = get_my_ungani_tenant_id(), admin bypass via is_ungani_admin()).
-- ---------------------------------------------------------------------
alter table public.ungani_purchases enable row level security;
alter table public.ungani_purchase_items enable row level security;

drop policy if exists ungani_purchases_select on public.ungani_purchases;
create policy ungani_purchases_select on public.ungani_purchases
  for select using (tenant_id = public.get_my_ungani_tenant_id() or public.is_ungani_admin());

drop policy if exists ungani_purchases_insert on public.ungani_purchases;
create policy ungani_purchases_insert on public.ungani_purchases
  for insert with check (tenant_id = public.get_my_ungani_tenant_id());

drop policy if exists ungani_purchases_update on public.ungani_purchases;
create policy ungani_purchases_update on public.ungani_purchases
  for update using (tenant_id = public.get_my_ungani_tenant_id() or public.is_ungani_admin());

drop policy if exists ungani_purchase_items_select on public.ungani_purchase_items;
create policy ungani_purchase_items_select on public.ungani_purchase_items
  for select using (tenant_id = public.get_my_ungani_tenant_id() or public.is_ungani_admin());

drop policy if exists ungani_purchase_items_insert on public.ungani_purchase_items;
create policy ungani_purchase_items_insert on public.ungani_purchase_items
  for insert with check (tenant_id = public.get_my_ungani_tenant_id());

drop policy if exists ungani_purchase_items_update on public.ungani_purchase_items;
create policy ungani_purchase_items_update on public.ungani_purchase_items
  for update using (tenant_id = public.get_my_ungani_tenant_id() or public.is_ungani_admin());

drop policy if exists ungani_purchase_items_delete on public.ungani_purchase_items;
create policy ungani_purchase_items_delete on public.ungani_purchase_items
  for delete using (tenant_id = public.get_my_ungani_tenant_id() or public.is_ungani_admin());

-- Direct table grants (the client lists purchases via a plain .from()
-- select, same as my-orders.html/my-quotations.html do for their own
-- tables - not every read needs a dedicated RPC) + service_role, since
-- missing service_role grants have been the single most repeated bug
-- class this project has hit (4x previously).
grant select, insert, update on public.ungani_purchases to authenticated;
grant select, insert, update, delete on public.ungani_purchase_items to authenticated;
grant all on public.ungani_purchases to service_role;
grant all on public.ungani_purchase_items to service_role;

-- ---------------------------------------------------------------------
-- 4. owner_upsert_ungani_purchase - structurally identical to the
-- confirmed-live owner_upsert_ungani_customer_invoice: no staff-
-- permission gate at this level (matching that function's own real
-- body exactly - it only resolves tenant_id and validates the name),
-- because this step alone never touches stock or money; only
-- update_ungani_purchase_status() below does, and that one carries its
-- own explicit gate.
-- ---------------------------------------------------------------------
create or replace function public.owner_upsert_ungani_purchase(
  p_purchase_id uuid default null,
  p_supplier_person_id uuid default null,
  p_supplier_name text default null,
  p_purchase_date date default current_date,
  p_vat_applicable boolean default false,
  p_vat_rate numeric default null,
  p_vat_pricing_mode text default 'exclusive',
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
  v_purchase_id uuid;
  v_purchase_number text;
  v_next_number integer;
  v_subtotal numeric := 0;
  v_vat_amount numeric := 0;
  v_total numeric := 0;
  v_clean_name text;
  v_item jsonb;
  v_line_subtotal numeric;
  v_sort integer := 0;
  v_existing_status text;
  v_item_id uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  v_clean_name := nullif(trim(coalesce(p_supplier_name, '')), '');

  if v_clean_name is null then
    return jsonb_build_object('ok', false, 'message', 'Supplier name is required.');
  end if;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_line_subtotal := coalesce((v_item->>'quantity')::numeric, 1) * coalesce((v_item->>'unit_cost')::numeric, 0);
    v_subtotal := v_subtotal + v_line_subtotal;
  end loop;

  if p_vat_applicable and p_vat_rate is not null and p_vat_rate > 0 then
    if p_vat_pricing_mode = 'inclusive' then
      v_vat_amount := round(v_subtotal * p_vat_rate / (100 + p_vat_rate), 2);
      v_total := v_subtotal;
    else
      v_vat_amount := round(v_subtotal * p_vat_rate / 100, 2);
      v_total := round(v_subtotal + v_vat_amount, 2);
    end if;
  else
    v_vat_amount := 0;
    v_total := v_subtotal;
  end if;

  if p_purchase_id is not null then
    select status into v_existing_status
    from public.ungani_purchases
    where id = p_purchase_id and tenant_id = v_tenant_id;

    if v_existing_status is null then
      return jsonb_build_object('ok', false, 'message', 'Purchase not found.');
    end if;

    if v_existing_status <> 'draft' then
      return jsonb_build_object('ok', false, 'message', 'Only draft purchases can be edited.');
    end if;

    update public.ungani_purchases
    set supplier_person_id = p_supplier_person_id,
        supplier_name = v_clean_name,
        purchase_date = coalesce(p_purchase_date, purchase_date),
        vat_applicable = coalesce(p_vat_applicable, false),
        vat_rate = p_vat_rate,
        vat_pricing_mode = coalesce(p_vat_pricing_mode, 'exclusive'),
        subtotal = v_subtotal,
        vat_amount = v_vat_amount,
        total_amount = v_total,
        currency = coalesce(p_currency, 'KES'),
        notes = nullif(trim(coalesce(p_notes, '')), ''),
        updated_at = now()
    where id = p_purchase_id and tenant_id = v_tenant_id
    returning id into v_purchase_id;

    delete from public.ungani_purchase_items where purchase_id = v_purchase_id;
  else
    update public.tenants
    set next_purchase_number = next_purchase_number + 1
    where id = v_tenant_id
    returning next_purchase_number - 1 into v_next_number;

    v_purchase_number := 'PO-' || to_char(current_date, 'YYYY') || '-' || lpad(v_next_number::text, 4, '0');

    insert into public.ungani_purchases (
      tenant_id, purchase_number, supplier_person_id, supplier_name, purchase_date,
      vat_applicable, vat_rate, vat_pricing_mode, subtotal, vat_amount, total_amount,
      currency, status, notes, created_by
    )
    values (
      v_tenant_id, v_purchase_number, p_supplier_person_id, v_clean_name,
      coalesce(p_purchase_date, current_date),
      coalesce(p_vat_applicable, false), p_vat_rate, coalesce(p_vat_pricing_mode, 'exclusive'),
      v_subtotal, v_vat_amount, v_total, coalesce(p_currency, 'KES'), 'draft',
      nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
    )
    returning id into v_purchase_id;
  end if;

  v_sort := 0;

  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_line_subtotal := coalesce((v_item->>'quantity')::numeric, 1) * coalesce((v_item->>'unit_cost')::numeric, 0);
    v_item_id := nullif(v_item->>'item_id', '')::uuid;

    insert into public.ungani_purchase_items (
      purchase_id, tenant_id, item_id, description, quantity, unit_cost, line_subtotal, sort_order
    )
    values (
      v_purchase_id, v_tenant_id, v_item_id, coalesce(v_item->>'description', ''),
      coalesce((v_item->>'quantity')::numeric, 1), coalesce((v_item->>'unit_cost')::numeric, 0),
      v_line_subtotal, v_sort
    );

    v_sort := v_sort + 1;
  end loop;

  return jsonb_build_object('ok', true, 'id', v_purchase_id, 'purchase_id', v_purchase_id, 'purchase_number', v_purchase_number);
end;
$function$;

grant execute on function public.owner_upsert_ungani_purchase(uuid, uuid, text, date, boolean, numeric, text, text, text, jsonb) to authenticated;

-- ---------------------------------------------------------------------
-- 5. update_ungani_purchase_status - the only function that moves
-- stock or money. Explicit top-level gate (same two checks
-- adjust_ungani_stock itself uses, confirmed live) because a purchase
-- made entirely of service/non-stock lines (item_id null throughout)
-- would otherwise never call adjust_ungani_stock at all and so would
-- never inherit its gate.
-- ---------------------------------------------------------------------
create or replace function public.update_ungani_purchase_status(p_purchase_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_old_status text;
  v_purchase record;
  v_line record;
  v_stock_result jsonb;
  v_transaction_id uuid;
  v_clean_status text;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.ungani_staff_can('items', 'edit') then
    return jsonb_build_object('ok', false, 'message', 'You do not have permission to update purchases.');
  end if;

  if not public.can_write_ungani_client_data() then
    return jsonb_build_object('ok', false, 'message', 'This account is currently read-only.');
  end if;

  v_clean_status := lower(trim(coalesce(p_status, '')));

  if v_clean_status not in ('draft', 'received', 'cancelled') then
    return jsonb_build_object('ok', false, 'message', 'Invalid status. Use draft, received, or cancelled.');
  end if;

  select * into v_purchase
  from public.ungani_purchases
  where id = p_purchase_id and tenant_id = v_tenant_id;

  if v_purchase.id is null then
    return jsonb_build_object('ok', false, 'message', 'Purchase not found.');
  end if;

  v_old_status := v_purchase.status;

  if v_old_status = v_clean_status then
    return jsonb_build_object('ok', true, 'message', 'No change.', 'status', v_old_status);
  end if;

  -- draft -> received: restock every item-linked line, write one
  -- payable expense transaction for the total.
  if v_old_status = 'draft' and v_clean_status = 'received' then
    for v_line in
      select * from public.ungani_purchase_items where purchase_id = p_purchase_id
    loop
      if v_line.item_id is not null then
        v_stock_result := public.adjust_ungani_stock(
          v_line.item_id, 'restock', v_line.quantity,
          'Purchase ' || v_purchase.purchase_number,
          null,
          'purchase-receive:' || v_line.id::text
        );

        if coalesce((v_stock_result->>'ok')::boolean, false) is not true then
          return jsonb_build_object('ok', false, 'message', 'Stock update failed: ' || coalesce(v_stock_result->>'message', 'unknown error'));
        end if;
      end if;
    end loop;

    if v_purchase.currency = 'KES' then
      insert into public.transactions (
        tenant_id, transaction_type, amount, amount_kes, currency, category, category_name,
        description, transaction_date, related_person_id, related_purchase_id,
        vat_applicable, vat_rate, vat_amount, vat_pricing_mode, created_by
      )
      values (
        v_tenant_id, 'expense', v_purchase.total_amount, v_purchase.total_amount, v_purchase.currency,
        'Purchases', 'Stock Purchase',
        'Purchase ' || v_purchase.purchase_number || ' - ' || v_purchase.supplier_name,
        v_purchase.purchase_date, v_purchase.supplier_person_id, p_purchase_id,
        v_purchase.vat_applicable, v_purchase.vat_rate, v_purchase.vat_amount, v_purchase.vat_pricing_mode,
        auth.uid()
      )
      returning id into v_transaction_id;

      update public.ungani_purchases set related_transaction_id = v_transaction_id where id = p_purchase_id;
    end if;

    update public.ungani_purchases set status = 'received', updated_at = now() where id = p_purchase_id;

    return jsonb_build_object('ok', true, 'message', 'Purchase received - stock updated.', 'status', 'received');
  end if;

  -- draft -> cancelled: never received, so nothing to reverse.
  if v_old_status = 'draft' and v_clean_status = 'cancelled' then
    update public.ungani_purchases set status = 'cancelled', updated_at = now() where id = p_purchase_id;
    return jsonb_build_object('ok', true, 'message', 'Purchase cancelled.', 'status', 'cancelled');
  end if;

  -- received -> cancelled: reverse every item-linked line's stock,
  -- soft-delete the linked transaction so the payable/expense is gone.
  if v_old_status = 'received' and v_clean_status = 'cancelled' then
    for v_line in
      select * from public.ungani_purchase_items where purchase_id = p_purchase_id
    loop
      if v_line.item_id is not null then
        v_stock_result := public.adjust_ungani_stock(
          v_line.item_id, 'adjustment', -v_line.quantity,
          'Purchase ' || v_purchase.purchase_number || ' cancelled',
          null,
          'purchase-cancel:' || v_line.id::text
        );

        if coalesce((v_stock_result->>'ok')::boolean, false) is not true then
          return jsonb_build_object('ok', false, 'message', 'Stock reversal failed: ' || coalesce(v_stock_result->>'message', 'unknown error'));
        end if;
      end if;
    end loop;

    if v_purchase.related_transaction_id is not null then
      update public.transactions set deleted_at = now() where id = v_purchase.related_transaction_id;
    end if;

    update public.ungani_purchases set status = 'cancelled', updated_at = now() where id = p_purchase_id;

    return jsonb_build_object('ok', true, 'message', 'Purchase cancelled - stock and expense reversed.', 'status', 'cancelled');
  end if;

  return jsonb_build_object('ok', false, 'message', 'Cannot change status from ' || v_old_status || ' to ' || v_clean_status || '.');
end;
$function$;

grant execute on function public.update_ungani_purchase_status(uuid, text) to authenticated;

-- =====================================================================
-- Combined verification SELECT
-- =====================================================================

select 'table_exists:ungani_purchases' as check_name, 'true' as expected,
       (to_regclass('public.ungani_purchases') is not null)::text as actual

union all

select 'table_exists:ungani_purchase_items', 'true',
       (to_regclass('public.ungani_purchase_items') is not null)::text

union all

select 'column_exists:tenants.next_purchase_number', 'true',
       (exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'tenants' and column_name = 'next_purchase_number'))::text

union all

select 'column_exists:transactions.related_purchase_id', 'true',
       (exists (select 1 from information_schema.columns where table_schema = 'public' and table_name = 'transactions' and column_name = 'related_purchase_id'))::text

union all

select 'overload_count:owner_upsert_ungani_purchase', '1',
       (select count(*)::text from pg_proc where proname = 'owner_upsert_ungani_purchase' and pronamespace = 'public'::regnamespace)

union all

select 'overload_count:update_ungani_purchase_status', '1',
       (select count(*)::text from pg_proc where proname = 'update_ungani_purchase_status' and pronamespace = 'public'::regnamespace)

union all

select 'rls_enabled:ungani_purchases', 'true',
       (select relrowsecurity::text from pg_class where relname = 'ungani_purchases' and relnamespace = 'public'::regnamespace)

union all

select 'rls_enabled:ungani_purchase_items', 'true',
       (select relrowsecurity::text from pg_class where relname = 'ungani_purchase_items' and relnamespace = 'public'::regnamespace);
