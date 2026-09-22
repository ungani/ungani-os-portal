-- Cluster 4: Recurring-commitment lifecycle (Lease / Membership / Service
-- Contract), generalized from Real Estate's already-working lease model.
--
-- Full cutover, not a mirror (explicit user decision): Real Estate's lease
-- data currently lives on client_people.lease_start_date/lease_end_date/
-- linked_item_id, with "expiring within 7 days" recomputed inline at 10+
-- call sites in client.html. This migration creates the one shared table
-- those three columns' data moves into, plus the RPCs/allowlists every
-- prior optional-module task in this series has needed. The client_people
-- columns themselves are left untouched by this SQL (app-code cutover is a
-- separate step) - Hospitality also writes those same three columns for
-- check-in/checkout, which is why this migration's backfill (Part E)
-- filters strictly to business_type_key = 'real_estate' and does NOT touch
-- Hospitality's rows.
--
-- Gated behind tenants.commitments_enabled (mirrors Stock Tracking/Debtors
-- & Payables/Price Lists' precedent) rather than ungated - most business
-- types (Retail, Logistics, Printing, etc.) have no recurring-commitment
-- concept at all and shouldn't see new UI surface for it.
--
-- `status` is a MANUAL field (active/terminated/frozen only - frozen is
-- Gym-specific for a paused membership). "expiring_soon"/"expired" are
-- NOT stored - they're derived client-side by comparing end_date to today,
-- exactly like the existing lease-expiring logic already does, so there is
-- no cron/background job dependency for date-based correctness.

-- ============================================================
-- PART A: Commitments toggle.
-- ============================================================

alter table public.tenants
  add column if not exists commitments_enabled boolean not null default false;

-- ============================================================
-- PART B: ungani_commitments table.
-- ============================================================

create table if not exists public.ungani_commitments (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,

  commitment_type text not null,
  -- 'lease' (Real Estate) | 'membership' (Gym) | 'service_contract' (Security / Cleaning)

  person_id uuid references public.client_people(id) on delete cascade,
  linked_item_id uuid references public.business_items(id) on delete set null,
  -- the unit (lease) or site (service_contract); null for membership

  plan_name text,
  amount numeric,
  billing_frequency text not null default 'monthly',
  -- 'monthly' | 'weekly' | 'quarterly' | 'annual' | 'once'

  start_date date,
  end_date date,

  status text not null default 'active',
  -- 'active' | 'terminated' | 'frozen' (manual states only, see note above)

  auto_renew boolean not null default false,
  section_label text,
  notes text,

  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  deleted_at timestamptz,
  deleted_by uuid,
  delete_reason text,
  restored_at timestamptz,
  restored_by uuid,

  constraint ungani_commitments_type_check
    check (commitment_type in ('lease', 'membership', 'service_contract')),
  constraint ungani_commitments_status_check
    check (status in ('active', 'terminated', 'frozen'))
);

create index if not exists ungani_commitments_tenant_idx
  on public.ungani_commitments (tenant_id);
create index if not exists ungani_commitments_person_idx
  on public.ungani_commitments (person_id);
create index if not exists ungani_commitments_end_date_idx
  on public.ungani_commitments (end_date);

alter table public.ungani_commitments enable row level security;

drop policy if exists ungani_commitments_tenant_select on public.ungani_commitments;
create policy ungani_commitments_tenant_select on public.ungani_commitments
  for select
  using (tenant_id = public.get_my_ungani_tenant_id());

grant select on public.ungani_commitments to authenticated;

-- ============================================================
-- PART C: RPCs.
-- ============================================================

create or replace function public.owner_upsert_ungani_commitment(
  p_commitment_id uuid default null,
  p_commitment_type text default null,
  p_person_id uuid default null,
  p_linked_item_id uuid default null,
  p_plan_name text default null,
  p_amount numeric default null,
  p_billing_frequency text default 'monthly',
  p_start_date date default null,
  p_end_date date default null,
  p_status text default 'active',
  p_auto_renew boolean default false,
  p_section_label text default null,
  p_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_commitment_id uuid;
  v_clean_type text;
  v_clean_status text;
  v_person_tenant_check uuid;
  v_item_tenant_check uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  v_clean_type := lower(trim(coalesce(p_commitment_type, '')));
  if v_clean_type not in ('lease', 'membership', 'service_contract') then
    return jsonb_build_object('ok', false, 'message', 'A valid commitment type is required.');
  end if;

  v_clean_status := lower(trim(coalesce(p_status, 'active')));
  if v_clean_status not in ('active', 'terminated', 'frozen') then
    v_clean_status := 'active';
  end if;

  if p_person_id is not null then
    select id into v_person_tenant_check
    from public.client_people
    where id = p_person_id and tenant_id = v_tenant_id;

    if v_person_tenant_check is null then
      return jsonb_build_object('ok', false, 'message', 'Person not found in your workspace.');
    end if;
  end if;

  if p_linked_item_id is not null then
    select id into v_item_tenant_check
    from public.business_items
    where id = p_linked_item_id and tenant_id = v_tenant_id;

    if v_item_tenant_check is null then
      return jsonb_build_object('ok', false, 'message', 'Linked unit/site not found in your workspace.');
    end if;
  end if;

  if p_commitment_id is not null then
    update public.ungani_commitments
    set commitment_type = v_clean_type,
        person_id = p_person_id,
        linked_item_id = p_linked_item_id,
        plan_name = nullif(trim(coalesce(p_plan_name, '')), ''),
        amount = p_amount,
        billing_frequency = coalesce(nullif(trim(coalesce(p_billing_frequency, '')), ''), 'monthly'),
        start_date = p_start_date,
        end_date = p_end_date,
        status = v_clean_status,
        auto_renew = coalesce(p_auto_renew, false),
        section_label = nullif(trim(coalesce(p_section_label, '')), ''),
        notes = nullif(trim(coalesce(p_notes, '')), ''),
        updated_at = now()
    where id = p_commitment_id and tenant_id = v_tenant_id
    returning id into v_commitment_id;

    if v_commitment_id is null then
      return jsonb_build_object('ok', false, 'message', 'Commitment not found.');
    end if;
  else
    insert into public.ungani_commitments (
      tenant_id, commitment_type, person_id, linked_item_id, plan_name, amount,
      billing_frequency, start_date, end_date, status, auto_renew, section_label,
      notes, created_by
    )
    values (
      v_tenant_id, v_clean_type, p_person_id, p_linked_item_id,
      nullif(trim(coalesce(p_plan_name, '')), ''), p_amount,
      coalesce(nullif(trim(coalesce(p_billing_frequency, '')), ''), 'monthly'),
      p_start_date, p_end_date, v_clean_status, coalesce(p_auto_renew, false),
      nullif(trim(coalesce(p_section_label, '')), ''), nullif(trim(coalesce(p_notes, '')), ''),
      auth.uid()
    )
    returning id into v_commitment_id;
  end if;

  return jsonb_build_object('ok', true, 'id', v_commitment_id, 'commitment_id', v_commitment_id);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

grant execute on function public.owner_upsert_ungani_commitment(
  uuid, text, uuid, uuid, text, numeric, text, date, date, text, boolean, text, text
) to authenticated;

create or replace function public.get_my_ungani_commitments()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_rows jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', c.id,
      'commitment_type', c.commitment_type,
      'person_id', c.person_id,
      'person_name', p.full_name,
      'linked_item_id', c.linked_item_id,
      'linked_item_name', coalesce(bi.item_name, bi.name, bi.title, bi.property_name),
      'plan_name', c.plan_name,
      'amount', c.amount,
      'billing_frequency', c.billing_frequency,
      'start_date', c.start_date,
      'end_date', c.end_date,
      'status', c.status,
      'auto_renew', c.auto_renew,
      'section_label', c.section_label,
      'notes', c.notes,
      'created_at', c.created_at
    )
    order by c.end_date nulls last, c.created_at desc
  ), '[]'::jsonb)
  into v_rows
  from public.ungani_commitments c
  left join public.client_people p on p.id = c.person_id
  left join public.business_items bi on bi.id = c.linked_item_id
  where c.tenant_id = v_tenant_id
    and c.deleted_at is null;

  return jsonb_build_object('ok', true, 'commitments', v_rows);
