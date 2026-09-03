-- Task 2: Business branding (printable documents only) + new customer
-- invoicing module. Real schema pulled and confirmed before writing this
-- (sql/diagnose-task2-branding-invoicing-schema.sql) - see chat for full
-- reasoning on every column decision below.
--
-- Explicitly NOT touched: dashboard/sidebar/nav/in-app UNGANI branding,
-- my-invoice.html (UNGANI's own subscription bill TO the tenant),
-- print-report.html's data logic (only its header/footer rendering will
-- be swapped to the new shared component in a later, separate commit).
--
-- ungani_invoice_number_seq (the orphaned, zero-reference sequence found
-- during investigation) is deliberately left untouched and unused - a
-- single global sequence object can't produce independent per-tenant
-- numbering, so this migration uses a per-tenant counter column instead
-- (tenants.next_invoice_number).

-- ============================================================
-- PART A: Branding columns on tenants.
--
-- company_name and logo_url already exist (confirmed live) - not
-- duplicated here. email/phone/location and business_email/
-- business_phone/business_location both already exist but are
-- inconsistently populated across the app with no single authoritative
-- source (confirmed via grep - multiple pages defensively fall back
-- across both sets) - reusing either risks bleeding into that existing
-- ambiguity, so branding gets its own clearly-scoped columns instead.
-- ============================================================

alter table public.tenants
  add column if not exists branding_email text,
  add column if not exists branding_phone text,
  add column if not exists branding_address text,
  add column if not exists kra_pin text,
  add column if not exists owner_name text,
  add column if not exists next_invoice_number integer not null default 1;

-- ============================================================
-- PART B: Storage bucket for logo uploads.
--
-- Public bucket (not private, unlike payment-proofs) - a company logo
-- isn't sensitive data, and this avoids needing signed-URL generation
-- just to render an <img> tag on every printable document. Anyone with
-- the exact object URL could view the image directly, but LISTING the
-- bucket (finding those URLs) and uploading/replacing/deleting objects
-- both remain restricted to the owning tenant via RLS below - the same
-- tradeoff most SaaS apps make for logo/avatar assets.
-- ============================================================

insert into storage.buckets (id, name, public)
values ('tenant-branding', 'tenant-branding', true)
on conflict (id) do nothing;

drop policy if exists tenant_branding_select on storage.objects;
create policy tenant_branding_select on storage.objects
  for select
  using (
    bucket_id = 'tenant-branding'
    and (storage.foldername(name))[1] = public.get_my_ungani_tenant_id()::text
  );

drop policy if exists tenant_branding_insert on storage.objects;
create policy tenant_branding_insert on storage.objects
  for insert
  with check (
    bucket_id = 'tenant-branding'
    and (storage.foldername(name))[1] = public.get_my_ungani_tenant_id()::text
  );

drop policy if exists tenant_branding_update on storage.objects;
create policy tenant_branding_update on storage.objects
  for update
  using (
    bucket_id = 'tenant-branding'
    and (storage.foldername(name))[1] = public.get_my_ungani_tenant_id()::text
  );

drop policy if exists tenant_branding_delete on storage.objects;
create policy tenant_branding_delete on storage.objects
  for delete
  using (
    bucket_id = 'tenant-branding'
    and (storage.foldername(name))[1] = public.get_my_ungani_tenant_id()::text
  );

