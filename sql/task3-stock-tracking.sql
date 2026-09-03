-- Task 3: Stock/quantity tracking (toggle-based module, off by default).
--
-- Repurposes two existing, confirmed-dead columns on business_items
-- (quantity numeric default 0, reorder_level numeric nullable - both
-- verified via information_schema to have zero references anywhere in
-- the live app) as the authoritative tracked values once a tenant opts
-- in. No new columns added to business_items. quantity_available/
-- quantity_on_hand are left untouched and still unused - one concept
-- doesn't need three columns.
--
-- Until a tenant enables tracking, nothing changes for them: item forms
-- keep reading/writing custom_fields.stock_quantity /
-- custom_fields.reorder_level exactly as today.

alter table public.tenants
  add column if not exists stock_tracking_enabled boolean not null default false;

create table if not exists public.ungani_stock_movements (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  item_id uuid not null references public.business_items(id),
  movement_type text not null check (movement_type in ('restock', 'sale', 'adjustment', 'waste')),
  quantity_delta numeric not null,
  quantity_before numeric not null,
  quantity_after numeric not null,
  reason text,
  created_by uuid,
  created_at timestamptz not null default now()
);

create index if not exists idx_ungani_stock_movements_tenant on public.ungani_stock_movements(tenant_id);
create index if not exists idx_ungani_stock_movements_item on public.ungani_stock_movements(item_id);

alter table public.ungani_stock_movements enable row level security;

drop policy if exists "ungani_stock_movements_select_own_tenant" on public.ungani_stock_movements;
create policy "ungani_stock_movements_select_own_tenant" on public.ungani_stock_movements
  for select
  using (tenant_id = public.get_my_ungani_tenant_id());

grant select on public.ungani_stock_movements to authenticated;

-- Turns tracking on for the caller's tenant, then backfills quantity/
-- reorder_level from custom_fields for items that haven't been touched
-- yet (quantity still at its untouched default of 0, reorder_level still
-- null) - so re-enabling later can never clobber real tracked data.
create or replace function public.enable_ungani_stock_tracking()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_backfilled_count integer := 0;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.can_write_ungani_client_data() then
    return jsonb_build_object('ok', false, 'message', 'This account is currently read-only.');
  end if;

  update public.tenants
  set stock_tracking_enabled = true
  where id = v_tenant_id;

  update public.business_items
  set quantity = nullif(custom_fields->>'stock_quantity', '')::numeric
  where tenant_id = v_tenant_id
    and quantity = 0
    and nullif(custom_fields->>'stock_quantity', '') is not null
    and nullif(custom_fields->>'stock_quantity', '')::numeric > 0;

  get diagnostics v_backfilled_count = row_count;

  update public.business_items
  set reorder_level = nullif(custom_fields->>'reorder_level', '')::numeric
  where tenant_id = v_tenant_id
    and reorder_level is null
    and nullif(custom_fields->>'reorder_level', '') is not null;

  return jsonb_build_object('ok', true, 'message', 'Stock tracking enabled.', 'items_backfilled', v_backfilled_count);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

grant execute on function public.enable_ungani_stock_tracking() to authenticated;

-- Turns tracking off. Does not touch data - quantity/reorder_level just
-- stop being the active source; the item form reverts to editing
-- custom_fields again.
create or replace function public.disable_ungani_stock_tracking()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.can_write_ungani_client_data() then
    return jsonb_build_object('ok', false, 'message', 'This account is currently read-only.');
  end if;

  update public.tenants
  set stock_tracking_enabled = false
  where id = v_tenant_id;

  return jsonb_build_object('ok', true, 'message', 'Stock tracking disabled.');
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

grant execute on function public.disable_ungani_stock_tracking() to authenticated;

-- The only place quantity can move once tracking is on: validates the
-- item belongs to the caller's tenant, blocks going negative, updates
-- business_items.quantity and logs the movement atomically.
create or replace function public.adjust_ungani_stock(p_item_id uuid, p_movement_type text, p_quantity_delta numeric, p_reason text default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_item record;
  v_clean_type text;
  v_new_quantity numeric;
  v_low_stock boolean;
  v_out_of_stock boolean;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
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

  update public.business_items
  set quantity = v_new_quantity
  where id = p_item_id;

  insert into public.ungani_stock_movements (
    tenant_id, item_id, movement_type, quantity_delta, quantity_before, quantity_after, reason, created_by
  )
  values (
    v_tenant_id, p_item_id, v_clean_type, p_quantity_delta, coalesce(v_item.quantity, 0), v_new_quantity,
    nullif(trim(coalesce(p_reason, '')), ''), auth.uid()
  );

  v_out_of_stock := v_new_quantity = 0;
  v_low_stock := (not v_out_of_stock) and v_item.reorder_level is not null and v_new_quantity <= v_item.reorder_level;

  return jsonb_build_object(
    'ok', true,
    'message', 'Stock adjusted.',
    'quantity', v_new_quantity,
    'out_of_stock', v_out_of_stock,
    'low_stock', v_low_stock
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

grant execute on function public.adjust_ungani_stock(uuid, text, numeric, text) to authenticated;

-- Movement history - either one item's (drill-down) or the whole
-- tenant's (module-wide log), most recent first.
create or replace function public.get_my_ungani_stock_movements(p_item_id uuid default null, p_limit integer default 100)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_movements jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', x.id,
      'item_id', x.item_id,
      'item_name', x.item_name,
      'movement_type', x.movement_type,
      'quantity_delta', x.quantity_delta,
      'quantity_before', x.quantity_before,
      'quantity_after', x.quantity_after,
      'reason', x.reason,
      'created_at', x.created_at
    )
    order by x.created_at desc
  ), '[]'::jsonb)
  into v_movements
  from (
    select
      m.id, m.item_id, m.movement_type, m.quantity_delta, m.quantity_before, m.quantity_after,
      m.reason, m.created_at,
      coalesce(bi.item_name, bi.name, bi.title, bi.property_name, 'Item') as item_name
    from public.ungani_stock_movements m
    left join public.business_items bi on bi.id = m.item_id
    where m.tenant_id = v_tenant_id
      and (p_item_id is null or m.item_id = p_item_id)
    order by m.created_at desc
    limit greatest(1, least(coalesce(p_limit, 100), 500))
  ) x;

  return jsonb_build_object('ok', true, 'movements', v_movements);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm, 'movements', '[]'::jsonb);
end;
$function$;

grant execute on function public.get_my_ungani_stock_movements(uuid, integer) to authenticated;

-- ============================================================
-- VERIFICATION - run and paste back the output.
-- ============================================================

select column_name, data_type, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'tenants' and column_name = 'stock_tracking_enabled';

select table_name from information_schema.tables
where table_schema = 'public' and table_name = 'ungani_stock_movements';

select policyname, cmd from pg_policies
where schemaname = 'public' and tablename = 'ungani_stock_movements';

select routine_name from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'enable_ungani_stock_tracking',
    'disable_ungani_stock_tracking',
    'adjust_ungani_stock',
    'get_my_ungani_stock_movements'
  )
order by routine_name;