end;
$function$;

grant execute on function public.get_my_ungani_commitments() to authenticated;

-- ============================================================
-- PART D: soft_delete_ungani_record() + get_my_ungani_recently_deleted_v2()
-- allowlist additions. Extended from sql/task7-price-lists.sql's own
-- CREATE OR REPLACE bodies (confirmed live) - only the additions below
-- (allowlist entry + title/label branches), every other line unchanged
-- from that confirmed-run version.
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
    'ungani_quotations',
    'ungani_orders',
    'ungani_price_lists',
    'ungani_commitments'
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
  elsif v_table = 'ungani_orders' then
    select coalesce(order_number, 'Order'), coalesce(customer_name, 'Order')
    into v_record_title, v_record_subtitle
    from public.ungani_orders
    where id = p_record_id
    limit 1;
  elsif v_table = 'ungani_price_lists' then
    select coalesce(name, 'Price list'), coalesce(description, 'Price list')
    into v_record_title, v_record_subtitle
    from public.ungani_price_lists
    where id = p_record_id
    limit 1;
  elsif v_table = 'ungani_commitments' then
    select coalesce(plan_name, initcap(replace(commitment_type, '_', ' '))), coalesce(commitment_type, 'Commitment')
    into v_record_title, v_record_subtitle
    from public.ungani_commitments
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
    'ungani_quotations',
    'ungani_orders',
    'ungani_price_lists',
    'ungani_commitments'
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
      when 'ungani_orders' then 'Order'
      when 'ungani_price_lists' then 'Price list'
      when 'ungani_commitments' then 'Lease / Membership / Contract'
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
      when 'ungani_orders' then array[
        'order_number'
      ]
      when 'ungani_price_lists' then array[
        'name'
      ]
      when 'ungani_commitments' then array[
        'plan_name',
        'commitment_type'
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

    if v_table = 'ungani_customer_invoices' then
      v_title_expr := $ov$coalesce(invoice_number, 'Customer invoice') || coalesce(' · ' || nullif(trim(customer_name), ''), '')$ov$;
    elsif v_table = 'ungani_quotations' then
      v_title_expr := $ov$coalesce(quotation_number, 'Quotation') || coalesce(' · ' || nullif(trim(customer_name), ''), '')$ov$;
    elsif v_table = 'ungani_orders' then
      v_title_expr := $ov$coalesce(order_number, 'Order') || coalesce(' · ' || nullif(trim(customer_name), ''), '')$ov$;
    elsif v_table = 'ungani_commitments' then
      v_title_expr := $ov$coalesce(plan_name, initcap(replace(commitment_type, '_', ' '))) || coalesce(' · ends ' || nullif(end_date::text, ''), '')$ov$;
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
-- PART E: One-time backfill - Real Estate ONLY.
--
-- Strictly filtered to business_type_key = 'real_estate' (with a
-- defensive ilike fallback on business_type/business_type_key, matching
-- the precedent in sql/diagnose-business-type-misclassification.sql) so
-- Hospitality's reuse of the same three client_people columns for
-- check-in/checkout is never pulled in here - that's Cluster 1's job,
-- not this one's.
--
-- Also enables commitments_enabled for every real_estate tenant that gets
-- a backfilled row, so existing leases are visible on my-commitments.html
-- immediately after this migration runs, with no separate manual
-- Settings-toggle step required for tenants who already had lease data.
-- ============================================================

insert into public.ungani_commitments (
  tenant_id, commitment_type, person_id, linked_item_id,
  start_date, end_date, status, created_at
)
select
  p.tenant_id,
  'lease',
  p.id,
  p.linked_item_id,
  p.lease_start_date,
  p.lease_end_date,
  'active',
  now()
from public.client_people p
join public.tenants t on t.id = p.tenant_id
where (p.lease_start_date is not null or p.lease_end_date is not null or p.linked_item_id is not null)
  and (
    t.business_type_key = 'real_estate'
    or t.business_type_key ilike '%real_estate%'
    or t.business_type ilike '%real estate%'
  );

update public.tenants t
set commitments_enabled = true
where exists (
  select 1 from public.ungani_commitments c where c.tenant_id = t.id
);

-- ============================================================
-- VERIFICATION - run and paste back the output.
-- ============================================================

select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_commitments'
order by column_name;

select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'tenants' and column_name = 'commitments_enabled';

select routine_name from information_schema.routines
where routine_schema = 'public'
  and routine_name in ('owner_upsert_ungani_commitment', 'get_my_ungani_commitments')
order by routine_name;

select pg_get_functiondef(p.oid) like '%ungani_commitments%' as soft_delete_allowlist_updated
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'soft_delete_ungani_record';

select pg_get_functiondef(p.oid) like '%ungani_commitments%' as recently_deleted_allowlist_updated
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'get_my_ungani_recently_deleted_v2';

select count(*) as backfilled_lease_count from public.ungani_commitments where commitment_type = 'lease';

select t.id, t.company_name, t.business_type_key, t.commitments_enabled, count(c.id) as lease_count
from public.tenants t
join public.ungani_commitments c on c.tenant_id = t.id
group by t.id, t.company_name, t.business_type_key, t.commitments_enabled;
