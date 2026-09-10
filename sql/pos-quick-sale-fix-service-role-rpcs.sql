-- Real gap found live-testing the M-Pesa success callback: adjust_ungani_stock()
-- and record_ungani_invoice_payment() both resolve their tenant via
-- get_my_ungani_tenant_id(), which depends on auth.uid() - that's null
-- for the service-role client the M-Pesa callback runs as (a real
-- Safaricom webhook, no user session at all). Both calls were failing
-- closed with "No tenant workspace found," which my own error-handling
-- misread as a genuine stock shortfall, and the payment RPC's failure
-- was silently swallowed (called via `perform`, result never checked) -
-- so the invoice never got marked paid at all.
--
-- Fix: new service-role-ONLY variants that take an explicit p_tenant_id
-- instead of deriving it from auth.uid(). Mirrors each real function's
-- logic exactly (verified against their live bodies pulled earlier this
-- session) - the only change is the tenant source and the removal of
-- the owner/read-only permission checks, since those don't apply to a
-- trusted server-to-server webhook (which is already gated by matching
-- a real, previously-created pending transaction's checkout_request_id).
-- Explicitly revoked from authenticated/public so these can never be
-- called by a regular client, only from server code holding the
-- service-role key.

create or replace function public.service_adjust_ungani_stock(
  p_tenant_id uuid,
  p_item_id uuid,
  p_movement_type text,
  p_quantity_delta numeric,
  p_reason text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_item record;
  v_new_quantity numeric;
begin
  if p_movement_type not in ('restock', 'sale', 'adjustment', 'waste') then
    return jsonb_build_object('ok', false, 'message', 'Invalid movement type.');
  end if;

  if p_quantity_delta is null or p_quantity_delta = 0 then
    return jsonb_build_object('ok', false, 'message', 'Quantity delta is required.');
  end if;

  select * into v_item
  from public.business_items
  where id = p_item_id and tenant_id = p_tenant_id;

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
    tenant_id, item_id, movement_type, quantity_delta, quantity_before, quantity_after, reason
  )
  values (
    p_tenant_id, p_item_id, p_movement_type, p_quantity_delta, coalesce(v_item.quantity, 0), v_new_quantity, p_reason
  );

  return jsonb_build_object(
    'ok', true, 'message', 'Stock adjusted.', 'quantity', v_new_quantity,
    'reorder_level', v_item.reorder_level,
    'out_of_stock', v_new_quantity = 0,
    'low_stock', v_item.reorder_level is not null and v_new_quantity <= v_item.reorder_level
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.service_adjust_ungani_stock(uuid, uuid, text, numeric, text) from public, authenticated;
grant execute on function public.service_adjust_ungani_stock(uuid, uuid, text, numeric, text) to service_role;

create or replace function public.service_record_ungani_invoice_payment(
  p_tenant_id uuid,
  p_invoice_id uuid,
  p_amount numeric,
  p_paid_at date default current_date,
  p_method text default null,
  p_reference text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_invoice record;
  v_new_paid numeric;
  v_new_status text;
begin
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object('ok', false, 'message', 'Payment amount must be greater than zero.');
  end if;

  select * into v_invoice
  from public.ungani_customer_invoices
  where id = p_invoice_id and tenant_id = p_tenant_id;

  if v_invoice.id is null then
    return jsonb_build_object('ok', false, 'message', 'Invoice not found.');
  end if;

  if v_invoice.status = 'cancelled' then
    return jsonb_build_object('ok', false, 'message', 'Cannot record a payment against a cancelled invoice.');
  end if;

  insert into public.ungani_customer_invoice_payments (
    invoice_id, tenant_id, amount, paid_at, method, reference, notes
  )
  values (
    p_invoice_id, p_tenant_id, p_amount, coalesce(p_paid_at, current_date), p_method, p_reference, p_notes
  );

  v_new_paid := v_invoice.amount_paid + p_amount;
  v_new_status := case
    when v_new_paid >= v_invoice.total_amount then 'paid'
    when v_new_paid > 0 then 'partially_paid'
    else v_invoice.status
  end;

  update public.ungani_customer_invoices
  set amount_paid = v_new_paid, status = v_new_status, updated_at = now()
  where id = p_invoice_id;

  return jsonb_build_object('ok', true, 'amount_paid', v_new_paid, 'status', v_new_status);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.service_record_ungani_invoice_payment(uuid, uuid, numeric, date, text, text, text) from public, authenticated;
grant execute on function public.service_record_ungani_invoice_payment(uuid, uuid, numeric, date, text, text, text) to service_role;

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================

select proname, pg_get_function_identity_arguments(oid) as args
from pg_proc
where proname in ('service_adjust_ungani_stock', 'service_record_ungani_invoice_payment')
  and pronamespace = 'public'::regnamespace
order by proname;

select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name in ('service_adjust_ungani_stock', 'service_record_ungani_invoice_payment')
order by routine_name, grantee;
