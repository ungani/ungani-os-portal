-- Task 5: Quotations.
--
-- Separate ungani_quotations + ungani_quotation_items tables, NOT an
-- extension of ungani_customer_invoices - confirmed via the real,
-- already-run invoice schema (sql/task2-branding-and-customer-invoicing.sql)
-- that reusing the invoice table would require:
--   - relaxing/replacing its status CHECK constraint (currently
--     'draft'/'sent'/'partially_paid'/'paid'/'cancelled' - all payment
--     lifecycle language, nothing that maps onto accepted/rejected)
--   - a separate numbering sequence (sharing next_invoice_number would
--     make invoice numbers non-sequential)
--   - a document_type filter retrofitted onto every existing consumer
--     (list view, KPIs, CSV export, Nia's invoice intent, the Debtors
--     aggregation from Task 4) to keep quotes out of revenue totals
-- A separate table avoids all of that structurally, while still reusing
-- the exact same line-item shape, VAT math, and UI shell as invoices.
--
-- Ungated (matches Customer Invoicing, not the Stock Tracking / Debtors
-- & Payables toggle pattern) - purely additive, doesn't change any
-- existing page's behavior, per user decision.
--
-- Also proactively adds ungani_quotations to soft_delete_ungani_record()
-- and get_my_ungani_recently_deleted_v2()'s allowlists in this same
-- migration - the exact bug Customer Invoicing hit in Task 2 (both
-- functions pulled from their real, already-run current source via
-- pg_get_functiondef before writing this - only the additions below are
-- new, every other line is byte-for-byte identical to the live version).

-- ============================================================
-- PART A: Quotation numbering sequence.
-- ============================================================

alter table public.tenants
  add column if not exists next_quotation_number integer not null default 1;

-- ============================================================
-- PART B: Quotations.
-- ============================================================

create table if not exists public.ungani_quotations (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  quotation_number text not null,

  customer_person_id uuid references public.client_people(id) on delete set null,
  customer_name text not null,
  customer_address text,
  customer_contact text,

  issue_date date not null default current_date,
  valid_until date,
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

  status text not null default 'draft',
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

  constraint ungani_quotations_status_check
    check (status in ('draft', 'sent', 'accepted', 'rejected', 'cancelled', 'converted')),
  constraint ungani_quotations_number_unique
    unique (tenant_id, quotation_number)
);

alter table public.ungani_quotations enable row level security;

drop policy if exists ungani_quotations_tenant_select on public.ungani_quotations;
create policy ungani_quotations_tenant_select on public.ungani_quotations
  for select
  using (tenant_id = public.get_my_ungani_tenant_id());

grant select on public.ungani_quotations to authenticated;

-- ============================================================
-- PART C: Quotation line items.
-- ============================================================

