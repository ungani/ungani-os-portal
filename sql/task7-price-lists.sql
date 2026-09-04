-- Task 7: Price Lists.
--
-- Investigation before building anything found the foundational price
-- field this depends on already exists, universally, for every business
-- type - NOT just real estate as first assumed. saveItem() in
-- my-items.html (confirmed via reading the real save payload, not
-- guessed) writes every business type's "Price / Value" form field into
-- business_items.property_price unconditionally - the column name is a
-- historical holdover from real estate being built first, but it's a
-- real, live, generically-used value already (also read the same way by
-- ungani-analytics.js, my-overview.html, my-activity.html,
-- my-item-profile.html with no real-estate-only guard anywhere).
-- selling_price/cost_price, by contrast, really are dead - confirmed via
-- an existing code comment describing an earlier repo-wide sweep - but
-- that's an unrelated, already-fixed bug, not evidence against
-- property_price.
--
-- Because of that, this migration does NOT add a new price column to
-- business_items or touch the Items form at all - there is nothing
-- missing at that layer. What's genuinely missing, and all this
-- migration adds, is the TIERING layer on top of the price that already
-- exists: named price lists holding per-item overrides of
-- property_price, for use when creating a Quotation/Invoice/Order.
--
-- Per user decision: gated behind tenants.price_lists_enabled (like
-- Stock Tracking/Debtors & Payables, not ungated like
-- Quotations/Orders) - this feature adds new UI surface (item pickers on
-- Quotations/Invoices, a pricing selector on all three) that most
-- business types without priced inventory (real estate, healthcare,
-- salons, security, etc.) don't need to see by default. No backfill
-- step is needed on enable (unlike Stock Tracking), so - matching
-- Debtors & Payables' simpler precedent - there's no dedicated
-- enable/disable RPC, just a plain tenants column the Settings page
-- updates directly.
--
-- Also proactively adds ungani_price_lists to soft_delete_ungani_record()
-- and get_my_ungani_recently_deleted_v2()'s allowlists in this same
-- migration - the same gap every prior task in this series has hit.
-- Extended from sql/task6-orders.sql's own CREATE OR REPLACE bodies,
-- confirmed live (all 5 of that migration's verification checks
-- passed) - not fabricated.

-- ============================================================
-- PART A: Price Lists toggle.
-- ============================================================

alter table public.tenants
  add column if not exists price_lists_enabled boolean not null default false;

-- ============================================================
-- PART B: Named price lists.
-- ============================================================

create table if not exists public.ungani_price_lists (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  name text not null,
  description text,

  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),

  deleted_at timestamptz,
  deleted_by uuid,
  delete_reason text,
  restored_at timestamptz,
  restored_by uuid,

  constraint ungani_price_lists_name_unique
    unique (tenant_id, name)
);

alter table public.ungani_price_lists enable row level security;

drop policy if exists ungani_price_lists_tenant_select on public.ungani_price_lists;
create policy ungani_price_lists_tenant_select on public.ungani_price_lists
  for select
  using (tenant_id = public.get_my_ungani_tenant_id());

grant select on public.ungani_price_lists to authenticated;

-- ============================================================
-- PART C: Per-item price overrides within a list.
-- ============================================================

create table if not exists public.ungani_price_list_items (
  id uuid primary key default gen_random_uuid(),
  price_list_id uuid not null references public.ungani_price_lists(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  item_id uuid not null references public.business_items(id) on delete cascade,
  price numeric not null,
  created_at timestamptz not null default now(),

  constraint ungani_price_list_items_unique
    unique (price_list_id, item_id)
);

alter table public.ungani_price_list_items enable row level security;

drop policy if exists ungani_price_list_items_tenant_select on public.ungani_price_list_items;
create policy ungani_price_list_items_tenant_select on public.ungani_price_list_items
  for select
  using (tenant_id = public.get_my_ungani_tenant_id());

grant select on public.ungani_price_list_items to authenticated;

-- ============================================================
-- PART D: RPCs.
-- ============================================================

-- Create/edit a price list. Unlike Quotations/Orders, a price list is a
-- plain lookup table with no lifecycle/lock states - it's always safely
-- re-editable, so delete-and-reinsert entries on every save is fine with
-- no fulfilment-style "has this started being used yet" guard needed.
create or replace function public.owner_upsert_ungani_price_list(
  p_price_list_id uuid default null,
  p_name text default null,
  p_description text default null,
  p_entries jsonb default '[]'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_price_list_id uuid;
  v_clean_name text;
  v_entry jsonb;
  v_item_id uuid;
  v_price numeric;
  v_item_tenant_check uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  v_clean_name := nullif(trim(coalesce(p_name, '')), '');

  if v_clean_name is null then
    return jsonb_build_object('ok', false, 'message', 'A name is required for this price list.');
  end if;

  if p_price_list_id is not null then
    update public.ungani_price_lists
    set name = v_clean_name,
        description = nullif(trim(coalesce(p_description, '')), ''),
        updated_at = now()
    where id = p_price_list_id and tenant_id = v_tenant_id
    returning id into v_price_list_id;

    if v_price_list_id is null then
      return jsonb_build_object('ok', false, 'message', 'Price list not found.');
    end if;

    delete from public.ungani_price_list_items where price_list_id = v_price_list_id;
  else
    insert into public.ungani_price_lists (tenant_id, name, description, created_by)
    values (v_tenant_id, v_clean_name, nullif(trim(coalesce(p_description, '')), ''), auth.uid())
    returning id into v_price_list_id;
  end if;

  for v_entry in select * from jsonb_array_elements(coalesce(p_entries, '[]'::jsonb))
  loop
    v_item_id := nullif(v_entry->>'item_id', '')::uuid;
    v_price := nullif(v_entry->>'price', '')::numeric;

    -- Skip entries missing either half of the pair, or pointing at an
    -- item that doesn't belong to this tenant (e.g. stale client-side
    -- state) - same "drop rather than fail the whole save" precedent as
    -- Orders' item_id validation.
    if v_item_id is null or v_price is null then
      continue;
    end if;

    select id into v_item_tenant_check
    from public.business_items
    where id = v_item_id and tenant_id = v_tenant_id;

    if v_item_tenant_check is null then
      continue;
    end if;

    insert into public.ungani_price_list_items (price_list_id, tenant_id, item_id, price)
    values (v_price_list_id, v_tenant_id, v_item_id, v_price)
    on conflict (price_list_id, item_id) do update set price = excluded.price;
  end loop;

  return jsonb_build_object('ok', true, 'id', v_price_list_id, 'price_list_id', v_price_list_id);
exception
  when unique_violation then
    return jsonb_build_object('ok', false, 'message', 'You already have a price list with that name.');
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

grant execute on function public.owner_upsert_ungani_price_list(uuid, text, text, jsonb) to authenticated;

-- List view - includes item_count so the list page can show "12 items
-- priced" without a separate query per row.
create or replace function public.get_my_ungani_price_lists()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_lists jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', pl.id,
      'name', pl.name,
      'description', pl.description,
      'item_count', (select count(*) from public.ungani_price_list_items pli where pli.price_list_id = pl.id),
      'created_at', pl.created_at
    )
    order by pl.name
  ), '[]'::jsonb)
  into v_lists
  from public.ungani_price_lists pl
  where pl.tenant_id = v_tenant_id
    and pl.deleted_at is null;

  return jsonb_build_object('ok', true, 'price_lists', v_lists);
