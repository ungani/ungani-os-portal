-- Car Showroom foundation migration.
--
-- Design decisions (so the "why" survives past this session):
--
-- 1. Vehicle costs (duty/clearing/transport/repair/other) are NOT a new
--    table. transactions.related_item_id already exists (same column
--    Purchases/stock-in uses via related_purchase_id's sibling pattern) -
--    recording each cost as a plain expense transaction with
--    related_item_id = the car's business_items.id means it shows in
--    Money automatically, and profit-per-car is just
--    "sum(transactions where related_item_id = car) vs sale proceeds" -
--    the exact same ledger Money already reconciles, so it can never be
--    double-counted against a separate ledger.
--
-- 2. Trade-in value is NETTED INTO total_amount at invoice-creation time
--    (like a discount), not added to amount_paid. trade_in_item_id/
--    trade_in_value below are audit-trail columns only - every existing
--    "balance owed = total_amount - amount_paid" calculation anywhere in
--    the app needs zero changes, and it is structurally impossible for
--    trade-in value to leak into a cash-received figure, because nothing
--    ever adds it to amount_paid in the first place.
--
-- 3. Consignment commission reuses business_items.management_commission_type
--    / management_commission_value (already exist, unused by car_showroom
--    otherwise) instead of new columns.
--
-- 4. Only 7 genuinely new real columns on business_items (not JSONB, per
--    Chris's explicit list: VIN, new/used, own/consignment, imported/
--    local, logbook status, plus minimum_price and the consignment owner
--    link). current_status (already exists, defaults 'available') is
--    reused for the vehicle status field itself - no new status column.
--
-- 5. owner_set_ungani_vehicle_status() is the ONE path for Available/
--    Reserved/Sold/In transit/In repair. It is idempotent by
--    construction (sets an absolute state, not a delta), not by a
--    duplicate-call guard - calling it twice with the same target status
--    is a provable no-op. Car Showroom tenants never enable
--    stock_tracking_enabled, so sync_ungani_invoice_stock's own existing
--    gate (SET search_path confirmed this session: "gated on
--    tenants.stock_tracking_enabled") already structurally excludes them
--    even if an invoice line references a car's item_id - no new guard
--    needed there.

begin;

-------------------------------------------------------------------------
-- 1. business_items: 7 new real columns (not JSONB - filtered/searched/
--    reported per Chris's explicit list).
-------------------------------------------------------------------------
alter table public.business_items
  add column if not exists vin_number text,
  add column if not exists condition_type text,
  add column if not exists ownership_type text,
  add column if not exists sourcing_type text,
  add column if not exists logbook_status text,
  add column if not exists minimum_price numeric,
  add column if not exists consignment_owner_person_id uuid references public.client_people(id);

alter table public.business_items
  drop constraint if exists business_items_condition_type_check;
alter table public.business_items
  add constraint business_items_condition_type_check
  check (condition_type is null or condition_type in ('new', 'used'));

alter table public.business_items
  drop constraint if exists business_items_ownership_type_check;
alter table public.business_items
  add constraint business_items_ownership_type_check
  check (ownership_type is null or ownership_type in ('own_stock', 'consignment'));

alter table public.business_items
  drop constraint if exists business_items_sourcing_type_check;
alter table public.business_items
  add constraint business_items_sourcing_type_check
  check (sourcing_type is null or sourcing_type in ('imported', 'local'));

-- Unique per tenant, only when populated - irrelevant to the other 18
-- types since they will never write to this column.
create unique index if not exists uq_business_items_vin_per_tenant
  on public.business_items (tenant_id, vin_number)
  where vin_number is not null;

-------------------------------------------------------------------------
-- 2. ungani_customer_invoices: trade-in audit columns (not counted as
--    cash received - see design note 2 above).
-------------------------------------------------------------------------
alter table public.ungani_customer_invoices
  add column if not exists trade_in_item_id uuid references public.business_items(id),
  add column if not exists trade_in_value numeric;

-------------------------------------------------------------------------
-- 3. ungani_inquiries: new table (confirmed via repo-wide grep - no
--    existing leads/inquiries table to reuse).
-------------------------------------------------------------------------
create table if not exists public.ungani_inquiries (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  customer_name text not null,
  customer_person_id uuid references public.client_people(id),
  vehicle_item_id uuid references public.business_items(id),
  source text,
  follow_up_date date,
  test_drive_at timestamptz,
  status text not null default 'new',
  notes text,
  created_by uuid,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  deleted_at timestamptz,
  deleted_by uuid,
  delete_reason text,
  restored_at timestamptz,
  restored_by uuid
);

alter table public.ungani_inquiries
  drop constraint if exists ungani_inquiries_status_check;
alter table public.ungani_inquiries
  add constraint ungani_inquiries_status_check
  check (status in ('new', 'contacted', 'test_drive_booked', 'won', 'lost'));

create index if not exists idx_ungani_inquiries_tenant_id on public.ungani_inquiries (tenant_id);
create index if not exists idx_ungani_inquiries_vehicle_item_id on public.ungani_inquiries (vehicle_item_id);

alter table public.ungani_inquiries enable row level security;

drop policy if exists ungani_inquiries_select_own_tenant on public.ungani_inquiries;
create policy ungani_inquiries_select_own_tenant on public.ungani_inquiries
  for select
  using (
    tenant_id = public.get_my_ungani_current_tenant_id_v16()
    or public.is_ungani_admin()
  );

-- Writes go through owner_upsert_ungani_inquiry() only (SECURITY DEFINER,
-- validates + derives tenant_id itself) - same pattern as Commitments.
-- No direct INSERT/UPDATE/DELETE policy is added.

revoke all on public.ungani_inquiries from public, anon;
grant select on public.ungani_inquiries to authenticated;

-------------------------------------------------------------------------
-- 4. Extend the two shared soft-delete functions (live bodies pulled
--    fresh this session) to cover ungani_inquiries - byte-identical to
--    live except the one allowlist/branch addition each, same approach
--    as the Commitments fix earlier this session.
-------------------------------------------------------------------------
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
    'ungani_commitments',
    'ungani_inquiries'
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
  elsif v_table = 'ungani_inquiries' then
    select coalesce(customer_name, 'Inquiry'), coalesce(status, 'Inquiry')
    into v_record_title, v_record_subtitle
    from public.ungani_inquiries
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
    'ungani_commitments',
    'ungani_inquiries'
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
      when 'ungani_inquiries' then 'Inquiry'
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
        'document_title',
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
      when 'ungani_inquiries' then array[
        'customer_name'
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
    elsif v_table = 'ungani_inquiries' then
      v_title_expr := $ov$coalesce(customer_name, 'Inquiry') || coalesce(' · ' || initcap(replace(status, '_', ' ')), '')$ov$;
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

-------------------------------------------------------------------------
-- 5. owner_upsert_ungani_inquiry() - the write path for Inquiries.
-------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.owner_upsert_ungani_inquiry(
  p_inquiry_id uuid DEFAULT NULL::uuid,
  p_customer_name text DEFAULT NULL::text,
  p_customer_person_id uuid DEFAULT NULL::uuid,
  p_vehicle_item_id uuid DEFAULT NULL::uuid,
  p_source text DEFAULT NULL::text,
  p_follow_up_date date DEFAULT NULL::date,
  p_test_drive_at timestamptz DEFAULT NULL::timestamptz,
  p_status text DEFAULT 'new'::text,
  p_notes text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_inquiry_id uuid;
  v_clean_name text;
  v_clean_status text;
  v_person_check uuid;
  v_vehicle_check uuid;
begin
  v_tenant_id := public.get_my_ungani_current_tenant_id_v16();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.can_write_ungani_client_data() and not public.is_ungani_admin() then
    return jsonb_build_object('ok', false, 'message', 'This account is currently read-only.');
  end if;

  v_clean_name := nullif(trim(coalesce(p_customer_name, '')), '');
  if v_clean_name is null then
    return jsonb_build_object('ok', false, 'message', 'Customer name is required.');
  end if;

  v_clean_status := lower(trim(coalesce(p_status, 'new')));
  if v_clean_status not in ('new', 'contacted', 'test_drive_booked', 'won', 'lost') then
    v_clean_status := 'new';
  end if;

  if p_customer_person_id is not null then
    select id into v_person_check from public.client_people
    where id = p_customer_person_id and tenant_id = v_tenant_id;

    if v_person_check is null then
      return jsonb_build_object('ok', false, 'message', 'Person not found in your workspace.');
    end if;
  end if;

  if p_vehicle_item_id is not null then
    select id into v_vehicle_check from public.business_items
    where id = p_vehicle_item_id and tenant_id = v_tenant_id;

    if v_vehicle_check is null then
      return jsonb_build_object('ok', false, 'message', 'Vehicle not found in your workspace.');
    end if;
  end if;

  if p_inquiry_id is not null then
    update public.ungani_inquiries
    set customer_name = v_clean_name,
        customer_person_id = p_customer_person_id,
        vehicle_item_id = p_vehicle_item_id,
        source = nullif(trim(coalesce(p_source, '')), ''),
        follow_up_date = p_follow_up_date,
        test_drive_at = p_test_drive_at,
        status = v_clean_status,
        notes = nullif(trim(coalesce(p_notes, '')), ''),
        updated_at = now()
    where id = p_inquiry_id and tenant_id = v_tenant_id
    returning id into v_inquiry_id;

    if v_inquiry_id is null then
      return jsonb_build_object('ok', false, 'message', 'Inquiry not found.');
    end if;
  else
    insert into public.ungani_inquiries (
      tenant_id, customer_name, customer_person_id, vehicle_item_id,
      source, follow_up_date, test_drive_at, status, notes, created_by
    )
    values (
      v_tenant_id, v_clean_name, p_customer_person_id, p_vehicle_item_id,
      nullif(trim(coalesce(p_source, '')), ''), p_follow_up_date, p_test_drive_at,
      v_clean_status, nullif(trim(coalesce(p_notes, '')), ''), auth.uid()
    )
    returning id into v_inquiry_id;
  end if;

  return jsonb_build_object('ok', true, 'id', v_inquiry_id, 'inquiry_id', v_inquiry_id);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.owner_upsert_ungani_inquiry(
  uuid, text, uuid, uuid, text, date, timestamptz, text, text
) from public, anon;
grant execute on function public.owner_upsert_ungani_inquiry(
  uuid, text, uuid, uuid, text, date, timestamptz, text, text
) to authenticated;

-------------------------------------------------------------------------
-- 6. owner_set_ungani_vehicle_status() - the single, idempotent path for
--    Available/Reserved/Sold/In transit/In repair. Sets current_status
--    and quantity (1 while anything but sold, 0 when sold) as an
--    absolute state, not a delta - calling it twice with the same target
--    status is a provable no-op.
-------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.owner_set_ungani_vehicle_status(
  p_vehicle_item_id uuid,
  p_new_status text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_clean_status text;
  v_vehicle_tenant_id uuid;
begin
  v_tenant_id := public.get_my_ungani_current_tenant_id_v16();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not public.can_write_ungani_client_data() and not public.is_ungani_admin() then
    return jsonb_build_object('ok', false, 'message', 'This account is currently read-only.');
  end if;

  v_clean_status := lower(trim(coalesce(p_new_status, '')));
  if v_clean_status not in ('available', 'reserved', 'sold', 'in_transit', 'in_repair') then
    return jsonb_build_object('ok', false, 'message', 'A valid vehicle status is required.');
  end if;

  select tenant_id into v_vehicle_tenant_id
  from public.business_items
  where id = p_vehicle_item_id;

  if v_vehicle_tenant_id is null or v_vehicle_tenant_id <> v_tenant_id then
    return jsonb_build_object('ok', false, 'message', 'Vehicle not found in your workspace.');
  end if;

  update public.business_items
  set current_status = v_clean_status,
      quantity = case when v_clean_status = 'sold' then 0 else 1 end,
      updated_at = now()
  where id = p_vehicle_item_id and tenant_id = v_tenant_id;

  return jsonb_build_object('ok', true, 'id', p_vehicle_item_id, 'status', v_clean_status);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.owner_set_ungani_vehicle_status(uuid, text) from public, anon;
grant execute on function public.owner_set_ungani_vehicle_status(uuid, text) to authenticated;

commit;

-- Verification (read-only, safe to run any time after the above commits).
select 'business_items new columns' as check_name,
       count(*) as actual, 7 as expected
from information_schema.columns
where table_schema = 'public' and table_name = 'business_items'
  and column_name in ('vin_number', 'condition_type', 'ownership_type', 'sourcing_type', 'logbook_status', 'minimum_price', 'consignment_owner_person_id')

union all

select 'invoice trade-in columns', count(*), 2
from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_customer_invoices'
  and column_name in ('trade_in_item_id', 'trade_in_value')

union all

select 'ungani_inquiries table exists', count(*), 1
from information_schema.tables
where table_schema = 'public' and table_name = 'ungani_inquiries'

union all

select 'soft-delete allowlist includes ungani_inquiries',
       (select count(*) from pg_proc where proname = 'soft_delete_ungani_record' and pronamespace = 'public'::regnamespace and prosrc ilike '%ungani_inquiries%'),
       1

union all

select 'recently-deleted v2 includes ungani_inquiries',
       (select count(*) from pg_proc where proname = 'get_my_ungani_recently_deleted_v2' and pronamespace = 'public'::regnamespace and prosrc ilike '%ungani_inquiries%'),
       1

union all

select 'new functions granted to authenticated only',
       (select count(*) from information_schema.routine_privileges
        where routine_schema = 'public' and grantee = 'authenticated'
          and routine_name in ('owner_upsert_ungani_inquiry', 'owner_set_ungani_vehicle_status')),
       2;