create table if not exists public.ungani_quotation_items (
  id uuid primary key default gen_random_uuid(),
  quotation_id uuid not null references public.ungani_quotations(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  description text not null,
  quantity numeric not null default 1,
  unit_price numeric not null default 0,
  line_subtotal numeric not null default 0,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.ungani_quotation_items enable row level security;

drop policy if exists ungani_quotation_items_tenant_select on public.ungani_quotation_items;
create policy ungani_quotation_items_tenant_select on public.ungani_quotation_items
  for select
  using (tenant_id = public.get_my_ungani_tenant_id());

grant select on public.ungani_quotation_items to authenticated;

-- ============================================================
-- PART D: RPCs.
-- ============================================================

create or replace function public.owner_upsert_ungani_quotation(
  p_quotation_id uuid default null,
  p_customer_person_id uuid default null,
  p_customer_name text default null,
  p_customer_address text default null,
  p_customer_contact text default null,
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

  -- Matches owner_upsert_ungani_customer_invoice's VAT math exactly.
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
    -- Edit path: only draft/sent quotations can be edited - once a
    -- customer has responded (accepted/rejected) or it's converted/
    -- cancelled, don't let it be silently rewritten.
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
      customer_contact, valid_until, delivery_address, delivery_date, payment_terms,
      payment_details, vat_applicable, vat_rate, vat_pricing_mode, discount_amount,
      subtotal, vat_amount, total_amount, currency, status, notes, created_by
    )
    values (
      v_tenant_id, v_quotation_number, p_customer_person_id, v_clean_name,
      nullif(trim(coalesce(p_customer_address, '')), ''),
      nullif(trim(coalesce(p_customer_contact, '')), ''),
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
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

grant execute on function public.owner_upsert_ungani_quotation(
  uuid, uuid, text, text, text, date, text, date, text, text, boolean, numeric, text, numeric, text, text, jsonb
) to authenticated;

-- Explicit status transitions (draft/sent/accepted/rejected/cancelled) -
-- 'converted' is never set here, only by convert_ungani_quotation_to_invoice
-- below, and a quotation that's already converted can't be reverted.
create or replace function public.update_ungani_quotation_status(p_quotation_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_clean_status text;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  v_clean_status := lower(trim(coalesce(p_status, '')));

  if v_clean_status not in ('draft', 'sent', 'accepted', 'rejected', 'cancelled') then
    return jsonb_build_object('ok', false, 'message', 'Invalid status. Use draft, sent, accepted, rejected, or cancelled.');
  end if;

  update public.ungani_quotations
  set status = v_clean_status, updated_at = now()
  where id = p_quotation_id and tenant_id = v_tenant_id
    and status <> 'converted';

  if not found then
    return jsonb_build_object('ok', false, 'message', 'Quotation not found, or it has already been converted to an invoice.');
  end if;

  return jsonb_build_object('ok', true);
end;
$function$;

grant execute on function public.update_ungani_quotation_status(uuid, text) to authenticated;

-- Converts a quotation into a real invoice - only from sent/accepted (not
-- draft, since an unsent quote shouldn't silently become a real invoice;
-- not rejected/cancelled/already converted). Copies line items over,
-- claims a fresh invoice number, and the new invoice starts as 'draft'
-- so the owner reviews it before sending - conversion never auto-sends.
create or replace function public.convert_ungani_quotation_to_invoice(p_quotation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_quotation record;
  v_invoice_id uuid;
  v_invoice_number text;
  v_next_number integer;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select * into v_quotation
  from public.ungani_quotations
  where id = p_quotation_id and tenant_id = v_tenant_id;

  if v_quotation.id is null then
    return jsonb_build_object('ok', false, 'message', 'Quotation not found.');
  end if;

  if v_quotation.status not in ('sent', 'accepted') then
    return jsonb_build_object('ok', false, 'message', 'Only a sent or accepted quotation can be converted to an invoice.');
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
    v_tenant_id, v_invoice_number, v_quotation.customer_person_id, v_quotation.customer_name,
    v_quotation.customer_address, v_quotation.customer_contact, v_quotation.delivery_address,
    v_quotation.delivery_date, v_quotation.payment_terms, v_quotation.payment_details,
    v_quotation.vat_applicable, v_quotation.vat_rate, v_quotation.vat_pricing_mode,
    v_quotation.discount_amount, v_quotation.subtotal, v_quotation.vat_amount, v_quotation.total_amount,
    v_quotation.currency, 'draft',
    trim(both from coalesce('Converted from ' || v_quotation.quotation_number || '. ', '') || coalesce(v_quotation.notes, '')),
    auth.uid()
  )
  returning id into v_invoice_id;

  insert into public.ungani_customer_invoice_items (
    invoice_id, tenant_id, description, quantity, unit_price, line_subtotal, sort_order
  )
  select v_invoice_id, v_tenant_id, description, quantity, unit_price, line_subtotal, sort_order
  from public.ungani_quotation_items
  where quotation_id = p_quotation_id;

  update public.ungani_quotations
  set status = 'converted', converted_invoice_id = v_invoice_id, updated_at = now()
  where id = p_quotation_id;

  return jsonb_build_object('ok', true, 'invoice_id', v_invoice_id, 'invoice_number', v_invoice_number);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

grant execute on function public.convert_ungani_quotation_to_invoice(uuid) to authenticated;

-- List view - computes "expired" at read-time (not stored) for a
-- sent quotation whose valid_until has passed, same pattern as
-- get_my_ungani_customer_invoices()'s "overdue".
create or replace function public.get_my_ungani_quotations()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_quotations jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', q.id,
      'quotation_number', q.quotation_number,
      'customer_name', q.customer_name,
      'issue_date', q.issue_date,
      'valid_until', q.valid_until,
      'total_amount', q.total_amount,
      'currency', q.currency,
      'status', q.status,
      'converted_invoice_id', q.converted_invoice_id,
      'effective_status', case
        when q.status = 'sent' and q.valid_until is not null and q.valid_until < current_date
          then 'expired'
        else q.status
      end
    )
    order by q.created_at desc
  ), '[]'::jsonb)
  into v_quotations
  from public.ungani_quotations q
  where q.tenant_id = v_tenant_id
    and q.deleted_at is null;

  return jsonb_build_object('ok', true, 'quotations', v_quotations);
end;
$function$;

grant execute on function public.get_my_ungani_quotations() to authenticated;

-- Single-quotation detail (items) for the edit/print view.
create or replace function public.get_ungani_quotation_detail(p_quotation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_quotation jsonb;
  v_items jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select to_jsonb(q) into v_quotation
  from public.ungani_quotations q
  where q.id = p_quotation_id and q.tenant_id = v_tenant_id;

  if v_quotation is null then
    return jsonb_build_object('ok', false, 'message', 'Quotation not found.');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object('id', id, 'description', description, 'quantity', quantity, 'unit_price', unit_price, 'line_subtotal', line_subtotal)
    order by sort_order
  ), '[]'::jsonb)
  into v_items
  from public.ungani_quotation_items
  where quotation_id = p_quotation_id;

  return jsonb_build_object('ok', true, 'quotation', v_quotation, 'items', v_items);
