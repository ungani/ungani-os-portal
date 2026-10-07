-- C2B rent-matching engine: the real feature behind the Paybill
-- connection built earlier this week. Until now, a C2B confirmation
-- just landed as an "Uncategorized" income row with at most a phone-
-- matched related_person_id - no account-number matching, no lease
-- ledger, no partial/overpayment handling, no "Payments to match"
-- queue, no receipts, no owner notification, and the callback had no
-- secret/IP verification at all. This is the full build.
--
-- ============================================================
-- PART A: schema additions.
-- ============================================================

-- Source-IP visibility on every raw callback (log-only check, see
-- MPESA_IP_ALLOWLIST_ENFORCE in api/mpesa-stk-push.js) and a 'rejected'
-- status for a bad/missing token or a blocked IP, distinct from the
-- existing 'received'/'matched'/'unmatched'/'error' states.
alter table public.ungani_mpesa_c2b_callback_log
  add column if not exists source_ip text,
  add column if not exists ip_allowlisted boolean;

-- Per-tenant secret embedded in each tenant's own registered
-- Confirmation/Validation URL (registerC2BUrls now builds a
-- tenant-specific URL instead of one shared URL for everyone - see
-- api/mpesa-stk-push.js). Defaulting every existing + new row to a
-- fresh random token means nothing is ever blank.
alter table public.ungani_tenant_mpesa_connections
  add column if not exists callback_secret_token text not null default encode(gen_random_bytes(24), 'hex');

-- The account number a tenant types into the Paybill's Account Number
-- field. Unique per tenant (not globally) so two different owners can
-- both use "A1" for their own first unit without colliding.
alter table public.business_items
  add column if not exists account_number text;

create unique index if not exists business_items_tenant_account_number_idx
  on public.business_items (tenant_id, upper(regexp_replace(account_number, '[\s-]', '', 'g')))
  where account_number is not null;

-- Running ledger per lease. balance_owed accrues monthly (Part D's
-- cron branch); credit_balance holds unapplied overpayment. Both are
-- always >= 0 by construction - "owed" and "credit" never net against
-- each other except at the moments explicitly described in Part C.
alter table public.ungani_commitments
  add column if not exists balance_owed numeric not null default 0,
  add column if not exists credit_balance numeric not null default 0,
  add column if not exists last_accrued_period text;
  -- 'YYYY-MM' of the last billing period this lease was charged for -
  -- prevents the monthly accrual cron from double-charging a lease it
  -- already ticked this month.

-- Links a payment to the specific lease it was applied against (for
-- Outstanding Rent / statement / Profit-per-property to query), plus
-- the two columns that make a C2B payment idempotent and printable.
alter table public.transactions
  add column if not exists commitment_id uuid references public.ungani_commitments(id) on delete set null,
  add column if not exists mpesa_trans_id text,
  add column if not exists receipt_number text;

create unique index if not exists transactions_tenant_mpesa_trans_id_idx
  on public.transactions (tenant_id, mpesa_trans_id)
  where mpesa_trans_id is not null;

-- "Payments to match" - a C2B payment that couldn't be auto-matched
-- (no account-number hit, no single-active-lease phone match). The
-- owner resolves these one at a time from a dedicated screen; the
-- dashboard Money badge counts status='unmatched' rows.
create table if not exists public.ungani_payments_to_match (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  raw_callback_log_id uuid references public.ungani_mpesa_c2b_callback_log(id) on delete set null,

  trans_id text not null unique,
  bill_ref_number text,
  msisdn text,
  amount numeric not null,
  trans_time timestamptz,

  status text not null default 'unmatched',
  -- 'unmatched' | 'resolved' | 'ignored'

  resolved_person_id uuid references public.client_people(id) on delete set null,
  resolved_commitment_id uuid references public.ungani_commitments(id) on delete set null,
  resolved_transaction_id uuid references public.transactions(id) on delete set null,
  resolved_at timestamptz,
  resolved_by uuid,

  created_at timestamptz not null default now(),

  constraint ungani_payments_to_match_status_check
    check (status in ('unmatched', 'resolved', 'ignored'))
);

