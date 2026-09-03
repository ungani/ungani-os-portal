-- Adds p_reorder_level to adjust_ungani_stock() so a tenant can actually
-- set/change an item's reorder threshold from the Adjust Stock modal -
-- without this, reorder_level stays null forever for any business type
-- whose item form never had a custom_fields.reorder_level to backfill
-- from (real estate, logistics, and others), and "Low Stock" could never
-- fire. Drops the old 4-arg signature first since adding a parameter
-- creates a distinct overload in Postgres rather than truly replacing it -
-- leaving both would risk an ambiguous-call error.

drop function if exists public.adjust_ungani_stock(uuid, text, numeric, text);

create or replace function public.adjust_ungani_stock(p_item_id uuid, p_movement_type text, p_quantity_delta numeric, p_reason text default null, p_reorder_level numeric default null)
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
  v_new_reorder_level numeric;
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

grant execute on function public.adjust_ungani_stock(uuid, text, numeric, text, numeric) to authenticated;

-- ============================================================
-- VERIFICATION - run and paste back the output.
-- ============================================================

-- Confirms only the new 5-arg signature exists (old 4-arg one is gone).
select
  p.proname,
  pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'adjust_ungani_stock';
