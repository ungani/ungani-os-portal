-- Rules 1-7 from the user: invoices join the rent ledger as one unified
-- system. Builds on sql/mpesa-c2b-rent-matching-engine.sql (read in full
-- before writing this - every signature below matches what's actually
-- live) and sql/connect-invoice-payments-to-money.sql (same - the
-- refactor below is a faithful split of that file's real body, not a
-- rewrite from memory).
--
-- Design decisions worth flagging:
--   - Rule 1 (block rent invoices on an active lease) is enforced by a
--     TRIGGER on ungani_customer_invoices, not by touching
--     owner_upsert_ungani_customer_invoice. That function has been
--     edited by ~15 other migrations and I have not read its current
--     full body - adding a parameter to it risks exactly the
--     overload-collision bug this codebase has hit before
--     (sql/deposits-fix-settle-overload.sql). A trigger enforces the
--     rule regardless of which RPC performs the insert/update, with
--     zero risk to that function. invoice_type is set via a new,
--     separate, tiny RPC (owner_set_ungani_invoice_type) instead.
--   - Rule 2's "oldest owed first across lease and invoices": the lease
--     balance_owed is always treated as the older bucket (rent accrues
--     monthly with no per-period row to compare a due_date against),
--     open invoices (extras only, by construction of rule 1) are drained
--     next by due_date ascending, and anything left becomes credit on
--     the lease. This is a judgment call where the data model doesn't
--     carry enough information to interleave the two by date - flagging
--     it explicitly rather than silently assuming.
--   - The cash-received transaction amount for the "lease bucket" is
--     p_amount minus whatever was separately receipted to invoices (so
--     it includes any overpayment-as-credit) - this matches the
--     ALREADY-LIVE behavior of apply_ungani_mpesa_rent_payment, which
--     records the full amount as income even when part of it becomes
--     credit_balance, not a deferred/unrecognized amount.
--
-- SQL first, deploy after. Every new/changed function has an explicit
-- revoke-all-from-public/anon/authenticated before its real grant.
--
-- Whole file is one transaction (BEGIN ... COMMIT at the very bottom) -
-- all-or-nothing. If anything in here errors, nothing in here lands:
-- no half-applied schema, no function left in a stale state.

begin;

-- ============================================================
-- PART A: schema additions.
-- ============================================================

alter table public.ungani_customer_invoices
  add column if not exists invoice_type text not null default 'general'
    check (invoice_type in ('general', 'rent'));

alter table public.ungani_commitments
  add column if not exists opening_balance_amount numeric,
  add column if not exists opening_balance_set_at timestamptz;

alter table public.transactions
  add column if not exists related_invoice_id uuid
    references public.ungani_customer_invoices(id) on delete set null,
  add column if not exists related_invoice_payment_id uuid
    references public.ungani_customer_invoice_payments(id) on delete set null;