create index if not exists ungani_payments_to_match_tenant_status_idx
  on public.ungani_payments_to_match (tenant_id, status);

alter table public.ungani_payments_to_match enable row level security;

drop policy if exists ungani_payments_to_match_owner_select on public.ungani_payments_to_match;
create policy ungani_payments_to_match_owner_select on public.ungani_payments_to_match
  for select
  using (
    tenant_id = public.get_my_ungani_tenant_id()
    and public.is_my_ungani_tenant_owner(tenant_id) is true
  );

grant select on public.ungani_payments_to_match to authenticated;

-- ============================================================
-- PART B: shared matching + ledger-application logic.
--
-- NOT granted to authenticated - this trusts p_tenant_id blindly and
-- is only ever called from (1) the service-role Node endpoint for
-- real Safaricom callbacks, which bypasses RLS as the table owner and
-- resolves tenant_id itself from the matched Shortcode, or (2) the
-- two owner-facing wrapper RPCs below, which resolve tenant_id from
-- auth.uid() FIRST and never let the caller supply their own.
-- ============================================================

create or replace function public.apply_ungani_mpesa_rent_payment(
  p_tenant_id uuid,
  p_trans_id text,
  p_bill_ref_number text,
  p_msisdn text,
  p_amount numeric,
  p_trans_time timestamptz,
  p_source text default 'c2b',
  p_raw_callback_log_id uuid default null,
  p_force_person_id uuid default null,
  p_force_commitment_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_existing_transaction_id uuid;
  v_normalized_ref text;
  v_normalized_phone text;
  v_unit_id uuid;
  -- %ROWTYPE, not a bare `record` - a bare record has NO fields at all
  -- until the first SELECT INTO assigns it, so `v_commitment.id` would
  -- throw "record is not assigned yet" on exactly the unknown-payer
  -- path (neither match branch below ever runs a SELECT INTO it).
  -- %ROWTYPE has every column from declaration, defaulting to NULL.
  v_commitment public.ungani_commitments%rowtype;
  v_person_id uuid;
  v_applied_to_balance numeric := 0;
  v_overpayment numeric := 0;
  v_receipt_seq int;
  v_receipt_number text;
  v_transaction_id uuid;
begin
  -- Idempotency, by trans_id alone (Safaricom's TransID is globally
  -- unique) - a duplicate delivery of an already-recorded payment
  -- (real or CSV-imported) is a no-op success, never a second row.
  select id into v_existing_transaction_id
  from public.transactions
  where tenant_id = p_tenant_id and mpesa_trans_id = p_trans_id
  limit 1;

  if v_existing_transaction_id is not null then
    return jsonb_build_object('ok', true, 'status', 'duplicate', 'transaction_id', v_existing_transaction_id);
  end if;

  if exists (select 1 from public.ungani_payments_to_match where trans_id = p_trans_id and tenant_id = p_tenant_id and status = 'unmatched') then
    return jsonb_build_object('ok', true, 'status', 'already_queued');
  end if;

  -- Matching order, only when the caller hasn't already told us which
  -- lease this is (the "resolve a Payment to match" wrapper passes
  -- p_force_commitment_id directly and skips all of this).
  if p_force_commitment_id is not null then
    v_person_id := p_force_person_id;
    select * into v_commitment from public.ungani_commitments where id = p_force_commitment_id and tenant_id = p_tenant_id;
  else
    -- (a) BillRefNumber, case/space/dash-insensitive, against a unit's
    -- account_number -> that unit's active lease.
    if p_bill_ref_number is not null and btrim(p_bill_ref_number) <> '' then
      v_normalized_ref := upper(regexp_replace(p_bill_ref_number, '[\s-]', '', 'g'));

      select bi.id into v_unit_id
      from public.business_items bi
      where bi.tenant_id = p_tenant_id
        and bi.account_number is not null
        and upper(regexp_replace(bi.account_number, '[\s-]', '', 'g')) = v_normalized_ref
      limit 1;

      if v_unit_id is not null then
        select * into v_commitment
        from public.ungani_commitments
        where tenant_id = p_tenant_id
          and linked_item_id = v_unit_id
          and commitment_type = 'lease'
          and status = 'active'
          and deleted_at is null
        order by created_at desc
        limit 1;

        if v_commitment.id is not null then
          v_person_id := v_commitment.person_id;
        end if;
      end if;
    end if;

    -- (b) else payer phone -> a tenant with exactly one active lease.
    if v_commitment.id is null and p_msisdn is not null then
      v_normalized_phone := regexp_replace(p_msisdn, '\D', '', 'g');
      if length(v_normalized_phone) = 12 and left(v_normalized_phone, 3) = '254' then
        v_normalized_phone := '0' || substring(v_normalized_phone from 4);
      end if;

      declare
        v_candidate_person_id uuid;
        v_match_count int;
      begin
        select cp.id into v_candidate_person_id
        from public.client_people cp
        where cp.tenant_id = p_tenant_id
          and cp.deleted_at is null
          and regexp_replace(coalesce(cp.phone, ''), '\D', '', 'g') like '%' || right(v_normalized_phone, 9)
        limit 1;

        if v_candidate_person_id is not null then
          select count(*) into v_match_count
          from public.ungani_commitments
          where tenant_id = p_tenant_id
            and person_id = v_candidate_person_id
            and commitment_type = 'lease'
            and status = 'active'
            and deleted_at is null;

          if v_match_count = 1 then
            select * into v_commitment
            from public.ungani_commitments
            where tenant_id = p_tenant_id
              and person_id = v_candidate_person_id
              and commitment_type = 'lease'
              and status = 'active'
              and deleted_at is null
            limit 1;
            v_person_id := v_candidate_person_id;
          end if;
        end if;
      end;
    end if;
  end if;

  -- (c) else -> Payments to match.
  if v_commitment.id is null then
    insert into public.ungani_payments_to_match (
      tenant_id, raw_callback_log_id, trans_id, bill_ref_number, msisdn, amount, trans_time
    ) values (
      p_tenant_id, p_raw_callback_log_id, p_trans_id, p_bill_ref_number, p_msisdn, p_amount, p_trans_time
    );

    perform public.create_ungani_notification(
      p_tenant_id,
      'Payment needs matching',
      'Ksh ' || to_char(p_amount, 'FM999,999,999') || ' came in via M-Pesa but could not be auto-matched to a tenant. Assign it from Payments to match.',
      'payment_unmatched',
      'ungani_payments_to_match',
      null,
      'my-payments-to-match.html',
      'high',
      jsonb_build_object('amount', p_amount, 'trans_id', p_trans_id),
      false,
      null
    );

    return jsonb_build_object('ok', true, 'status', 'unmatched');
  end if;

  -- Apply: oldest-owed-first against this lease's running balance.
  -- Partial reduces balance_owed, never below zero. Anything left
  -- over (including a payment made while nothing was owed) becomes
  -- credit_balance, to be drawn down automatically by the next
  -- monthly accrual (Part D) before it adds a fresh charge.
  v_applied_to_balance := least(p_amount, greatest(v_commitment.balance_owed, 0));
  v_overpayment := p_amount - v_applied_to_balance;

  update public.ungani_commitments
  set balance_owed = balance_owed - v_applied_to_balance,
      credit_balance = credit_balance + v_overpayment,
      updated_at = now()
  where id = v_commitment.id;

  select count(*) + 1 into v_receipt_seq
  from public.transactions
  where tenant_id = p_tenant_id and receipt_number is not null;
  v_receipt_number := 'RCT-' || lpad(v_receipt_seq::text, 6, '0');

  insert into public.transactions (
    tenant_id, type, transaction_type, category, amount, currency, exchange_rate, amount_kes,
    transaction_date, payment_method, status, description,
    related_person_id, related_item_id, commitment_id,
    payer_phone, reference_no, mpesa_trans_id, receipt_number,
    created_at, updated_at
  ) values (
    p_tenant_id, 'income', 'income', 'Rental Income', p_amount, 'KES', 1, p_amount,
    coalesce(p_trans_time::date, current_date), 'M-Pesa', 'completed',
    'Rent received via M-Pesa Paybill' || case when p_source = 'csv_import' then ' (imported from statement)' else '' end,
    v_person_id, v_commitment.linked_item_id, v_commitment.id,
    p_msisdn, p_trans_id, p_trans_id, v_receipt_number,
    now(), now()
  )
  returning id into v_transaction_id;

  perform public.create_ungani_notification(
    p_tenant_id,
    'Rent payment received',
    'Ksh ' || to_char(p_amount, 'FM999,999,999') || ' received via M-Pesa' || case when v_overpayment > 0 then ' (Ksh ' || to_char(v_overpayment, 'FM999,999,999') || ' held as credit)' else '' end || '.',
    'payment_received',
    'transactions',
    v_transaction_id,
    'my-money.html',
    'normal',
    jsonb_build_object('amount', p_amount, 'receipt_number', v_receipt_number),
    true,
    null
  );

  return jsonb_build_object(
    'ok', true,
    'status', 'matched',
    'transaction_id', v_transaction_id,
    'commitment_id', v_commitment.id,
    'receipt_number', v_receipt_number,
    'applied_to_balance', v_applied_to_balance,
    'overpayment_as_credit', v_overpayment
  );
end;
$function$;

-- ============================================================
-- PART C: owner-facing wrappers (these ARE granted to authenticated -
-- each resolves tenant_id from auth.uid() itself before ever touching
-- apply_ungani_mpesa_rent_payment, so a caller can never apply a
-- payment against a tenant that isn't their own).
-- ============================================================

create or replace function public.owner_list_ungani_payments_to_match()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null or public.is_my_ungani_tenant_owner(v_tenant_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'Only the business owner can view this.');
  end if;

  return jsonb_build_object(
    'ok', true,
    'payments', coalesce((
      select jsonb_agg(row_to_json(p) order by p.trans_time desc nulls last)
      from public.ungani_payments_to_match p
      where p.tenant_id = v_tenant_id and p.status = 'unmatched'
    ), '[]'::jsonb),
    'active_leases', coalesce((
      select jsonb_agg(jsonb_build_object(
        'commitment_id', c.id,
        'person_id', c.person_id,
        'person_name', cp.full_name,
        'unit_id', c.linked_item_id,
        'unit_name', coalesce(bi.item_name, bi.name, bi.title)
      ))
      from public.ungani_commitments c
      join public.client_people cp on cp.id = c.person_id
      left join public.business_items bi on bi.id = c.linked_item_id
      where c.tenant_id = v_tenant_id
        and c.commitment_type = 'lease'
        and c.status = 'active'
        and c.deleted_at is null
    ), '[]'::jsonb)
  );
end;
$function$;

grant execute on function public.owner_list_ungani_payments_to_match() to authenticated;

create or replace function public.owner_get_ungani_payments_to_match_count()
returns integer
language sql
security definer
set search_path to 'public'
stable
as $function$
  select count(*)::int
  from public.ungani_payments_to_match
  where tenant_id = public.get_my_ungani_tenant_id()
    and status = 'unmatched';
$function$;

grant execute on function public.owner_get_ungani_payments_to_match_count() to authenticated;

create or replace function public.owner_resolve_ungani_payment_to_match(
  p_payment_id uuid,
  p_person_id uuid,
  p_commitment_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_payment record;
  v_apply_result jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null or public.is_my_ungani_tenant_owner(v_tenant_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'Only the business owner can resolve payments.');
  end if;

  select * into v_payment
  from public.ungani_payments_to_match
  where id = p_payment_id and tenant_id = v_tenant_id and status = 'unmatched';

  if v_payment.id is null then
    return jsonb_build_object('ok', false, 'message', 'Payment not found or already resolved.');
  end if;

  if not exists (select 1 from public.ungani_commitments where id = p_commitment_id and tenant_id = v_tenant_id and person_id = p_person_id) then
    return jsonb_build_object('ok', false, 'message', 'That lease does not belong to this tenant.');
  end if;

  v_apply_result := public.apply_ungani_mpesa_rent_payment(
    v_tenant_id, v_payment.trans_id, v_payment.bill_ref_number, v_payment.msisdn, v_payment.amount, v_payment.trans_time,
    'manual_resolve', v_payment.raw_callback_log_id, p_person_id, p_commitment_id
  );

  update public.ungani_payments_to_match
  set status = 'resolved',
      resolved_person_id = p_person_id,
      resolved_commitment_id = p_commitment_id,
      resolved_transaction_id = (v_apply_result->>'transaction_id')::uuid,
      resolved_at = now(),
      resolved_by = auth.uid()
  where id = p_payment_id;

  return v_apply_result;
end;
$function$;

grant execute on function public.owner_resolve_ungani_payment_to_match(uuid, uuid, uuid) to authenticated;

-- CSV statement safety net - every row goes through the exact same
-- apply function, so a row whose TransID is already recorded (whether
-- originally captured via the live callback or a prior upload) is
-- silently skipped, never duplicated.
create or replace function public.owner_bulk_import_ungani_mpesa_statement(p_rows jsonb)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_row jsonb;
  v_result jsonb;
  v_imported int := 0;
  v_skipped int := 0;
  v_unmatched int := 0;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null or public.is_my_ungani_tenant_owner(v_tenant_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'Only the business owner can import a statement.');
  end if;

  for v_row in select * from jsonb_array_elements(coalesce(p_rows, '[]'::jsonb))
  loop
    v_result := public.apply_ungani_mpesa_rent_payment(
      v_tenant_id,
      v_row->>'trans_id',
      v_row->>'bill_ref_number',
      v_row->>'msisdn',
      (v_row->>'amount')::numeric,
      (v_row->>'trans_time')::timestamptz,
      'csv_import',
      null
    );

    if v_result->>'status' = 'duplicate' or v_result->>'status' = 'already_queued' then
      v_skipped := v_skipped + 1;
    elsif v_result->>'status' = 'unmatched' then
      v_unmatched := v_unmatched + 1;
    else
      v_imported := v_imported + 1;
    end if;
  end loop;

  return jsonb_build_object('ok', true, 'imported', v_imported, 'skipped_duplicates', v_skipped, 'queued_unmatched', v_unmatched);
end;
$function$;

grant execute on function public.owner_bulk_import_ungani_mpesa_statement(jsonb) to authenticated;

-- ============================================================
-- PART D: monthly rent accrual (called from the renamed webhook file
-- via a new vercel.json cron entry hitting it with a cron purpose,
-- not a 13th serverless function - see api/payments-callback.js).
-- ============================================================

create or replace function public.service_accrue_ungani_monthly_rent()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_period text := to_char(current_date, 'YYYY-MM');
  v_lease record;
  v_charge numeric;
  v_count int := 0;
begin
  for v_lease in
    select *
    from public.ungani_commitments
    where commitment_type = 'lease'
      and status = 'active'
      and deleted_at is null
      and coalesce(amount, 0) > 0
      and start_date <= current_date
      and extract(day from start_date) = extract(day from current_date)
      and coalesce(last_accrued_period, '') <> v_period
  loop
    v_charge := v_lease.amount;

    if v_lease.credit_balance >= v_charge then
      update public.ungani_commitments
      set credit_balance = credit_balance - v_charge,
          last_accrued_period = v_period,
          updated_at = now()
      where id = v_lease.id;
    else
      update public.ungani_commitments
      set balance_owed = balance_owed + (v_charge - credit_balance),
          credit_balance = 0,
          last_accrued_period = v_period,
          updated_at = now()
      where id = v_lease.id;
    end if;

    v_count := v_count + 1;
  end loop;

  return jsonb_build_object('ok', true, 'leases_accrued', v_count, 'period', v_period);
end;
$function$;

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================
select proname
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in (
    'apply_ungani_mpesa_rent_payment',
    'owner_list_ungani_payments_to_match',
    'owner_get_ungani_payments_to_match_count',
    'owner_resolve_ungani_payment_to_match',
    'owner_bulk_import_ungani_mpesa_statement',
    'service_accrue_ungani_monthly_rent'
  )
order by proname;
