-- POS <-> M-Pesa reconciliation feature, plus a prerequisite bug fix found
-- while investigating it.
--
-- BUG FOUND: a POS sale paid via the M-Pesa STK button correctly deducts
-- stock and marks the invoice paid (api/mpesa-stk-push.js's STK callback),
-- but service_record_ungani_invoice_payment() never wrote a `transactions`
-- row - only the owner-facing record_ungani_invoice_payment() (used by the
-- cash path) had the Money-sync block added in
-- connect-invoice-payments-to-money.sql. Every POS M-Pesa sale has been
-- invisible in Money/reports since that feature shipped. Fixed below by
-- mirroring the exact same Money-sync block into the service-role variant.
--
-- NEW: a third POS payment option, "Already Paid (M-Pesa)", for the real
-- walk-in scenario - a customer sends money directly to the tenant's own
-- connected Paybill (captured by this week's passive C2B webhook) rather
-- than through a merchant-initiated STK prompt. This settles the sale
-- immediately like cash (real stock deduction, real transactions row)
-- without ever calling Daraja.
--
-- NEW: owner_get_ungani_pos_mpesa_reconciliation(p_date) - compares the
-- day's passive C2B M-Pesa total against the day's total recorded POS
-- sales (any payment method), and lists any individual C2B payment with
-- no same-day POS sale of the identical amount as "unmatched - investigate."
-- This is a same-day/same-amount heuristic, not a precise match (Safaricom
-- sends no item/invoice reference at all) - documented as a best-effort
-- signal, not proof, in both the RPC comment and the UI copy.

-- ============================================================
-- PART A: fix service_record_ungani_invoice_payment - add the same
-- Money-sync block record_ungani_invoice_payment already has
-- (connect-invoice-payments-to-money.sql:58-171), swapping
-- get_my_ungani_tenant_id()/auth.uid() for the explicit p_tenant_id this
-- service-role variant already takes, and created_by left null (no real
-- user session exists for a Safaricom webhook). Everything else is
-- byte-for-byte the same as the live version
-- (pos-quick-sale-fix-service-role-rpcs.sql:86-144).
-- ============================================================

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
  v_payment_id uuid;
  v_transaction_id uuid;
  v_vat_for_payment numeric := 0;
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
      p_tenant_id, 'income', p_amount, 'KES', p_amount,
      'paid', p_method, p_reference, coalesce(p_paid_at, current_date),
      'Invoice Payment',
      'Payment for Invoice ' || v_invoice.invoice_number,
      'Customer: ' || v_invoice.customer_name,
      v_invoice.vat_applicable, v_invoice.vat_rate, v_vat_for_payment, v_vat_for_payment, v_invoice.vat_pricing_mode,
      v_invoice.customer_person_id, p_invoice_id, v_payment_id,
      null
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
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.service_record_ungani_invoice_payment(uuid, uuid, numeric, date, text, text, text) from public, authenticated;
grant execute on function public.service_record_ungani_invoice_payment(uuid, uuid, numeric, date, text, text, text) to service_role;

-- ============================================================
-- PART B: record_ungani_pos_sale - add 'mpesa_manual' as a third payment
-- method, valid alongside the existing 'cash'/'mpesa'. Settles exactly
-- like cash (immediate stock deduction + record_ungani_invoice_payment
-- call) but is recorded with method 'M-Pesa' so it's indistinguishable
-- from any other M-Pesa-labelled sale in Money, while still being
-- identifiable as a POS-recorded row (related_invoice_id is set) for the
-- reconciliation RPC in Part C.
--
-- Everything else is unchanged from the live version
-- (fix-pos-sale-missing-money-permission-check.sql:21-136).
-- ============================================================

create or replace function public.record_ungani_pos_sale(p_customer_name text, p_customer_person_id uuid DEFAULT NULL::uuid, p_payment_method text DEFAULT 'cash'::text, p_items jsonb DEFAULT '[]'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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
  v_stock_result jsonb;
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

  select stock_tracking_enabled, pos_enabled
  into v_stock_tracking_enabled, v_pos_enabled
  from public.tenants
  where id = v_tenant_id;

  if coalesce(v_pos_enabled, false) is not true then
    return jsonb_build_object('ok', false, 'message', 'Point of Sale is not turned on for this business. Enable it in Settings.');
  end if;

  select package_key into v_package_key
  from public.ungani_subscriptions
  where tenant_id = v_tenant_id;

  select coalesce(p.pos_included, false) into v_pos_included
  from public.ungani_packages p
  where p.package_key = v_package_key;

  if coalesce(v_pos_included, false) is not true then
    return jsonb_build_object('ok', false, 'message', 'Your package does not include Point of Sale. Upgrade to Business or Custom to use Quick Sale.');
  end if;

  v_payment_method := lower(trim(coalesce(p_payment_method, 'cash')));
  if v_payment_method not in ('cash', 'mpesa', 'mpesa_manual') then
    return jsonb_build_object('ok', false, 'message', 'Invalid payment method.');
  end if;

  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
    return jsonb_build_object('ok', false, 'message', 'Add at least one item to the sale.');
  end if;

  v_invoice_result := public.owner_upsert_ungani_customer_invoice(
    p_customer_name := p_customer_name,
    p_customer_person_id := p_customer_person_id,
    p_items := p_items
  );

  if coalesce((v_invoice_result->>'ok')::boolean, false) is not true then
    return v_invoice_result;
  end if;

  v_invoice_id := (v_invoice_result->>'invoice_id')::uuid;

  select invoice_number, total_amount into v_invoice_number, v_total_amount
  from public.ungani_customer_invoices
  where id = v_invoice_id;

  if v_payment_method in ('cash', 'mpesa_manual') then
    for v_item in select * from jsonb_array_elements(p_items)
    loop
      if v_item->>'item_id' is not null and coalesce(v_stock_tracking_enabled, false) then
        v_stock_result := public.adjust_ungani_stock(
          (v_item->>'item_id')::uuid,
          'sale',
          -coalesce((v_item->>'quantity')::numeric, 1),
          'POS sale: ' || v_invoice_number
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

    return jsonb_build_object(
      'ok', true, 'invoice_id', v_invoice_id, 'invoice_number', v_invoice_number,
      'total_amount', v_total_amount, 'status', 'paid', 'payment_method', v_payment_method
    );
  end if;

  return jsonb_build_object(
    'ok', true, 'invoice_id', v_invoice_id, 'invoice_number', v_invoice_number,
    'total_amount', v_total_amount, 'status', 'draft', 'payment_method', 'mpesa'
  );
end;
$function$;

-- ============================================================
-- PART C: new reconciliation RPC.
--
-- mpesa_received_total: passive C2B rows only - category/related_invoice_id
-- aren't used as the filter (a future reclassification of an Uncategorized
-- row would wrongly drop it) - payer_phone populated + related_invoice_id
-- null is the real structural signature of a C2B-originated row, confirmed
-- against the exact insert in api/mpesa-stk-push.js:764-782.
--
-- pos_sales_total: every transactions row with related_invoice_id set,
-- any payment method - a real recorded sale regardless of how it was paid.
-- ============================================================

create or replace function public.owner_get_ungani_pos_mpesa_reconciliation(p_date date default current_date)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_pos_enabled boolean;
  v_mpesa_total numeric := 0;
  v_pos_total numeric := 0;
  v_unmatched jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select pos_enabled into v_pos_enabled from public.tenants where id = v_tenant_id;

  if coalesce(v_pos_enabled, false) is not true then
    return jsonb_build_object('ok', false, 'message', 'Point of Sale is not turned on for this business.');
  end if;

  select coalesce(sum(amount), 0) into v_mpesa_total
  from public.transactions
  where tenant_id = v_tenant_id
    and transaction_date = p_date
    and payment_method = 'M-Pesa'
    and related_invoice_id is null
    and payer_phone is not null;

  select coalesce(sum(amount), 0) into v_pos_total
  from public.transactions
  where tenant_id = v_tenant_id
    and transaction_date = p_date
    and related_invoice_id is not null;

  select coalesce(jsonb_agg(jsonb_build_object(
      'id', t.id,
      'amount', t.amount,
      'payer_phone', t.payer_phone,
      'reference_no', t.reference_no,
      'created_at', t.created_at
    ) order by t.created_at), '[]'::jsonb)
  into v_unmatched
  from public.transactions t
  where t.tenant_id = v_tenant_id
    and t.transaction_date = p_date
    and t.payment_method = 'M-Pesa'
    and t.related_invoice_id is null
    and t.payer_phone is not null
    and not exists (
      select 1 from public.transactions p
      where p.tenant_id = v_tenant_id
        and p.transaction_date = p_date
        and p.related_invoice_id is not null
        and p.amount = t.amount
    );

  return jsonb_build_object(
    'ok', true,
    'date', p_date,
    'mpesa_received_total', v_mpesa_total,
    'pos_sales_total', v_pos_total,
    'discrepancy', v_mpesa_total - v_pos_total,
    'unmatched_mpesa_payments', v_unmatched
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.owner_get_ungani_pos_mpesa_reconciliation(date) from public;
grant execute on function public.owner_get_ungani_pos_mpesa_reconciliation(date) to authenticated;

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================

select proname, pg_get_function_identity_arguments(oid) as args
from pg_proc
where proname in ('service_record_ungani_invoice_payment', 'record_ungani_pos_sale', 'owner_get_ungani_pos_mpesa_reconciliation')
  and pronamespace = 'public'::regnamespace
order by proname;

select routine_name, grantee, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name in ('service_record_ungani_invoice_payment', 'record_ungani_pos_sale', 'owner_get_ungani_pos_mpesa_reconciliation')
order by routine_name, grantee;