-- ============================================================
-- PART C: Customer invoices - the new module. Separate entirely from
-- my-invoice.html (UNGANI's bill to the tenant) and print-report.html
-- (internal activity report) - this is a business's own bill to ITS
-- customer.
--
-- Status: draft/sent/cancelled are real workflow states an RPC sets
-- explicitly. partially_paid/paid are recomputed automatically whenever
-- a payment is recorded (see record_ungani_invoice_payment below).
-- overdue is NOT stored - it's a point-in-time fact (today vs due_date)
-- that would need a cron job to keep a stored column truthful, which is
-- out of scope for v1. get_my_ungani_customer_invoices() below computes
-- it at read-time instead, same as how the client should treat it.
--
-- customer_name/address/contact are stored directly on the invoice as
-- an immutable snapshot of what was true when it was created -
-- customer_person_id is an optional back-reference to client_people for
-- reporting only, so editing that person's record later never
-- retroactively changes an already-issued invoice.
-- ============================================================

create table if not exists public.ungani_customer_invoices (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  invoice_number text not null,

  customer_person_id uuid references public.client_people(id) on delete set null,
  customer_name text not null,
  customer_address text,
  customer_contact text,

  issue_date date not null default current_date,
  due_date date,
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
  amount_paid numeric not null default 0,
  currency text not null default 'KES',

  status text not null default 'draft',
  notes text,

  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  deleted_at timestamptz,
  deleted_by uuid,
  delete_reason text,
  restored_at timestamptz,
  restored_by uuid,

  constraint ungani_customer_invoices_status_check
    check (status in ('draft', 'sent', 'partially_paid', 'paid', 'cancelled')),
  constraint ungani_customer_invoices_number_unique
    unique (tenant_id, invoice_number)
);

alter table public.ungani_customer_invoices enable row level security;

drop policy if exists ungani_customer_invoices_tenant_select on public.ungani_customer_invoices;
create policy ungani_customer_invoices_tenant_select on public.ungani_customer_invoices
  for select
  using (tenant_id = public.get_my_ungani_tenant_id());

grant select on public.ungani_customer_invoices to authenticated;

-- ============================================================
-- PART D: Invoice line items.
-- ============================================================

create table if not exists public.ungani_customer_invoice_items (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.ungani_customer_invoices(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  description text not null,
  quantity numeric not null default 1,
  unit_price numeric not null default 0,
  line_subtotal numeric not null default 0,
  sort_order integer not null default 0,
  created_at timestamptz not null default now()
);

alter table public.ungani_customer_invoice_items enable row level security;

drop policy if exists ungani_customer_invoice_items_tenant_select on public.ungani_customer_invoice_items;
create policy ungani_customer_invoice_items_tenant_select on public.ungani_customer_invoice_items
  for select
  using (tenant_id = public.get_my_ungani_tenant_id());

grant select on public.ungani_customer_invoice_items to authenticated;

-- ============================================================
-- PART E: Invoice payments - supports partial payments against one
-- invoice. amount_paid/status on the parent invoice are kept in sync by
-- record_ungani_invoice_payment() below, not maintained by hand.
-- ============================================================

create table if not exists public.ungani_customer_invoice_payments (
  id uuid primary key default gen_random_uuid(),
  invoice_id uuid not null references public.ungani_customer_invoices(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  amount numeric not null,
  paid_at date not null default current_date,
  method text,
  reference text,
  notes text,
  created_by uuid,
  created_at timestamptz not null default now()
);

alter table public.ungani_customer_invoice_payments enable row level security;

drop policy if exists ungani_customer_invoice_payments_tenant_select on public.ungani_customer_invoice_payments;
create policy ungani_customer_invoice_payments_tenant_select on public.ungani_customer_invoice_payments
  for select
  using (tenant_id = public.get_my_ungani_tenant_id());

grant select on public.ungani_customer_invoice_payments to authenticated;

-- ============================================================
-- PART F: RPCs. All writes go through these (SECURITY DEFINER) rather
-- than direct table grants, matching the Payee feature's pattern from
-- Task 1 - keeps totals/status/numbering correct in one place instead
-- of trusting client-computed values.
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
  uuid, uuid, text, text, text, date, text, date, text, text, boolean, numeric, text, numeric, text, text, jsonb
) to authenticated;

-- Explicit status transitions that aren't "record a payment" - Draft to
-- Sent, or Cancelled. Kept separate from the upsert RPC above so
-- changing status is its own clear, auditable action.
create or replace function public.update_ungani_invoice_status(p_invoice_id uuid, p_status text)
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

  if v_clean_status not in ('draft', 'sent', 'cancelled') then
    return jsonb_build_object('ok', false, 'message', 'Invalid status. Use draft, sent, or cancelled.');
  end if;

  update public.ungani_customer_invoices
  set status = v_clean_status, updated_at = now()
  where id = p_invoice_id and tenant_id = v_tenant_id
    and status not in ('partially_paid', 'paid');

  if not found then
    return jsonb_build_object('ok', false, 'message', 'Invoice not found, or already has payments recorded against it.');
  end if;

  return jsonb_build_object('ok', true);
end;
$function$;

grant execute on function public.update_ungani_invoice_status(uuid, text) to authenticated;

-- Records a (possibly partial) payment and keeps the parent invoice's
-- amount_paid/status in sync - the single source of truth for both,
-- rather than trusting the client to compute and send them.
create or replace function public.record_ungani_invoice_payment(
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
  v_tenant_id uuid;
  v_invoice record;
  v_new_paid numeric;
  v_new_status text;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object('ok', false, 'message', 'Payment amount must be greater than zero.');
  end if;

  select * into v_invoice
  from public.ungani_customer_invoices
  where id = p_invoice_id and tenant_id = v_tenant_id;

  if v_invoice.id is null then
    return jsonb_build_object('ok', false, 'message', 'Invoice not found.');
  end if;

  if v_invoice.status = 'cancelled' then
    return jsonb_build_object('ok', false, 'message', 'Cannot record a payment against a cancelled invoice.');
  end if;

  insert into public.ungani_customer_invoice_payments (
    invoice_id, tenant_id, amount, paid_at, method, reference, notes, created_by
  )
  values (
    p_invoice_id, v_tenant_id, p_amount, coalesce(p_paid_at, current_date), p_method, p_reference, p_notes, auth.uid()
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
end;
$function$;

grant execute on function public.record_ungani_invoice_payment(uuid, numeric, date, text, text, text) to authenticated;

-- List view - computes "overdue" at read-time (not stored) by comparing
-- due_date to today for any invoice that's sent/partially_paid and not
-- yet fully paid.
create or replace function public.get_my_ungani_customer_invoices()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_invoices jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', i.id,
      'invoice_number', i.invoice_number,
      'customer_name', i.customer_name,
      'issue_date', i.issue_date,
      'due_date', i.due_date,
      'total_amount', i.total_amount,
      'amount_paid', i.amount_paid,
      'currency', i.currency,
      'status', i.status,
      'effective_status', case
        when i.status in ('sent', 'partially_paid') and i.due_date is not null and i.due_date < current_date
          then 'overdue'
        else i.status
      end
    )
    order by i.created_at desc
  ), '[]'::jsonb)
  into v_invoices
  from public.ungani_customer_invoices i
  where i.tenant_id = v_tenant_id
    and i.deleted_at is null;

  return jsonb_build_object('ok', true, 'invoices', v_invoices);
end;
$function$;

grant execute on function public.get_my_ungani_customer_invoices() to authenticated;

-- Single-invoice detail (items + payments) for the edit/print view.
create or replace function public.get_ungani_customer_invoice_detail(p_invoice_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_invoice jsonb;
  v_items jsonb;
  v_payments jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select to_jsonb(i) into v_invoice
  from public.ungani_customer_invoices i
  where i.id = p_invoice_id and i.tenant_id = v_tenant_id;

  if v_invoice is null then
    return jsonb_build_object('ok', false, 'message', 'Invoice not found.');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object('id', id, 'description', description, 'quantity', quantity, 'unit_price', unit_price, 'line_subtotal', line_subtotal)
    order by sort_order
  ), '[]'::jsonb)
  into v_items
  from public.ungani_customer_invoice_items
  where invoice_id = p_invoice_id;

  select coalesce(jsonb_agg(
    jsonb_build_object('id', id, 'amount', amount, 'paid_at', paid_at, 'method', method, 'reference', reference, 'notes', notes)
    order by paid_at
  ), '[]'::jsonb)
  into v_payments
  from public.ungani_customer_invoice_payments
  where invoice_id = p_invoice_id;

  return jsonb_build_object('ok', true, 'invoice', v_invoice, 'items', v_items, 'payments', v_payments);
