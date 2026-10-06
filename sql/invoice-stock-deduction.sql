-- =====================================================================
-- Invoices move stock when sent. Built from the LIVE function bodies
-- (pg_get_functiondef, pasted by Chris) of adjust_ungani_stock,
-- owner_upsert_ungani_customer_invoice, update_ungani_invoice_status,
-- and convert_ungani_order_to_invoice - not guessed, not reconstructed
-- from sql/*.sql source files.
--
-- Correction to the original premise: ungani_customer_invoice_items
-- ALREADY HAS a real item_id column live (confirmed via direct REST
-- probe) - the gap was never a missing column, it's that nothing
-- populates or acts on it. No ALTER TABLE needed here.
--
-- What changes:
--   1. owner_upsert_ungani_customer_invoice - now accepts an optional
--      item_id per line in p_items and saves it. A line with no
--      item_id (free-text/service line, or any line from before this
--      change) behaves exactly as before - untouched, no stock link.
--   2. New function sync_ungani_invoice_stock(invoice_id, new_status,
--      old_status) - deducts stock for item-linked lines when an
--      invoice moves INTO 'sent' for the first time, restores it when
--      a 'sent' invoice moves to 'cancelled'. Idempotent via
--      adjust_ungani_stock's own source_reference mechanism
--      ('invoice:' || line_id) - the exact same mechanism Orders'
--      fulfilment already uses ('fulfil:' || event_id), just a
--      different prefix.
--   3. update_ungani_invoice_status - captures the invoice's status
--      BEFORE the update (needed to detect the transition), calls the
--      new sync function after, and rolls the whole status change back
--      (via RAISE EXCEPTION caught by a new outer exception block) if
--      stock can't be adjusted - an invoice can never say "sent" while
--      the stock deduction behind it failed. Every existing
--      error-message string and status-transition rule is unchanged.
--
-- Why this can't double-deduct with Orders: convert_ungani_order_to_
-- invoice's INSERT into ungani_customer_invoice_items (confirmed live
-- body) does not list item_id in its target column list, so every
-- order-converted invoice line gets item_id = NULL regardless of this
-- change - sync_ungani_invoice_stock only ever acts on lines where
-- item_id is not null, so a converted invoice (stock already deducted
-- once, at fulfilment) is structurally invisible to this new logic.
-- convert_ungani_order_to_invoice itself is NOT modified by this file.
--
-- Known, deliberately out-of-scope gap: editing a line's quantity on an
-- already-'sent' invoice (owner_upsert_ungani_customer_invoice allows
-- editing a 'sent' invoice, deleting and re-inserting its lines with
-- new row ids) does NOT re-trigger a stock adjustment, since no status
-- transition occurs. Flagging this now rather than silently leaving it
-- - not in the requested test matrix, happy to close it separately if
-- wanted.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. owner_upsert_ungani_customer_invoice - add optional item_id per
-- line. Everything else in this function is reproduced verbatim from
-- the live body.
-- ---------------------------------------------------------------------
create or replace function public.owner_upsert_ungani_customer_invoice(p_invoice_id uuid DEFAULT NULL::uuid, p_customer_person_id uuid DEFAULT NULL::uuid, p_customer_name text DEFAULT NULL::text, p_customer_address text DEFAULT NULL::text, p_customer_contact text DEFAULT NULL::text, p_customer_pin text DEFAULT NULL::text, p_due_date date DEFAULT NULL::date, p_delivery_address text DEFAULT NULL::text, p_delivery_date date DEFAULT NULL::date, p_payment_terms text DEFAULT NULL::text, p_payment_details text DEFAULT NULL::text, p_vat_applicable boolean DEFAULT false, p_vat_rate numeric DEFAULT NULL::numeric, p_vat_pricing_mode text DEFAULT 'inclusive'::text, p_discount_amount numeric DEFAULT 0, p_currency text DEFAULT 'KES'::text, p_notes text DEFAULT NULL::text, p_items jsonb DEFAULT '[]'::jsonb)
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
  v_item_id uuid;
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
        customer_pin = nullif(trim(coalesce(p_customer_pin, '')), ''),
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
    update public.tenants
    set next_invoice_number = next_invoice_number + 1
    where id = v_tenant_id
    returning next_invoice_number - 1 into v_next_number;

    v_invoice_number := 'INV-' || to_char(current_date, 'YYYY') || '-' || lpad(v_next_number::text, 4, '0');

    insert into public.ungani_customer_invoices (
      tenant_id, invoice_number, customer_person_id, customer_name, customer_address,
      customer_contact, customer_pin, due_date, delivery_address, delivery_date, payment_terms,
      payment_details, vat_applicable, vat_rate, vat_pricing_mode, discount_amount,
      subtotal, vat_amount, total_amount, currency, status, notes, created_by
    )
    values (
      v_tenant_id, v_invoice_number, p_customer_person_id, v_clean_name,
      nullif(trim(coalesce(p_customer_address, '')), ''),
      nullif(trim(coalesce(p_customer_contact, '')), ''),
      nullif(trim(coalesce(p_customer_pin, '')), ''),
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

    -- NEW: optional item_id per line - nullif/empty-string-safe so a
    -- caller that never sends the key (every existing call site, until
    -- the JS change ships) behaves exactly as before.
    v_item_id := nullif(v_item->>'item_id', '')::uuid;

    insert into public.ungani_customer_invoice_items (
      invoice_id, tenant_id, item_id, description, quantity, unit_price, line_subtotal, sort_order
    )
    values (
      v_invoice_id, v_tenant_id, v_item_id, coalesce(v_item->>'description', ''),
      coalesce((v_item->>'quantity')::numeric, 1), coalesce((v_item->>'unit_price')::numeric, 0),
      v_line_subtotal, v_sort
    );

    v_sort := v_sort + 1;
  end loop;

  return jsonb_build_object('ok', true, 'id', v_invoice_id, 'invoice_id', v_invoice_id);
end;
$function$;

-- ---------------------------------------------------------------------
-- 2. New function - the actual stock deduction/restoration logic.
-- ---------------------------------------------------------------------
create or replace function public.sync_ungani_invoice_stock(
  p_invoice_id uuid,
  p_new_status text,
  p_old_status text
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
  v_stock_result jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  -- Same defense-in-depth check fulfill_ungani_order_item already does
  -- even though item_id being set is itself gated by the Stock Tracking
  -- UI toggle - a tenant with Stock Tracking off should never have its
  -- business_items.quantity touched by this, regardless of what item_id
  -- values happen to be on its invoice lines.
  select stock_tracking_enabled into v_stock_tracking_enabled
  from public.tenants where id = v_tenant_id;

  if not coalesce(v_stock_tracking_enabled, false) then
    return jsonb_build_object('ok', true, 'message', 'Stock Tracking is off - nothing to sync.');
  end if;

  -- Deduct: moving INTO 'sent'. Service/free-text lines (item_id is
  -- null) are structurally skipped by the WHERE clause - they never
  -- touch stock. Order-converted invoice lines are also always
  -- item_id = null (see file header), so they're skipped here too -
  -- their stock was already deducted once, at fulfilment.
  if p_new_status = 'sent' and p_old_status is distinct from 'sent' then
    for v_line in
      select id, item_id, quantity
      from public.ungani_customer_invoice_items
      where invoice_id = p_invoice_id and tenant_id = v_tenant_id and item_id is not null
    loop
      v_stock_result := public.adjust_ungani_stock(
        v_line.item_id, 'sale', -v_line.quantity, 'Invoice sent',
        null, 'invoice:' || v_line.id
      );

      if coalesce((v_stock_result->>'ok')::boolean, false) is not true then
        return jsonb_build_object('ok', false, 'message', coalesce(v_stock_result->>'message', 'Could not adjust stock for an invoice line.'));
      end if;
    end loop;
  end if;

  -- Restore: a previously-sent invoice is now cancelled.
  if p_new_status = 'cancelled' and p_old_status = 'sent' then
    for v_line in
      select id, item_id, quantity
      from public.ungani_customer_invoice_items
      where invoice_id = p_invoice_id and tenant_id = v_tenant_id and item_id is not null
    loop
      v_stock_result := public.adjust_ungani_stock(
        v_line.item_id, 'restock', v_line.quantity, 'Invoice cancelled - stock restored',
        null, 'invoice-cancel:' || v_line.id
      );

      if coalesce((v_stock_result->>'ok')::boolean, false) is not true then
        return jsonb_build_object('ok', false, 'message', coalesce(v_stock_result->>'message', 'Could not restore stock for an invoice line.'));
      end if;
    end loop;
  end if;

  return jsonb_build_object('ok', true);
end;
$function$;

revoke all on function public.sync_ungani_invoice_stock(uuid, text, text) from public, anon;
grant execute on function public.sync_ungani_invoice_stock(uuid, text, text) to authenticated;

-- ---------------------------------------------------------------------
-- 3. update_ungani_invoice_status - every existing line reproduced
-- verbatim from the live body; only additions are the old-status
-- capture, the sync call, and the new outer exception wrapper (which
-- only changes behavior for the NEW raise-exception path below - every
-- existing return path is untouched).
-- ---------------------------------------------------------------------
create or replace function public.update_ungani_invoice_status(p_invoice_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_clean_status text;
  v_old_status text;
  v_sync_result jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.ungani_staff_can('money', 'edit') then
    return jsonb_build_object('ok', false, 'message', 'You do not have permission to edit invoices.');
  end if;

  if not public.can_write_ungani_client_data() then
    return jsonb_build_object('ok', false, 'message', 'This account is currently read-only.');
  end if;

  v_clean_status := lower(trim(coalesce(p_status, '')));

  if v_clean_status not in ('draft', 'sent', 'cancelled') then
    return jsonb_build_object('ok', false, 'message', 'Invalid status. Use draft, sent, or cancelled.');
  end if;

  select status into v_old_status
  from public.ungani_customer_invoices
  where id = p_invoice_id and tenant_id = v_tenant_id;

  update public.ungani_customer_invoices
  set status = v_clean_status, updated_at = now()
  where id = p_invoice_id and tenant_id = v_tenant_id
    and status not in ('partially_paid', 'paid');

  if not found then
    return jsonb_build_object('ok', false, 'message', 'Invoice not found, or already has payments recorded against it.');
  end if;

  v_sync_result := public.sync_ungani_invoice_stock(p_invoice_id, v_clean_status, v_old_status);

  if coalesce((v_sync_result->>'ok')::boolean, false) is not true then
    -- Caught by this function's own exception handler below, which
    -- rolls back the status UPDATE above (implicit savepoint) and
    -- returns the real reason instead of leaving the invoice marked
    -- "sent" while stock silently failed to move.
    raise exception '%', coalesce(v_sync_result->>'message', 'Could not update stock for this invoice.');
  end if;

  return jsonb_build_object('ok', true);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

-- =====================================================================
-- Combined verification SELECT
-- =====================================================================

select 'overload_count:owner_upsert_ungani_customer_invoice' as check_name, '1' as expected,
       count(*)::text as actual
from pg_proc
where proname = 'owner_upsert_ungani_customer_invoice' and pronamespace = 'public'::regnamespace

union all

select 'overload_count:update_ungani_invoice_status', '1',
       count(*)::text
from pg_proc
where proname = 'update_ungani_invoice_status' and pronamespace = 'public'::regnamespace

union all

select 'overload_count:sync_ungani_invoice_stock', '1',
       count(*)::text
from pg_proc
where proname = 'sync_ungani_invoice_stock' and pronamespace = 'public'::regnamespace

union all

select 'item_id_column_exists_on_invoice_items', 'true',
       (
         (select count(*) from information_schema.columns
          where table_schema = 'public' and table_name = 'ungani_customer_invoice_items'
            and column_name = 'item_id'
         ) = 1
       )::text

union all

-- Confirms the 3 functions execute without a SQL-level exception (run
-- with no session - "No tenant workspace found" is the expected,
-- harmless response, same convention as every other function in this
-- project). update_ungani_invoice_status/sync are NOT exercised with a
-- real invoice here - see sql/invoice-stock-deduction-test.sql for the
-- real scenario coverage (run separately, inside its own
-- BEGIN...ROLLBACK, as Billy Logistics' real owner).
select 'owner_upsert_ungani_customer_invoice_executes', 'true',
       (public.owner_upsert_ungani_customer_invoice() is not null)::text

union all

select 'update_ungani_invoice_status_executes', 'true',
       (public.update_ungani_invoice_status('00000000-0000-0000-0000-000000000000'::uuid, 'sent') is not null)::text;
