-- ============================================================
-- Stock #1: unify stock-status logic across JS and SQL, and close the
-- JS/SQL default-reorder-level parity gap Chris flagged.
--
-- Problem being fixed:
-- 1. adjust_ungani_stock() and service_adjust_ungani_stock() both only set
--    low_stock=true when the ITEM has an explicit reorder_level - an item
--    relying on any default (the common case) can never show as low stock
--    via these two RPCs, even though the dashboard/Nia would already flag
--    it. Both duplicate the exact same three-line bucketing logic
--    independently.
-- 2. There was no tenant-level default reorder level at all, so the JS
--    side's client.html/nia-assistant.js fallback (a flat 5) and any
--    future SQL fallback would drift the moment a business type needed a
--    different default (a car showroom at qty=1/car needs 0, not 5) -
--    confirmed live: Pwani Motors ("showrooms", business_type_key
--    incorrectly generic per the pending Car Showroom decision) already
--    had 1 item falsely flagged low under a flat-5 assumption.
--
-- Fix: default_reorder_level becomes a real, owner-editable tenants column
-- that is GUARANTEED NON-NULL whenever stock_tracking_enabled is true
-- (enforced by a check constraint, not just application discipline) - so
-- neither JS nor SQL ever needs its own independent fallback constant.
-- The only shared arithmetic left is a single small function,
-- ungani_stock_status(), which ungani-stock-status.js mirrors exactly.
--
-- default_reorder_level is OWNER-EDITABLE (a business setting, same class
-- as the 4 unprotected feature toggles) - it is deliberately NOT part of
-- the tenants protected-column trigger (protect_tenant_admin_only_columns,
-- see ARCHITECTURE.md's security section). Recorded in ARCHITECTURE.md.
-- ============================================================

-- ============================================================
-- PART A: default_reorder_level column, backfill, then constraints
-- (backfill MUST run before the "required when tracking" constraint is
-- added, since Postgres validates a new CHECK against every existing row)
-- ============================================================

alter table public.tenants
  add column if not exists default_reorder_level numeric;

-- Every tenant with stock_tracking_enabled = true today, confirmed live
-- (queried directly, not assumed - Billy Logistics being test-tenant-only
-- doesn't exempt it from this constraint, since the constraint is
-- unconditional on is_test):
--   - Demo Dyar Properties (a29af055-e4f0-48cf-af97-f99081a9106b) - real
--     estate, unique-unit type -> 0
--   - Pwani Motors (4e0d851f-649b-47f8-9fe8-c685474f799e) - "showrooms"
--     business_type, currently miscategorized to business_type_key
--     "general_business" pending the Car Showroom type decision -> 0, per
--     Chris's explicit instruction (a showroom's cars are qty=1 each,
--     same reasoning as every other unique-asset type)
--   - BILLY LOGISTICS (84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11) - engineering
--     test tenant, Logistics & Transport -> 0 (vehicles, unique-asset type)
update public.tenants set default_reorder_level = 0
where id = 'a29af055-e4f0-48cf-af97-f99081a9106b';

update public.tenants set default_reorder_level = 0
where id = '4e0d851f-649b-47f8-9fe8-c685474f799e';

update public.tenants set default_reorder_level = 0
where id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11';

alter table public.tenants drop constraint if exists tenants_default_reorder_level_non_negative;
alter table public.tenants add constraint tenants_default_reorder_level_non_negative
  check (default_reorder_level is null or default_reorder_level >= 0);

-- The core parity guarantee: once tracking is on, there is always a real
-- number here - JS and SQL both read it, neither needs its own fallback.
alter table public.tenants drop constraint if exists tenants_default_reorder_level_required_when_tracking;
alter table public.tenants add constraint tenants_default_reorder_level_required_when_tracking
  check (not stock_tracking_enabled or default_reorder_level is not null);

-- ============================================================
-- PART B: the one shared rule, in SQL. ungani-stock-status.js mirrors this
-- exactly (out_of_stock at qty<=0, low_stock at qty<=effective reorder
-- level, in_stock otherwise). No hardcoded default lives in here at all -
-- callers must resolve item-override-then-tenant-default themselves and
-- pass the final number in, which Part A's constraint guarantees is never
-- null for a tracking tenant.
-- ============================================================