end;
$function$;

grant execute on function public.get_ungani_customer_invoice_detail(uuid) to authenticated;

-- ============================================================
-- VERIFICATION - run and paste back the output.
-- ============================================================

select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'tenants'
  and column_name in ('branding_email', 'branding_phone', 'branding_address', 'kra_pin', 'owner_name', 'next_invoice_number')
order by column_name;

select id, name, public from storage.buckets where id = 'tenant-branding';

select policyname, cmd from pg_policies
where schemaname = 'storage' and tablename = 'objects' and policyname like 'tenant_branding_%'
order by policyname;

select table_name from information_schema.tables
where table_schema = 'public'
  and table_name in ('ungani_customer_invoices', 'ungani_customer_invoice_items', 'ungani_customer_invoice_payments')
order by table_name;

select routine_name from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'owner_upsert_ungani_customer_invoice',
    'update_ungani_invoice_status',
    'record_ungani_invoice_payment',
    'get_my_ungani_customer_invoices',
    'get_ungani_customer_invoice_detail'
  )
order by routine_name;

select routine_name, privilege_type from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name in (
    'owner_upsert_ungani_customer_invoice',
    'update_ungani_invoice_status',
    'record_ungani_invoice_payment',
    'get_my_ungani_customer_invoices',
    'get_ungani_customer_invoice_detail'
  )
  and grantee = 'authenticated'
order by routine_name;

select table_name, privilege_type from information_schema.table_privileges
where table_schema = 'public'
  and table_name in ('ungani_customer_invoices', 'ungani_customer_invoice_items', 'ungani_customer_invoice_payments')
  and grantee = 'authenticated'
order by table_name, privilege_type;
