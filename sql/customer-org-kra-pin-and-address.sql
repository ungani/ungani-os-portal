-- Company/Organization data completeness (Chris's request): a customer's
-- KRA PIN and physical/mailing address should be captured ONCE on their
-- client_people record (Person or Organization) and then be available to
-- pull onto Invoices/Quotations, instead of only name+phone/email
-- (confirmed via investigation: client_people currently has neither an
-- address nor a PIN column at all - only phone/email/a generic
-- non-address "location" field).
--
-- Both owner_upsert_ungani_customer_invoice and owner_upsert_ungani_quotation
-- already exist live with a fixed parameter list (confirmed via
-- sql/task2-branding-and-customer-invoicing.sql and sql/task5-quotations.sql,
-- the real already-run source for both). Adding a new parameter requires
-- an explicit DROP of the OLD signature first - CREATE OR REPLACE with a
-- different parameter list creates a second overload instead of replacing
-- the original, which is the exact stale-overload bug class this project
-- has hit before (see ARCHITECTURE.md).
--
-- NOT touched in this migration: convert_ungani_quotation_to_invoice().
-- Three different files each define this same single-argument function
-- (task5-quotations.sql, staff-permission-enforcement-v1.sql,
-- subscription-write-block-rpcs-v1.sql, the last two with unclear/
-- unconfirmed run order) - safely reproducing its true current live body
-- would mean guessing, which this project's standing rule is to never do.
-- Practical effect: a quotation's Customer PIN will NOT automatically
-- carry over when converted to an invoice - it can be added manually on
-- the resulting invoice. Flagging this explicitly rather than silently
-- leaving it undocumented.

-- ============================================================
-- PART A: new columns. Purely additive.
-- ============================================================

alter table public.client_people
  add column if not exists kra_pin text,
  add column if not exists address text;

alter table public.ungani_customer_invoices
  add column if not exists customer_pin text;

alter table public.ungani_quotations
  add column if not exists customer_pin text;

-- ============================================================
-- PART B: owner_upsert_ungani_customer_invoice - add p_customer_pin.
-- Body below is byte-for-byte the live version from
-- sql/task2-branding-and-customer-invoicing.sql:223-387, with only
-- p_customer_pin added to the parameter list, the customer_pin column
-- added to both the UPDATE and INSERT paths, and one added
-- nullif/trim/coalesce line per path (same pattern as every other text
-- field in this function).
-- ============================================================

drop function if exists public.owner_upsert_ungani_customer_invoice(
  uuid, uuid, text, text, text, date, text, date, text, text, boolean, numeric, text, numeric, text, text, jsonb
);

create or replace function public.owner_upsert_ungani_customer_invoice(
  p_invoice_id uuid default null,
  p_customer_person_id uuid default null,
  p_customer_name text default null,
  p_customer_address text default null,
  p_customer_contact text default null,
  p_customer_pin text default null,
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

grant execute on function public.owner_upsert_ungani_customer_invoice(
  uuid, uuid, text, text, text, text, date, text, date, text, text, boolean, numeric, text, numeric, text, text, jsonb
) to authenticated;

-- ============================================================
-- PART C: owner_upsert_ungani_quotation - add p_customer_pin. Same
-- treatment, body byte-for-byte from sql/task5-quotations.sql:127-283.
-- ============================================================

drop function if exists public.owner_upsert_ungani_quotation(
  uuid, uuid, text, text, text, date, text, date, text, text, boolean, numeric, text, numeric, text, text, jsonb
);

create or replace function public.owner_upsert_ungani_quotation(
  p_quotation_id uuid default null,
  p_customer_person_id uuid default null,
  p_customer_name text default null,
  p_customer_address text default null,
  p_customer_contact text default null,
  p_customer_pin text default null,
  p_valid_until date default null,
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
        customer_pin = nullif(trim(coalesce(p_customer_pin, '')), ''),
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
    update public.tenants
    set next_quotation_number = next_quotation_number + 1
    where id = v_tenant_id
    returning next_quotation_number - 1 into v_next_number;

    v_quotation_number := 'QUO-' || to_char(current_date, 'YYYY') || '-' || lpad(v_next_number::text, 4, '0');

    insert into public.ungani_quotations (
      tenant_id, quotation_number, customer_person_id, customer_name, customer_address,
      customer_contact, customer_pin, valid_until, delivery_address, delivery_date, payment_terms,
      payment_details, vat_applicable, vat_rate, vat_pricing_mode, discount_amount,
      subtotal, vat_amount, total_amount, currency, status, notes, created_by
    )
    values (
      v_tenant_id, v_quotation_number, p_customer_person_id, v_clean_name,
      nullif(trim(coalesce(p_customer_address, '')), ''),
      nullif(trim(coalesce(p_customer_contact, '')), ''),
      nullif(trim(coalesce(p_customer_pin, '')), ''),
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
end;
$function$;

grant execute on function public.owner_upsert_ungani_quotation(
  uuid, uuid, text, text, text, text, date, text, date, text, text, boolean, numeric, text, numeric, text, text, jsonb
) to authenticated;

-- ============================================================
-- VERIFICATION - run and paste back the output.
-- ============================================================

select table_name, column_name from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'client_people' and column_name in ('kra_pin', 'address'))
    or (table_name = 'ungani_customer_invoices' and column_name = 'customer_pin')
    or (table_name = 'ungani_quotations' and column_name = 'customer_pin')
  )
order by table_name, column_name;

select routine_name, count(*) as overload_count
from information_schema.routines
where routine_schema = 'public'
  and routine_name in ('owner_upsert_ungani_customer_invoice', 'owner_upsert_ungani_quotation')
group by routine_name;
-- overload_count should be 1 for each - if either shows 2+, the old
-- signature's drop above didn't take and there are now duplicate
-- overloads (the exact bug this migration's DROP FUNCTION calls exist to
-- prevent).
