-- POS "Quick Sale" Phase 2: the modified owner_upsert_ungani_customer_invoice
-- (adds item_id persistence, ONLY change from its real current body -
-- verified against the live source read in full this session) and the
-- new record_ungani_pos_sale RPC. Run sql/pos-quick-sale-phase1.sql
-- BEFORE this file (it depends on the columns added there).

-- ============================================================
-- PART A: owner_upsert_ungani_customer_invoice - full function,
-- unchanged except the items-insert loop now also writes item_id when
-- the caller supplies it. Every other line is identical to the real
-- live body.
-- ============================================================

create or replace function public.owner_upsert_ungani_customer_invoice(
  p_invoice_id uuid default null,
  p_customer_person_id uuid default null,
  p_customer_name text default null,
  p_customer_address text default null,
  p_customer_contact text default null,
  p_due_date date default null,
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

  -- Compute totals from the submitted line items server-side - never
  -- trust client-computed totals.
  for v_item in select * from jsonb_array_elements(coalesce(p_items, '[]'::jsonb))
  loop
    v_line_subtotal := coalesce((v_item->>'quantity')::numeric, 1) * coalesce((v_item->>'unit_price')::numeric, 0);
    v_subtotal := v_subtotal + v_line_subtotal;
  end loop;

  v_subtotal := v_subtotal - coalesce(p_discount_amount, 0);

  -- Matches my-money.html's saveMoneyRecord() VAT math exactly (same
  -- formulas, same 2-decimal rounding) - see that function for the
  -- reference implementation this mirrors.
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
    -- Edit path: only draft/sent invoices can be edited, matching the
    -- "don't rewrite history once money has moved" principle already
    -- used for transactions elsewhere in this app.
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
    -- Create path: atomically claim the next per-tenant invoice number.
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

    -- FIXED (POS Phase 2): now also persists item_id when supplied -
    -- every pre-existing caller simply never sends this key, so it
    -- stays null exactly as before for them.
    insert into public.ungani_customer_invoice_items (
      invoice_id, tenant_id, item_id, description, quantity, unit_price, line_subtotal, sort_order
    )
    values (
      v_invoice_id, v_tenant_id, nullif(v_item->>'item_id', '')::uuid, coalesce(v_item->>'description', ''),
      coalesce((v_item->>'quantity')::numeric, 1), coalesce((v_item->>'unit_price')::numeric, 0),
      v_line_subtotal, v_sort
    );

    v_sort := v_sort + 1;
  end loop;

  return jsonb_build_object('ok', true, 'id', v_invoice_id, 'invoice_id', v_invoice_id);
end;
$function$;

grant execute on function public.owner_upsert_ungani_customer_invoice(
  uuid, uuid, text, text, text, date, text, date, text, text, boolean, numeric, text, numeric, text, text, jsonb
) to authenticated;

-- ============================================================
-- PART B: record_ungani_pos_sale - the single entry point for Quick
-- Sale. Server-side eligibility gate is the real security boundary
-- (mirrors the trial-cap/user-limit enforcement style already used in
-- owner_upsert_ungani_team_member) - nav-hiding is UX on top of this,
-- not the enforcement itself.
-- ============================================================

create or replace function public.record_ungani_pos_sale(
  p_customer_name text,
  p_customer_person_id uuid default null,
  p_payment_method text default 'cash',
  p_items jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
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

  select stock_tracking_enabled, pos_enabled
  into v_stock_tracking_enabled, v_pos_enabled
  from public.tenants
  where id = v_tenant_id;

  if coalesce(v_pos_enabled, false) is not true then
    return jsonb_build_object('ok', false, 'message', 'Point of Sale is not turned on for this business. Enable it in Settings.');
  end if;

  -- Reads ungani_subscriptions.package_key (the live value), never
  -- tenants.package_key (confirmed stale after upgrades).
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
  if v_payment_method not in ('cash', 'mpesa') then
    return jsonb_build_object('ok', false, 'message', 'Invalid payment method.');
  end if;

  if jsonb_array_length(coalesce(p_items, '[]'::jsonb)) = 0 then
    return jsonb_build_object('ok', false, 'message', 'Add at least one item to the sale.');
  end if;

  -- Reuses the real, existing invoice-creation RPC - one canonical
  -- place for totals/VAT/invoice-numbering, not a parallel
  -- implementation. This is what makes a POS sale a real Invoice.
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

  if v_payment_method = 'cash' then
    -- Cash is already physically in hand - deduct stock and mark paid
    -- now, atomically. Any stock failure raises (not returns), which
    -- rolls back the invoice and any already-succeeded deductions in
    -- this same call together - never a "paid invoice, no stock moved"
    -- or "stock moved, no invoice" half-state.
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
      p_method := 'cash',
      p_notes := 'Quick Sale'
    );

    return jsonb_build_object(
      'ok', true, 'invoice_id', v_invoice_id, 'invoice_number', v_invoice_number,
      'total_amount', v_total_amount, 'status', 'paid', 'payment_method', 'cash'
    );
  end if;

  -- M-Pesa path: invoice created as draft, NO stock deducted yet - a
  -- declined/cancelled/timed-out prompt must never remove stock for a
  -- sale that didn't happen. The client now triggers the STK push
  -- against this invoice_id/amount; stock deduction and payment
  -- recording happen together, atomically, in the M-Pesa callback,
  -- only once payment is actually confirmed.
  return jsonb_build_object(
    'ok', true, 'invoice_id', v_invoice_id, 'invoice_number', v_invoice_number,
    'total_amount', v_total_amount, 'status', 'draft', 'payment_method', 'mpesa'
  );
end;
$function$;

grant execute on function public.record_ungani_pos_sale(text, uuid, text, jsonb) to authenticated;

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================

select proname, pg_get_function_identity_arguments(oid) as args
from pg_proc
where proname in ('owner_upsert_ungani_customer_invoice', 'record_ungani_pos_sale')
  and pronamespace = 'public'::regnamespace
order by proname;