create or replace function public.ungani_stock_status(p_quantity numeric, p_effective_reorder_level numeric)
returns text
language plpgsql
immutable
as $function$
begin
  if p_quantity is null then
    return null;
  end if;

  if p_quantity <= 0 then
    return 'out_of_stock';
  end if;

  if p_effective_reorder_level is not null and p_quantity <= p_effective_reorder_level then
    return 'low_stock';
  end if;

  return 'in_stock';
end;
$function$;

revoke all on function public.ungani_stock_status(numeric, numeric) from public, anon;
grant execute on function public.ungani_stock_status(numeric, numeric) to authenticated, service_role;

-- ============================================================
-- PART C: adjust_ungani_stock - rewritten from the live definition (last
-- touched this session's Phase 2 required-ids migration, confirmed run
-- and verified). ONLY the low-stock computation changes: it now resolves
-- effective reorder level as item override -> tenant default (never both
-- null, per Part A), then calls the shared function instead of
-- reimplementing the bucket logic inline. Everything else (atomicity,
-- idempotent replay, permission checks) is untouched.
-- ============================================================

create or replace function public.adjust_ungani_stock(
  p_item_id uuid,
  p_movement_type text,
  p_quantity_delta numeric,
  p_reason text default null,
  p_reorder_level numeric default null,
  p_source_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_clean_type text;
  v_quantity_before numeric;
  v_quantity_after numeric;
  v_reorder_level numeric;
  v_tenant_default_reorder_level numeric;
  v_effective_reorder_level numeric;
  v_stock_status text;
  v_out_of_stock boolean;
  v_low_stock boolean;
  v_existing record;
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

  select default_reorder_level into v_tenant_default_reorder_level
  from public.tenants where id = v_tenant_id;

  -- Idempotent replay: a retry carrying the same source_reference returns
  -- the original outcome instead of re-applying the change or erroring.
  if p_source_reference is not null then
    select * into v_existing
    from public.ungani_stock_movements
    where tenant_id = v_tenant_id and source_reference = p_source_reference;

    if found then
      return jsonb_build_object(
        'ok', true,
        'message', 'Already recorded (idempotent replay).',
        'quantity', v_existing.quantity_after,
        'replay', true
      );
    end if;
  end if;

  -- Single atomic statement - no prior SELECT, so two concurrent calls
  -- against the same item can never both compute from the same stale
  -- quantity.
  update public.business_items
  set quantity = coalesce(quantity, 0) + p_quantity_delta,
      reorder_level = coalesce(p_reorder_level, reorder_level)
  where id = p_item_id
    and tenant_id = v_tenant_id
    and coalesce(quantity, 0) + p_quantity_delta >= 0
  returning quantity - p_quantity_delta, quantity, reorder_level
  into v_quantity_before, v_quantity_after, v_reorder_level;

  if not found then
    if exists (select 1 from public.business_items where id = p_item_id and tenant_id = v_tenant_id) then
      return jsonb_build_object('ok', false, 'message', 'Not enough stock for this change.');
    else
      return jsonb_build_object('ok', false, 'message', 'Item not found.');
    end if;
  end if;

  begin
    insert into public.ungani_stock_movements (
      tenant_id, item_id, movement_type, quantity_delta, quantity_before, quantity_after, reason, source_reference, created_by
    )
    values (
      v_tenant_id, p_item_id, v_clean_type, p_quantity_delta, v_quantity_before, v_quantity_after,
      nullif(trim(coalesce(p_reason, '')), ''), p_source_reference, auth.uid()
    );
  exception
    when unique_violation then
      update public.business_items
      set quantity = quantity - p_quantity_delta
      where id = p_item_id and tenant_id = v_tenant_id;

      select * into v_existing
      from public.ungani_stock_movements
      where tenant_id = v_tenant_id and source_reference = p_source_reference;

      return jsonb_build_object(
        'ok', true,
        'message', 'Already recorded (idempotent replay).',
        'quantity', v_existing.quantity_after,
        'replay', true
      );
  end;

  v_effective_reorder_level := coalesce(v_reorder_level, v_tenant_default_reorder_level);
  v_stock_status := public.ungani_stock_status(v_quantity_after, v_effective_reorder_level);
  v_out_of_stock := v_stock_status = 'out_of_stock';
  v_low_stock := v_stock_status = 'low_stock';

  return jsonb_build_object(
    'ok', true,
    'message', 'Stock adjusted.',
    'quantity', v_quantity_after,
    'reorder_level', v_reorder_level,
    'effective_reorder_level', v_effective_reorder_level,
    'stock_status', v_stock_status,
    'out_of_stock', v_out_of_stock,
    'low_stock', v_low_stock
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.adjust_ungani_stock(uuid, text, numeric, text, numeric, text) from public, anon;
grant execute on function public.adjust_ungani_stock(uuid, text, numeric, text, numeric, text) to authenticated;

-- ============================================================
-- PART D: service_adjust_ungani_stock - identical fix, service-role path
-- (M-Pesa webhook). No permission checks here, matching the live version -
-- correct, since only service_role can call it.
-- ============================================================

create or replace function public.service_adjust_ungani_stock(
  p_tenant_id uuid,
  p_item_id uuid,
  p_movement_type text,
  p_quantity_delta numeric,
  p_reason text default null,
  p_source_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_quantity_before numeric;
  v_quantity_after numeric;
  v_reorder_level numeric;
  v_tenant_default_reorder_level numeric;
  v_effective_reorder_level numeric;
  v_stock_status text;
  v_existing record;
begin
  if p_movement_type not in ('restock', 'sale', 'adjustment', 'waste') then
    return jsonb_build_object('ok', false, 'message', 'Invalid movement type.');
  end if;

  if p_quantity_delta is null or p_quantity_delta = 0 then
    return jsonb_build_object('ok', false, 'message', 'Quantity delta is required.');
  end if;

  select default_reorder_level into v_tenant_default_reorder_level
  from public.tenants where id = p_tenant_id;

  if p_source_reference is not null then
    select * into v_existing
    from public.ungani_stock_movements
    where tenant_id = p_tenant_id and source_reference = p_source_reference;

    if found then
      return jsonb_build_object(
        'ok', true, 'message', 'Already recorded (idempotent replay).',
        'quantity', v_existing.quantity_after, 'replay', true
      );
    end if;
  end if;

  update public.business_items
  set quantity = coalesce(quantity, 0) + p_quantity_delta
  where id = p_item_id
    and tenant_id = p_tenant_id
    and coalesce(quantity, 0) + p_quantity_delta >= 0
  returning quantity - p_quantity_delta, quantity, reorder_level
  into v_quantity_before, v_quantity_after, v_reorder_level;

  if not found then
    if exists (select 1 from public.business_items where id = p_item_id and tenant_id = p_tenant_id) then
      return jsonb_build_object('ok', false, 'message', 'Not enough stock for this change.');
    else
      return jsonb_build_object('ok', false, 'message', 'Item not found.');
    end if;
  end if;

  begin
    insert into public.ungani_stock_movements (
      tenant_id, item_id, movement_type, quantity_delta, quantity_before, quantity_after, reason, source_reference
    )
    values (
      p_tenant_id, p_item_id, p_movement_type, p_quantity_delta, v_quantity_before, v_quantity_after, p_reason, p_source_reference
    );
  exception
    when unique_violation then
      update public.business_items
      set quantity = quantity - p_quantity_delta
      where id = p_item_id and tenant_id = p_tenant_id;

      select * into v_existing
      from public.ungani_stock_movements
      where tenant_id = p_tenant_id and source_reference = p_source_reference;

      return jsonb_build_object(
        'ok', true, 'message', 'Already recorded (idempotent replay).',
        'quantity', v_existing.quantity_after, 'replay', true
      );
  end;

  v_effective_reorder_level := coalesce(v_reorder_level, v_tenant_default_reorder_level);
  v_stock_status := public.ungani_stock_status(v_quantity_after, v_effective_reorder_level);

  return jsonb_build_object(
    'ok', true, 'message', 'Stock adjusted.', 'quantity', v_quantity_after,
    'reorder_level', v_reorder_level,
    'effective_reorder_level', v_effective_reorder_level,
    'stock_status', v_stock_status,
    'out_of_stock', v_stock_status = 'out_of_stock',
    'low_stock', v_stock_status = 'low_stock'
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.service_adjust_ungani_stock(uuid, uuid, text, numeric, text, text) from public, anon, authenticated;
grant execute on function public.service_adjust_ungani_stock(uuid, uuid, text, numeric, text, text) to service_role;

-- ============================================================
-- PART E: enable_ungani_stock_tracking - now takes a required default
-- reorder level (JS resolves it via ungani-business-config.js's resolve(),
-- the same canonical type resolver used everywhere else in the app, then
-- passes the result here - no business-type keyword matching is
-- duplicated in SQL). Rejects null/negative outright, so a caller can
-- never turn tracking on without also fixing Part A's constraint
-- requirement. If the tenant already has a default_reorder_level set
-- (e.g. re-enabling after a prior disable), that existing value wins -
-- this never clobbers an owner's own prior setting.
--
-- Old zero-arg signature is explicitly dropped (not just replaced) so it
-- can't linger as a stale overload alongside the new one - same class of
-- bug as the old 7-param owner_upsert_ungani_team_member overload.
--
-- Dependency: my-settings.html's saveStockTracking() must be updated to
-- resolve the tenant's type-based default and pass it as
-- p_default_reorder_level before this ships - until then, calling this
-- RPC with no arguments will correctly fail with the message below rather
-- than silently succeeding without a default (fail loud, not silent).
-- ============================================================

drop function if exists public.enable_ungani_stock_tracking();

create or replace function public.enable_ungani_stock_tracking(p_default_reorder_level numeric default null)
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

  if p_default_reorder_level is null or p_default_reorder_level < 0 then
    return jsonb_build_object('ok', false, 'message', 'A default reorder level (0 or greater) is required to enable stock tracking.');
  end if;

  update public.tenants
  set stock_tracking_enabled = true,
      default_reorder_level = coalesce(default_reorder_level, p_default_reorder_level)
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

grant execute on function public.enable_ungani_stock_tracking(numeric) to authenticated;

-- ============================================================
-- Combined verification
-- ============================================================

select 'column:default_reorder_level' as check_name, 'exists' as expected,
       (select count(*)::text from information_schema.columns
        where table_schema = 'public' and table_name = 'tenants' and column_name = 'default_reorder_level')
union all
select 'backfilled_tracking_tenants_non_null', '3',
       (select count(*)::text from public.tenants
        where stock_tracking_enabled = true and default_reorder_level is not null)
union all
select 'backfilled_tracking_tenants_still_null', '0',
       (select count(*)::text from public.tenants
        where stock_tracking_enabled = true and default_reorder_level is null)
union all
select 'demo_dyar_default', '0',
       (select default_reorder_level::text from public.tenants where id = 'a29af055-e4f0-48cf-af97-f99081a9106b')
union all
select 'pwani_motors_default', '0',
       (select default_reorder_level::text from public.tenants where id = '4e0d851f-649b-47f8-9fe8-c685474f799e')
union all
select 'billy_logistics_default', '0',
       (select default_reorder_level::text from public.tenants where id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11')
union all
select 'function:ungani_stock_status', '1',
       (select count(*)::text from pg_proc where proname = 'ungani_stock_status')
union all
select 'function:adjust_ungani_stock_overload_count', '1',
       (select count(*)::text from pg_proc where proname = 'adjust_ungani_stock')
union all
select 'function:service_adjust_ungani_stock_overload_count', '1',
       (select count(*)::text from pg_proc where proname = 'service_adjust_ungani_stock')
union all
select 'function:enable_ungani_stock_tracking_overload_count', '1',
       (select count(*)::text from pg_proc where proname = 'enable_ungani_stock_tracking')
union all
select 'ungani_stock_status_out_of_stock_at_zero', 'out_of_stock',
       public.ungani_stock_status(0, 5)
union all
select 'ungani_stock_status_low_at_threshold', 'low_stock',
       public.ungani_stock_status(5, 5)
union all
select 'ungani_stock_status_in_stock_above_threshold', 'in_stock',
       public.ungani_stock_status(6, 5)
union all
select 'ungani_stock_status_in_stock_when_no_reorder_level', 'in_stock',
       public.ungani_stock_status(1, null);