-- (the two lines above are identical to sql/connect-invoice-payments-to-money.sql -
-- `add column if not exists` so re-running this file is a no-op if that
-- migration already ran, and NOT an error if it didn't.)

create index if not exists transactions_related_invoice_id_idx
  on public.transactions(related_invoice_id);
create index if not exists transactions_related_invoice_payment_id_idx
  on public.transactions(related_invoice_payment_id);

-- ============================================================
-- PART B: Rule 1 - rent is never billed twice.
-- Trigger-based, independent of owner_upsert_ungani_customer_invoice's
-- own (unread, multiply-revised) body. Fires on insert, and on any
-- update that actually changes invoice_type - so owner_set_ungani_
-- invoice_type (Part B2) is covered too.
-- ============================================================

create or replace function public.ungani_block_duplicate_rent_invoice()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
begin
  if new.invoice_type = 'rent' and new.customer_person_id is not null then
    if exists (
      select 1 from public.ungani_commitments c
      where c.tenant_id = new.tenant_id
        and c.person_id = new.customer_person_id
        and c.commitment_type = 'lease'
        and c.status = 'active'
        and c.deleted_at is null
    ) then
      raise exception 'This customer has an active lease - rent is tracked on the lease balance, not a separate invoice. Use the lease ledger instead.';
    end if;
  end if;
  return new;
end;
$function$;

revoke all on function public.ungani_block_duplicate_rent_invoice() from public, anon, authenticated;

drop trigger if exists ungani_block_duplicate_rent_invoice_trg on public.ungani_customer_invoices;
create trigger ungani_block_duplicate_rent_invoice_trg
before insert or update of invoice_type on public.ungani_customer_invoices
for each row execute function public.ungani_block_duplicate_rent_invoice();

create or replace function public.owner_set_ungani_invoice_type(
  p_invoice_id uuid,
  p_invoice_type text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_clean_type text := lower(trim(coalesce(p_invoice_type, 'general')));
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if v_clean_type not in ('general', 'rent') then
    return jsonb_build_object('ok', false, 'message', 'Invalid invoice type.');
  end if;

  update public.ungani_customer_invoices
  set invoice_type = v_clean_type, updated_at = now()
  where id = p_invoice_id and tenant_id = v_tenant_id;

  if not found then
    return jsonb_build_object('ok', false, 'message', 'Invoice not found.');
  end if;

  return jsonb_build_object('ok', true, 'invoice_type', v_clean_type);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.owner_set_ungani_invoice_type(uuid, text) from public, anon, authenticated;
grant execute on function public.owner_set_ungani_invoice_type(uuid, text) to authenticated;

-- ============================================================
-- PART C: Rule 2 - one apply function, oldest-owed-first across lease
-- and invoices. apply_ungani_invoice_payment is record_ungani_invoice_
-- payment's REAL body (sql/connect-invoice-payments-to-money.sql:58-169,
-- read in full above), split so it can be called with an explicit
-- tenant_id instead of resolving auth.uid() itself - the only way a
-- service-role/no-session caller (the ledger function below) can use it.
-- ============================================================

create or replace function public.apply_ungani_invoice_payment(
  p_tenant_id uuid,
  p_invoice_id uuid,
  p_amount numeric,
  p_paid_at date default current_date,
  p_method text default null,
  p_reference text default null,
  p_notes text default null,
  p_created_by uuid default null,
  p_mpesa_trans_id text default null
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
    invoice_id, tenant_id, amount, paid_at, method, reference, notes, created_by
  )
  values (
    p_invoice_id, p_tenant_id, p_amount, coalesce(p_paid_at, current_date), p_method, p_reference, p_notes, p_created_by
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
      mpesa_trans_id, created_by
    )
    values (
      p_tenant_id, 'income', p_amount, 'KES', p_amount,
      'paid', p_method, p_reference, coalesce(p_paid_at, current_date),
      'Invoice Payment',
      'Payment for Invoice ' || v_invoice.invoice_number,
      'Customer: ' || v_invoice.customer_name,
      v_invoice.vat_applicable, v_invoice.vat_rate, v_vat_for_payment, v_vat_for_payment, v_invoice.vat_pricing_mode,
      v_invoice.customer_person_id, p_invoice_id, v_payment_id,
      p_mpesa_trans_id, p_created_by
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
end;
$function$;

revoke all on function public.apply_ungani_invoice_payment(uuid, uuid, numeric, date, text, text, text, uuid, text) from public, anon, authenticated;
grant execute on function public.apply_ungani_invoice_payment(uuid, uuid, numeric, date, text, text, text, uuid, text) to service_role;

-- Thin wrapper - EXACT same signature/behavior as before (resolves its
-- own tenant from auth.uid(), same "No tenant workspace found" message),
-- now just delegating the body to the function above.
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
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  return public.apply_ungani_invoice_payment(
    v_tenant_id, p_invoice_id, p_amount, p_paid_at, p_method, p_reference, p_notes, auth.uid(), null
  );
end;
$function$;

revoke all on function public.record_ungani_invoice_payment(uuid, numeric, date, text, text, text) from public, anon;
grant execute on function public.record_ungani_invoice_payment(uuid, numeric, date, text, text, text) to authenticated;

-- The ONE unified ledger-apply function. Called by (1) apply_ungani_
-- mpesa_rent_payment below (C2B + CSV import + Payments-to-match
-- resolve all route through that), and (2) the new manual-entry wrapper
-- in Part E. Lease bucket first (oldest), then open invoices (extras
-- only - rule 1 makes a rent invoice on an active lease impossible) by
-- due_date ascending, then remainder -> credit_balance.
create or replace function public.apply_ungani_tenant_ledger_payment(
  p_tenant_id uuid,
  p_commitment_id uuid,
  p_amount numeric,
  p_source text,
  p_trans_id text default null,
  p_paid_at date default current_date,
  p_method text default null,
  p_reference text default null,
  p_created_by uuid default null,
  p_payer_phone text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_lease public.ungani_commitments%rowtype;
  v_existing_transaction_id uuid;
  v_remaining numeric;
  v_applied_to_lease numeric := 0;
  v_credit_added numeric := 0;
  v_lease_recorded_amount numeric := 0;
  v_receipt_seq int;
  v_receipt_number text;
  v_lease_transaction_id uuid;
  v_invoice record;
  v_invoice_owed numeric;
  v_pay_to_invoice numeric;
  v_total_invoice_applied numeric := 0;
  v_invoices_applied jsonb := '[]'::jsonb;
begin
  if p_amount is null or p_amount <= 0 then
    return jsonb_build_object('ok', false, 'message', 'Amount must be greater than zero.');
  end if;

  if p_trans_id is not null then
    select id into v_existing_transaction_id
    from public.transactions
    where tenant_id = p_tenant_id and mpesa_trans_id = p_trans_id
    limit 1;

    if v_existing_transaction_id is not null then
      return jsonb_build_object('ok', true, 'status', 'duplicate', 'transaction_id', v_existing_transaction_id);
    end if;
  end if;

  select * into v_lease
  from public.ungani_commitments
  where id = p_commitment_id and tenant_id = p_tenant_id and commitment_type = 'lease'
  for update;

  if v_lease.id is null then
    return jsonb_build_object('ok', false, 'message', 'Lease not found.');
  end if;

  v_remaining := p_amount;

  -- Bucket 1: the lease's own balance - always the oldest obligation.
  v_applied_to_lease := least(v_remaining, greatest(v_lease.balance_owed, 0));
  v_remaining := v_remaining - v_applied_to_lease;

  -- Bucket 2: this tenant's open extras invoices, oldest due_date first.
  if v_remaining > 0 then
    for v_invoice in
      select * from public.ungani_customer_invoices
      where tenant_id = p_tenant_id
        and customer_person_id = v_lease.person_id
        and status in ('sent', 'partially_paid')
        and deleted_at is null
      order by due_date asc nulls last, created_at asc
    loop
      exit when v_remaining <= 0;

      v_invoice_owed := greatest(v_invoice.total_amount - v_invoice.amount_paid, 0);
      v_pay_to_invoice := least(v_remaining, v_invoice_owed);

      if v_pay_to_invoice > 0 then
        perform public.apply_ungani_invoice_payment(
          p_tenant_id, v_invoice.id, v_pay_to_invoice, coalesce(p_paid_at, current_date),
          p_method, p_reference,
          'Auto-applied from ' || p_source || ' payment',
          p_created_by, p_trans_id
        );
        v_remaining := v_remaining - v_pay_to_invoice;
        v_total_invoice_applied := v_total_invoice_applied + v_pay_to_invoice;
        v_invoices_applied := v_invoices_applied || jsonb_build_object('invoice_id', v_invoice.id, 'applied', v_pay_to_invoice)::jsonb;
      end if;
    end loop;
  end if;

  -- Bucket 3: whatever's left is credit on the lease.
  v_credit_added := v_remaining;

  -- Cash received, recorded against the lease: everything NOT already
  -- receipted to an invoice above - matches the already-live behavior
  -- of recording the full amount as income even when part becomes
  -- credit_balance (see file header).
  v_lease_recorded_amount := p_amount - v_total_invoice_applied;

  if v_lease_recorded_amount > 0 then
    select count(*) + 1 into v_receipt_seq
    from public.transactions
    where tenant_id = p_tenant_id and receipt_number is not null;
    v_receipt_number := 'RCT-' || lpad(v_receipt_seq::text, 6, '0');

    insert into public.transactions (
      tenant_id, type, transaction_type, category, amount, currency, exchange_rate, amount_kes,
      transaction_date, payment_method, status, description,
      related_person_id, related_item_id, commitment_id,
      payer_phone, reference_no, mpesa_trans_id, receipt_number,
      created_by, created_at, updated_at
    ) values (
      p_tenant_id, 'income', 'income', 'Rental Income', v_lease_recorded_amount, 'KES', 1, v_lease_recorded_amount,
      coalesce(p_paid_at, current_date),
      coalesce(p_method, case when p_source = 'manual' then 'Manual' else 'M-Pesa' end),
      'completed',
      'Rent received' || case
        when p_source = 'manual' then ' (recorded manually)'
        when p_source = 'csv_import' then ' (imported from statement)'
        when p_source = 'manual_resolve' then ' (matched from Payments to match)'
        else ' via M-Pesa'
      end,
      v_lease.person_id, v_lease.linked_item_id, v_lease.id,
      p_payer_phone, p_reference, p_trans_id, v_receipt_number,
      p_created_by, now(), now()
    )
    returning id into v_lease_transaction_id;

    perform public.create_ungani_notification(
      p_tenant_id,
      'Rent payment received',
      'Ksh ' || to_char(p_amount, 'FM999,999,999') || ' received' ||
        case when v_total_invoice_applied > 0 then ' (Ksh ' || to_char(v_total_invoice_applied, 'FM999,999,999') || ' applied to other invoices)' else '' end ||
        case when v_credit_added > 0 then ' (Ksh ' || to_char(v_credit_added, 'FM999,999,999') || ' held as credit)' else '' end || '.',
      'payment_received',
      'transactions',
      v_lease_transaction_id,
      'my-money.html',
      'normal',
      jsonb_build_object('amount', p_amount, 'receipt_number', v_receipt_number),
      true,
      null
    );
  end if;

  update public.ungani_commitments
  set balance_owed = balance_owed - v_applied_to_lease,
      credit_balance = credit_balance + v_credit_added,
      updated_at = now()
  where id = p_commitment_id;

  return jsonb_build_object(
    'ok', true,
    'status', 'matched',
    'commitment_id', p_commitment_id,
    'transaction_id', v_lease_transaction_id,
    'receipt_number', v_receipt_number,
    'applied_to_lease', v_applied_to_lease,
    'applied_to_invoices', v_invoices_applied,
    'total_applied_to_invoices', v_total_invoice_applied,
    'overpayment_as_credit', v_credit_added
  );
end;
$function$;

revoke all on function public.apply_ungani_tenant_ledger_payment(uuid, uuid, numeric, text, text, date, text, text, uuid, text) from public, anon, authenticated;
grant execute on function public.apply_ungani_tenant_ledger_payment(uuid, uuid, numeric, text, text, date, text, text, uuid, text) to service_role;

-- apply_ungani_mpesa_rent_payment: SAME signature as the live version
-- (sql/mpesa-c2b-rent-matching-engine.sql:119-130), matching logic
-- UNCHANGED - only the "Apply" section (previously lines 274-331 of
-- that file) now delegates to the unified ledger function above instead
-- of updating balance_owed/inserting the transaction inline.
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
  v_commitment public.ungani_commitments%rowtype;
  v_person_id uuid;
begin
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

  if p_force_commitment_id is not null then
    v_person_id := p_force_person_id;
    select * into v_commitment from public.ungani_commitments where id = p_force_commitment_id and tenant_id = p_tenant_id;
  else
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

  return public.apply_ungani_tenant_ledger_payment(
    p_tenant_id, v_commitment.id, p_amount, p_source, p_trans_id,
    coalesce(p_trans_time::date, current_date), null, null, null, p_msisdn
  );
end;
$function$;

revoke all on function public.apply_ungani_mpesa_rent_payment(uuid, text, text, text, numeric, timestamptz, text, uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.apply_ungani_mpesa_rent_payment(uuid, text, text, text, numeric, timestamptz, text, uuid, uuid, uuid) to service_role;

-- ============================================================
-- PART D: Rule 7 - Accountant (staff with Money permission) can see and
-- resolve Payments to match, not only the owner. get_my_ungani_staff_
-- access() is this app's single owner/staff-permission resolver
-- (sql/fix-staff-access-status-coalesce-order.sql) - used here exactly
-- as everywhere else in the app.
-- ============================================================

create or replace function public.ungani_resolve_payments_to_match_access(p_require_edit boolean default false)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_access jsonb;
  v_can boolean;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is not null and public.is_my_ungani_tenant_owner(v_tenant_id) is true then
    return jsonb_build_object('allowed', true, 'tenant_id', v_tenant_id);
  end if;

  v_access := public.get_my_ungani_staff_access();

  if coalesce((v_access->>'can_access')::boolean, false) then
    v_can := case
      when p_require_edit then coalesce((v_access->'permissions'->'money'->>'edit')::boolean, false)
      else coalesce((v_access->'permissions'->'money'->>'view')::boolean, false)
    end;

    if v_can then
      return jsonb_build_object('allowed', true, 'tenant_id', (v_access->>'tenant_id')::uuid);
    end if;
  end if;

  return jsonb_build_object('allowed', false, 'tenant_id', null);
end;
$function$;

revoke all on function public.ungani_resolve_payments_to_match_access(boolean) from public, anon, authenticated;
grant execute on function public.ungani_resolve_payments_to_match_access(boolean) to authenticated;

create or replace function public.owner_list_ungani_payments_to_match()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_access jsonb;
  v_tenant_id uuid;
begin
  v_access := public.ungani_resolve_payments_to_match_access(false);
  if not coalesce((v_access->>'allowed')::boolean, false) then
    return jsonb_build_object('ok', false, 'message', 'You do not have permission to view this.');
  end if;
  v_tenant_id := (v_access->>'tenant_id')::uuid;

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

revoke all on function public.owner_list_ungani_payments_to_match() from public, anon, authenticated;
grant execute on function public.owner_list_ungani_payments_to_match() to authenticated;

create or replace function public.owner_get_ungani_payments_to_match_count()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_access jsonb;
begin
  v_access := public.ungani_resolve_payments_to_match_access(false);
  if not coalesce((v_access->>'allowed')::boolean, false) then
    return 0;
  end if;

  return (
    select count(*)::int
    from public.ungani_payments_to_match
    where tenant_id = (v_access->>'tenant_id')::uuid
      and status = 'unmatched'
  );
end;
$function$;

revoke all on function public.owner_get_ungani_payments_to_match_count() from public, anon, authenticated;
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
  v_access jsonb;
  v_tenant_id uuid;
  v_payment record;
  v_apply_result jsonb;
begin
  v_access := public.ungani_resolve_payments_to_match_access(true);
  if not coalesce((v_access->>'allowed')::boolean, false) then
    return jsonb_build_object('ok', false, 'message', 'You do not have permission to resolve payments.');
  end if;
  v_tenant_id := (v_access->>'tenant_id')::uuid;

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

revoke all on function public.owner_resolve_ungani_payment_to_match(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.owner_resolve_ungani_payment_to_match(uuid, uuid, uuid) to authenticated;

-- Unchanged from the live version (owner-only, CSV import is a bulk/
-- destructive-adjacent action not extended to staff by the user's ask) -
-- re-applied here only for the revoke sweep.
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

revoke all on function public.owner_bulk_import_ungani_mpesa_statement(jsonb) from public, anon, authenticated;
grant execute on function public.owner_bulk_import_ungani_mpesa_statement(jsonb) to authenticated;

-- ============================================================
-- PART E: manual Money entry with a Related Lease (my-money.html picker
-- is still pending frontend work - this ships the RPC it will call).
-- ============================================================

create or replace function public.owner_record_manual_ungani_rent_payment(
  p_commitment_id uuid,
  p_amount numeric,
  p_paid_at date default current_date,
  p_method text default null,
  p_reference text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if not exists (select 1 from public.ungani_commitments where id = p_commitment_id and tenant_id = v_tenant_id and commitment_type = 'lease') then
    return jsonb_build_object('ok', false, 'message', 'Lease not found.');
  end if;

  return public.apply_ungani_tenant_ledger_payment(
    v_tenant_id, p_commitment_id, p_amount, 'manual', null, p_paid_at, p_method, p_reference, auth.uid()
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.owner_record_manual_ungani_rent_payment(uuid, numeric, date, text, text) from public, anon, authenticated;
grant execute on function public.owner_record_manual_ungani_rent_payment(uuid, numeric, date, text, text) to authenticated;

-- ============================================================
-- PART F: Rule 5 - one-time opening balance for existing leases.
-- ============================================================

create or replace function public.owner_set_ungani_lease_opening_balance(
  p_commitment_id uuid,
  p_opening_balance numeric
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_lease public.ungani_commitments%rowtype;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null or public.is_my_ungani_tenant_owner(v_tenant_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'Only the business owner can set an opening balance.');
  end if;

  if p_opening_balance is null or p_opening_balance < 0 then
    return jsonb_build_object('ok', false, 'message', 'Opening balance cannot be negative.');
  end if;

  select * into v_lease
  from public.ungani_commitments
  where id = p_commitment_id and tenant_id = v_tenant_id and commitment_type = 'lease'
  for update;

  if v_lease.id is null then
    return jsonb_build_object('ok', false, 'message', 'Lease not found.');
  end if;

  if v_lease.opening_balance_set_at is not null then
    return jsonb_build_object('ok', false, 'message', 'An opening balance has already been set for this lease.');
  end if;

  update public.ungani_commitments
  set balance_owed = balance_owed + p_opening_balance,
      opening_balance_amount = p_opening_balance,
      opening_balance_set_at = now(),
      updated_at = now()
  where id = p_commitment_id;

  return jsonb_build_object('ok', true, 'opening_balance', p_opening_balance);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.owner_set_ungani_lease_opening_balance(uuid, numeric) from public, anon, authenticated;
grant execute on function public.owner_set_ungani_lease_opening_balance(uuid, numeric) to authenticated;

-- ============================================================
-- PART G: Rule 4 - accrual catch-up. Replaces the single "only fires if
-- today is the anniversary day" check with a per-lease loop that charges
-- every missed period up to today, still exactly once per lease per
-- calendar month (last_accrued_period is the same dedup key as before).
-- Safety cap of 36 periods per lease per run so a corrupted/ancient
-- start_date can never runaway-loop.
-- ============================================================

create or replace function public.service_accrue_ungani_monthly_rent()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_lease record;
  v_anchor_day int;
  v_next_period_start date;
  v_next_charge_date date;
  v_period_label text;
  v_balance_owed numeric;
  v_credit_balance numeric;
  v_last_period text;
  v_periods_charged int;
  v_total_charged int := 0;
  v_leases_touched int := 0;
  v_leases_scanned int := 0;
  v_safety int;
  v_today date := current_date;
begin
  for v_lease in
    select *
    from public.ungani_commitments
    where commitment_type = 'lease'
      and status = 'active'
      and deleted_at is null
      and coalesce(amount, 0) > 0
      and start_date <= v_today
    for update
  loop
    v_leases_scanned := v_leases_scanned + 1;
    v_anchor_day := greatest(1, extract(day from v_lease.start_date)::int);
    v_balance_owed := v_lease.balance_owed;
    v_credit_balance := v_lease.credit_balance;
    v_last_period := v_lease.last_accrued_period;
    v_periods_charged := 0;

    if v_last_period is null then
      v_next_period_start := date_trunc('month', v_lease.start_date)::date;
    else
      v_next_period_start := (to_date(v_last_period || '-01', 'YYYY-MM-DD') + interval '1 month')::date;
    end if;

    v_safety := 0;
    loop
      v_safety := v_safety + 1;
      exit when v_safety > 36;

      v_next_charge_date := least(
        v_next_period_start + (v_anchor_day - 1),
        (date_trunc('month', v_next_period_start) + interval '1 month - 1 day')::date
      );

      exit when v_next_charge_date > v_today;

      v_period_label := to_char(v_next_period_start, 'YYYY-MM');

      if v_credit_balance >= v_lease.amount then
        v_credit_balance := v_credit_balance - v_lease.amount;
      else
        v_balance_owed := v_balance_owed + (v_lease.amount - v_credit_balance);
        v_credit_balance := 0;
      end if;

      v_last_period := v_period_label;
      v_periods_charged := v_periods_charged + 1;
      v_next_period_start := (v_next_period_start + interval '1 month')::date;
    end loop;

    if v_periods_charged > 0 then
      update public.ungani_commitments
      set balance_owed = v_balance_owed,
          credit_balance = v_credit_balance,
          last_accrued_period = v_last_period,
          updated_at = now()
      where id = v_lease.id;

      v_leases_touched := v_leases_touched + 1;
      v_total_charged := v_total_charged + v_periods_charged;
    end if;
  end loop;

  return jsonb_build_object(
    'ok', true,
    'leases_scanned', v_leases_scanned,
    'leases_charged', v_leases_touched,
    'total_periods_charged', v_total_charged,
    'run_at', now()
  );
end;
$function$;

revoke all on function public.service_accrue_ungani_monthly_rent() from public, anon, authenticated;
grant execute on function public.service_accrue_ungani_monthly_rent() to service_role;

-- ============================================================
-- PART H: Rule 6 - deposit deduction for unpaid rent reduces
-- balance_owed too. SAME signature as the live version (sql/deposits-
-- feature.sql:197-301, read in full above) - every line unchanged
-- except the new block right after the deduction transaction insert.
-- ============================================================

create or replace function public.owner_settle_ungani_commitment_deposit(
  p_commitment_id uuid,
  p_refund_amount numeric default 0,
  p_deduction_amount numeric default 0,
  p_deduction_type text default null::text,
  p_refund_method text default null::text,
  p_note text default null::text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_lease record;
  v_refund_amount numeric := coalesce(p_refund_amount, 0);
  v_deduction_amount numeric := coalesce(p_deduction_amount, 0);
  v_clean_deduction_type text := lower(trim(coalesce(p_deduction_type, '')));
  v_unit_name text;
  v_tenant_name text;
  v_deduction_transaction_id uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if v_refund_amount < 0 or v_deduction_amount < 0 then
    return jsonb_build_object('ok', false, 'message', 'Amounts cannot be negative.');
  end if;

  if v_deduction_amount > 0 and v_clean_deduction_type not in ('damages', 'unpaid_rent') then
    return jsonb_build_object('ok', false, 'message', 'A deduction reason (damages or unpaid rent) is required.');
  end if;

  select * into v_lease
  from public.ungani_commitments
  where id = p_commitment_id and tenant_id = v_tenant_id
  for update;

  if v_lease.id is null then
    return jsonb_build_object('ok', false, 'message', 'Lease not found.');
  end if;

  if v_lease.commitment_type <> 'lease' then
    return jsonb_build_object('ok', false, 'message', 'Deposits apply to leases only.');
  end if;

  if v_lease.deposit_amount_kes is null or v_lease.deposit_amount_kes <= 0 then
    return jsonb_build_object('ok', false, 'message', 'This lease has no deposit on file.');
  end if;

  if v_lease.deposit_status = 'settled' then
    return jsonb_build_object('ok', false, 'message', 'This deposit has already been settled.');
  end if;

  if (v_refund_amount + v_deduction_amount) > v_lease.deposit_amount_kes then
    return jsonb_build_object('ok', false, 'message', 'Refund + deduction cannot exceed the deposit held (Ksh ' || v_lease.deposit_amount_kes || ').');
  end if;

  select full_name into v_tenant_name from public.client_people where id = v_lease.person_id;
  select item_name into v_unit_name from public.business_items where id = v_lease.linked_item_id;

  if v_deduction_amount > 0 then
    insert into public.transactions (
      tenant_id, transaction_type, amount, amount_kes, currency, category, category_name,
      description, transaction_date, related_person_id, related_item_id, created_by
    )
    values (
      v_tenant_id, 'income', v_deduction_amount, v_deduction_amount, 'KES',
      case when v_clean_deduction_type = 'unpaid_rent' then 'Rental Income' else 'Deposit Deduction' end,
      case when v_clean_deduction_type = 'unpaid_rent' then 'Rental Income' else 'Deposit Deduction (Damages)' end,
      'Deposit deduction - ' || coalesce(v_tenant_name, 'Tenant') ||
        coalesce(' (' || v_unit_name || ')', '') ||
        case when v_clean_deduction_type = 'unpaid_rent' then ' - applied to unpaid rent' else ' - damages' end,
      current_date, v_lease.person_id, v_lease.linked_item_id, auth.uid()
    )
    returning id into v_deduction_transaction_id;

    -- Rule 6: the deduction is real rent income on the books (above) AND
    -- it must reduce the lease's own ledger the same way any other rent
    -- payment would, so Outstanding Rent/statement/Person 360 stay in
    -- sync with this settlement.
    if v_clean_deduction_type = 'unpaid_rent' then
      update public.ungani_commitments
      set balance_owed = greatest(v_lease.balance_owed - v_deduction_amount, 0),
          credit_balance = credit_balance + greatest(v_deduction_amount - v_lease.balance_owed, 0)
      where id = p_commitment_id;
    end if;
  end if;

  update public.ungani_commitments
  set deposit_status = 'settled',
      deposit_refunded_kes = v_refund_amount,
      deposit_refund_method = nullif(trim(coalesce(p_refund_method, '')), ''),
      deposit_deducted_kes = v_deduction_amount,
      deposit_deduction_type = nullif(v_clean_deduction_type, ''),
      deposit_settlement_note = nullif(trim(coalesce(p_note, '')), ''),
      deposit_settled_at = now(),
      deposit_settled_by = auth.uid(),
      updated_at = now()
  where id = p_commitment_id;

  return jsonb_build_object(
    'ok', true,
    'deduction_transaction_id', v_deduction_transaction_id
  );
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.owner_settle_ungani_commitment_deposit(uuid, numeric, numeric, text, text, text) from public, anon, authenticated;
grant execute on function public.owner_settle_ungani_commitment_deposit(uuid, numeric, numeric, text, text, text) to authenticated;

-- ============================================================
-- PART I: Rule 3 - one source of truth, readable from any page.
-- ============================================================

create or replace function public.get_my_ungani_tenant_total_owed(p_person_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
stable
as $function$
declare
  v_tenant_id uuid;
  v_lease_owed numeric := 0;
  v_invoice_owed numeric := 0;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select coalesce(sum(greatest(balance_owed, 0)), 0) into v_lease_owed
  from public.ungani_commitments
  where tenant_id = v_tenant_id
    and person_id = p_person_id
    and commitment_type = 'lease'
    and status = 'active'
    and deleted_at is null;

  select coalesce(sum(greatest(total_amount - amount_paid, 0)), 0) into v_invoice_owed
  from public.ungani_customer_invoices
  where tenant_id = v_tenant_id
    and customer_person_id = p_person_id
    and status in ('sent', 'partially_paid')
    and deleted_at is null;

  return jsonb_build_object(
    'ok', true,
    'lease_owed', v_lease_owed,
    'invoice_owed', v_invoice_owed,
    'total_owed', v_lease_owed + v_invoice_owed
  );
end;
$function$;

revoke all on function public.get_my_ungani_tenant_total_owed(uuid) from public, anon, authenticated;
grant execute on function public.get_my_ungani_tenant_total_owed(uuid) to authenticated;

create or replace function public.get_my_ungani_total_outstanding_rent()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
stable
as $function$
declare
  v_tenant_id uuid;
  v_lease_owed numeric := 0;
  v_legacy_rent_invoice_owed numeric := 0;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select coalesce(sum(greatest(balance_owed, 0)), 0) into v_lease_owed
  from public.ungani_commitments
  where tenant_id = v_tenant_id
    and commitment_type = 'lease'
    and status = 'active'
    and deleted_at is null;

  -- invoice_type = 'rent' should be structurally empty going forward
  -- (the trigger in Part B blocks it whenever an active lease exists) -
  -- included only so any pre-existing rent-marked invoice isn't silently
  -- dropped from the dashboard total.
  select coalesce(sum(greatest(total_amount - amount_paid, 0)), 0) into v_legacy_rent_invoice_owed
  from public.ungani_customer_invoices
  where tenant_id = v_tenant_id
    and invoice_type = 'rent'
    and status in ('sent', 'partially_paid')
    and deleted_at is null;

  return jsonb_build_object(
    'ok', true,
    'lease_owed', v_lease_owed,
    'legacy_rent_invoice_owed', v_legacy_rent_invoice_owed,
    'total_outstanding_rent', v_lease_owed + v_legacy_rent_invoice_owed
  );
end;
$function$;

revoke all on function public.get_my_ungani_total_outstanding_rent() from public, anon, authenticated;
grant execute on function public.get_my_ungani_total_outstanding_rent() to authenticated;

-- ============================================================
-- PART J: Rule 5 - Demo Properties Ltd opening balances. Looked up by
-- name in public.tenants (NOT hardcoded, NOT a different tenant) at
-- RUN TIME, and only applied if that tenant is also is_test = true.
-- Touches no other tenant in this file - this DO block is the only
-- tenant-scoped DML anywhere in this migration; everything else is
-- schema (CREATE FUNCTION/TRIGGER, ALTER TABLE ADD COLUMN), which
-- applies identically regardless of tenant. Formulaic default (one
-- month's rent per active lease) since I have no way to see real
-- opening figures - idempotent (opening_balance_set_at is null guard),
-- so re-running this file a second time is a no-op for leases already
-- seeded. If the tenant isn't found, or is found but is_test is not
-- true, this does nothing and says so via RAISE NOTICE - no fallback
-- to any other tenant.
-- ============================================================

do $$
declare
  v_tenant_id uuid;
  v_is_test boolean;
  v_leases_updated int;
begin
  select id, is_test
  into v_tenant_id, v_is_test
  from public.tenants
  where lower(trim(business_name)) = lower(trim('Demo Properties Ltd'))
  order by created_at desc
  limit 1;

  if v_tenant_id is null then
    raise notice 'Opening-balance seed SKIPPED: no tenant named "Demo Properties Ltd" found in public.tenants.';
  elsif coalesce(v_is_test, false) is not true then
    raise notice 'Opening-balance seed SKIPPED: tenant "Demo Properties Ltd" (id %) exists but is_test is not true - refusing to seed a non-test tenant.', v_tenant_id;
  else
    update public.ungani_commitments
    set balance_owed = balance_owed + amount,
        opening_balance_amount = amount,
        opening_balance_set_at = now(),
        updated_at = now()
    where commitment_type = 'lease'
      and status = 'active'
      and deleted_at is null
      and opening_balance_set_at is null
      and tenant_id = v_tenant_id;

    get diagnostics v_leases_updated = row_count;
    raise notice 'Opening-balance seed APPLIED to "Demo Properties Ltd" (id %): % lease(s) updated.', v_tenant_id, v_leases_updated;
  end if;
end;
$$;

-- ============================================================
-- COMBINED VERIFICATION - run this and paste back the full output.
-- ============================================================

-- 1) Overload count per function - must be exactly 1 each.
select proname, count(*) as overload_count
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in (
    'ungani_block_duplicate_rent_invoice',
    'owner_set_ungani_invoice_type',
    'apply_ungani_invoice_payment',
    'record_ungani_invoice_payment',
    'apply_ungani_tenant_ledger_payment',
    'apply_ungani_mpesa_rent_payment',
    'ungani_resolve_payments_to_match_access',
    'owner_list_ungani_payments_to_match',
    'owner_get_ungani_payments_to_match_count',
    'owner_resolve_ungani_payment_to_match',
    'owner_bulk_import_ungani_mpesa_statement',
    'owner_record_manual_ungani_rent_payment',
    'owner_set_ungani_lease_opening_balance',
    'service_accrue_ungani_monthly_rent',
    'owner_settle_ungani_commitment_deposit',
    'get_my_ungani_tenant_total_owed',
    'get_my_ungani_total_outstanding_rent'
  )
group by proname
order by proname;

-- 2) Exact EXECUTE grants per function/role. Expected:
--    apply_ungani_invoice_payment, apply_ungani_tenant_ledger_payment,
--    apply_ungani_mpesa_rent_payment, service_accrue_ungani_monthly_rent
--      -> only service_role.
--    ungani_block_duplicate_rent_invoice -> NO role at all (trigger-only).
--    every other function listed -> only authenticated.
--    public/anon should appear for NONE of them.
select
  p.proname,
  grantee.rolname as granted_to,
  acl.privilege_type
from pg_proc p
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
join pg_roles grantee on grantee.oid = acl.grantee
where p.pronamespace = 'public'::regnamespace
  and p.proname in (
    'ungani_block_duplicate_rent_invoice',
    'owner_set_ungani_invoice_type',
    'apply_ungani_invoice_payment',
    'record_ungani_invoice_payment',
    'apply_ungani_tenant_ledger_payment',
    'apply_ungani_mpesa_rent_payment',
    'ungani_resolve_payments_to_match_access',
    'owner_list_ungani_payments_to_match',
    'owner_get_ungani_payments_to_match_count',
    'owner_resolve_ungani_payment_to_match',
    'owner_bulk_import_ungani_mpesa_statement',
    'owner_record_manual_ungani_rent_payment',
    'owner_set_ungani_lease_opening_balance',
    'service_accrue_ungani_monthly_rent',
    'owner_settle_ungani_commitment_deposit',
    'get_my_ungani_tenant_total_owed',
    'get_my_ungani_total_outstanding_rent'
  )
  and acl.privilege_type = 'EXECUTE'
order by p.proname, grantee.rolname;

-- 3) Trigger confirmation.
select tgname, tgrelid::regclass, tgenabled
from pg_trigger
where tgname = 'ungani_block_duplicate_rent_invoice_trg';

-- 4) New columns present.
select column_name, data_type, column_default
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'ungani_customer_invoices' and column_name = 'invoice_type')
    or (table_name = 'ungani_commitments' and column_name in ('opening_balance_amount', 'opening_balance_set_at'))
  );

-- 5) Demo Properties Ltd opening-balance seed result - looked up by name,
-- same as the DO block above, not a hardcoded id.
select t.business_name, t.is_test, c.id as lease_id, cp.full_name as tenant_name,
       c.amount as monthly_rent, c.balance_owed, c.opening_balance_amount, c.opening_balance_set_at
from public.ungani_commitments c
join public.client_people cp on cp.id = c.person_id
join public.tenants t on t.id = c.tenant_id
where lower(trim(t.business_name)) = lower(trim('Demo Properties Ltd'))
  and c.commitment_type = 'lease'
order by c.created_at;

commit;