end;
$function$;

grant execute on function public.get_my_ungani_price_lists() to authenticated;

-- Single-list detail (entries, with the item's own name/current
-- property_price joined in so the edit page can show both the override
-- and the item's base price side by side).
create or replace function public.get_ungani_price_list_detail(p_price_list_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_price_list jsonb;
  v_entries jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select to_jsonb(pl) into v_price_list
  from public.ungani_price_lists pl
  where pl.id = p_price_list_id and pl.tenant_id = v_tenant_id;

  if v_price_list is null then
    return jsonb_build_object('ok', false, 'message', 'Price list not found.');
  end if;

  select coalesce(jsonb_agg(
    jsonb_build_object(
      'id', pli.id,
      'item_id', pli.item_id,
      'item_name', coalesce(bi.item_name, bi.name, bi.title, bi.property_name, 'Item'),
      'base_price', bi.property_price,
      'price', pli.price
    )
    order by coalesce(bi.item_name, bi.name, bi.title, bi.property_name, 'Item')
  ), '[]'::jsonb)
  into v_entries
  from public.ungani_price_list_items pli
  join public.business_items bi on bi.id = pli.item_id
  where pli.price_list_id = p_price_list_id;

  return jsonb_build_object('ok', true, 'price_list', v_price_list, 'entries', v_entries);
end;
$function$;

grant execute on function public.get_ungani_price_list_detail(uuid) to authenticated;

-- ============================================================
-- PART E: soft_delete_ungani_record() allowlist addition.
-- Extended from sql/task6-orders.sql's own body (confirmed live) - only
-- the two additions below (allowlist entry + title branch), every other
-- line is unchanged from that confirmed-run version.
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
    'ungani_price_lists'
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
-- Extended from sql/task6-orders.sql's own body (confirmed live) - only
-- the additions below (table array entry, label, title candidates),
-- every other line is unchanged from that confirmed-run version. Price
-- lists don't need the combined-title exception invoices/quotations/
-- orders got (number + customer name) - a list's own name is already
-- the meaningful title on its own, no second identifier needed.
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
    'ungani_quotations',
    'ungani_orders',
    'ungani_price_lists'
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

    -- Invoices, quotations, and orders all need their number AND the
    -- customer name to be meaningful in this list - price lists don't,
    -- their own name column (handled generically above) is enough.
    if v_table = 'ungani_customer_invoices' then
      v_title_expr := $ov$coalesce(invoice_number, 'Customer invoice') || coalesce(' · ' || nullif(trim(customer_name), ''), '')$ov$;
    elsif v_table = 'ungani_quotations' then
      v_title_expr := $ov$coalesce(quotation_number, 'Quotation') || coalesce(' · ' || nullif(trim(customer_name), ''), '')$ov$;
    elsif v_table = 'ungani_orders' then
      v_title_expr := $ov$coalesce(order_number, 'Order') || coalesce(' · ' || nullif(trim(customer_name), ''), '')$ov$;
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
where table_schema = 'public' and table_name in ('ungani_price_lists', 'ungani_price_list_items')
order by table_name, column_name;

select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'tenants' and column_name = 'price_lists_enabled';

select routine_name from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'owner_upsert_ungani_price_list',
    'get_my_ungani_price_lists',
    'get_ungani_price_list_detail'
  )
order by routine_name;

select pg_get_functiondef(p.oid) like '%ungani_price_lists%' as soft_delete_allowlist_updated
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'soft_delete_ungani_record';

select pg_get_functiondef(p.oid) like '%ungani_price_lists%' as recently_deleted_allowlist_updated
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'get_my_ungani_recently_deleted_v2';