end;
$function$;

grant execute on function public.get_ungani_quotation_detail(uuid) to authenticated;

-- ============================================================
-- PART E: soft_delete_ungani_record() allowlist addition.
-- Pulled from the real, currently-live source (sql/fix-soft-delete-invoice-allowlist.sql,
-- confirmed run) - only the two additions below (allowlist entry + title
-- branch), every other line is unchanged.
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
    'ungani_quotations'
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
-- Pulled from the real, currently-live source
-- (sql/fix-recently-deleted-v2-invoice-allowlist.sql, confirmed run) -
-- only the additions below (table array entry, label, title candidates,
-- and the same combined-title exception invoices got), every other line
-- is unchanged.
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
    'ungani_quotations'
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

    -- Invoices and quotations both need their number AND the customer
    -- name to be meaningful in this list - the same deliberate exception
    -- to the generic single-column-priority title above.
    if v_table = 'ungani_customer_invoices' then
      v_title_expr := $ov$coalesce(invoice_number, 'Customer invoice') || coalesce(' · ' || nullif(trim(customer_name), ''), '')$ov$;
    elsif v_table = 'ungani_quotations' then
      v_title_expr := $ov$coalesce(quotation_number, 'Quotation') || coalesce(' · ' || nullif(trim(customer_name), ''), '')$ov$;
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
where table_schema = 'public' and table_name in ('ungani_quotations', 'ungani_quotation_items')
order by table_name, column_name;

select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'tenants' and column_name = 'next_quotation_number';

select pg_get_functiondef(p.oid) like '%ungani_quotations%' as soft_delete_allowlist_updated
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'soft_delete_ungani_record';

select pg_get_functiondef(p.oid) like '%ungani_quotations%' as recently_deleted_allowlist_updated
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'get_my_ungani_recently_deleted_v2';
