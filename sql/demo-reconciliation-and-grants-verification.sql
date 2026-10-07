-- Three things, in order:
-- PART 1: combined grants/overload/trigger/column verification as ONE
--         query (read-only, safe to run any time, run it first).
-- PART 2: last_accrued_period check for Demo Properties Ltd's 8 leases
--         (read-only - answers "will tomorrow's 06:00 cron double-
--         charge?" with data, before PART 3 fixes it).
-- PART 3: the actual reconciliation (own begin/commit - all or nothing).
--         Looked up by name + is_test = true, same guarded pattern as
--         the opening-balance seed - does nothing to any other tenant.
-- PART 4: final per-lease verification of the resulting mix.
--
-- PART 3 also directly answers/fixes PART 2's question: every lease
-- touched gets last_accrued_period set to the current month as part of
-- the reconciliation itself (the reconciled balance already represents
-- "everything through today" - a separate narrow fix would just be
-- overwritten by this same statement seconds later, so it's folded in
-- here instead of written twice).

-- ============================================================
-- PART 1: combined verification (overload count + grants + trigger +
-- new columns) in one result set, one query to run.
-- ============================================================

select 'overload_count' as check_type, proname as object_name, count(*)::text as detail
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in (
    'ungani_block_duplicate_rent_invoice', 'owner_set_ungani_invoice_type',
    'apply_ungani_invoice_payment', 'record_ungani_invoice_payment',
    'apply_ungani_tenant_ledger_payment', 'apply_ungani_mpesa_rent_payment',
    'ungani_resolve_payments_to_match_access', 'owner_list_ungani_payments_to_match',
    'owner_get_ungani_payments_to_match_count', 'owner_resolve_ungani_payment_to_match',
    'owner_bulk_import_ungani_mpesa_statement', 'owner_record_manual_ungani_rent_payment',
    'owner_set_ungani_lease_opening_balance', 'service_accrue_ungani_monthly_rent',
    'owner_settle_ungani_commitment_deposit', 'get_my_ungani_tenant_total_owed',
    'get_my_ungani_total_outstanding_rent'
  )
group by proname

union all

select 'grant' as check_type, p.proname as object_name, grantee.rolname || ':' || acl.privilege_type as detail
from pg_proc p
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
join pg_roles grantee on grantee.oid = acl.grantee
where p.pronamespace = 'public'::regnamespace
  and p.proname in (
    'ungani_block_duplicate_rent_invoice', 'owner_set_ungani_invoice_type',
    'apply_ungani_invoice_payment', 'record_ungani_invoice_payment',
    'apply_ungani_tenant_ledger_payment', 'apply_ungani_mpesa_rent_payment',
    'ungani_resolve_payments_to_match_access', 'owner_list_ungani_payments_to_match',
    'owner_get_ungani_payments_to_match_count', 'owner_resolve_ungani_payment_to_match',
    'owner_bulk_import_ungani_mpesa_statement', 'owner_record_manual_ungani_rent_payment',
    'owner_set_ungani_lease_opening_balance', 'service_accrue_ungani_monthly_rent',
    'owner_settle_ungani_commitment_deposit', 'get_my_ungani_tenant_total_owed',
    'get_my_ungani_total_outstanding_rent'
  )
  and acl.privilege_type = 'EXECUTE'

union all

select 'trigger' as check_type, tgname as object_name,
       tgrelid::regclass::text || ' enabled=' || tgenabled as detail
from pg_trigger
where tgname = 'ungani_block_duplicate_rent_invoice_trg'

union all

select 'column' as check_type, table_name || '.' || column_name as object_name, data_type as detail
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'ungani_customer_invoices' and column_name = 'invoice_type')
    or (table_name = 'ungani_commitments' and column_name in ('opening_balance_amount', 'opening_balance_set_at'))
  )

order by check_type, object_name;

-- ============================================================
-- PART 2: last_accrued_period check for Demo Properties Ltd's leases.
-- If last_accrued_period is null or earlier than the current month on
-- any of these, tomorrow's 06:00 cron WILL add another month on top of
-- the opening-balance seed - this is the exact risk you flagged.
-- ============================================================

select t.business_name, c.id as lease_id, cp.full_name as tenant_name,
       c.amount as monthly_rent, c.balance_owed, c.last_accrued_period,
       to_char(current_date, 'YYYY-MM') as current_period,
       (coalesce(c.last_accrued_period, '') < to_char(current_date, 'YYYY-MM')) as will_double_charge_tomorrow
from public.ungani_commitments c
join public.client_people cp on cp.id = c.person_id
join public.tenants t on t.id = c.tenant_id
where lower(trim(t.business_name)) = lower(trim('Demo Properties Ltd'))
  and c.commitment_type = 'lease'
order by c.created_at;

-- ============================================================
-- PART 3: reconciliation. Resets Demo Properties Ltd's 8 leases to a
-- realistic mix (3 fully paid, 2 partly paid, 2 owing one month, 1
-- owing two months + an open water invoice), backing every paid/owed
-- number with an actual transaction so balance_owed is never a naked
-- number with no paper trail. Idempotent: re-running computes the same
-- shortfall against transactions already inserted by a prior run, so it
-- settles to the same end state rather than piling up duplicates.
-- ============================================================

begin;

do $$
declare
  v_tenant_id uuid;
  v_is_test boolean;
  v_lease_count int;
  v_rec record;
  v_rn int;
  v_target_owed numeric;
  v_required_paid numeric;
  v_existing_paid numeric;
  v_shortfall numeric;
  v_receipt_seq int;
  v_receipt_number text;
  v_payment_method text;
  v_bucket text;
  v_invoice_id uuid;
  v_person_name text;
begin
  select id, is_test
  into v_tenant_id, v_is_test
  from public.tenants
  where lower(trim(business_name)) = lower(trim('Demo Properties Ltd'))
  order by created_at desc
  limit 1;

  if v_tenant_id is null then
    raise notice 'Reconciliation SKIPPED: no tenant named "Demo Properties Ltd" found in public.tenants.';
    return;
  end if;

  if coalesce(v_is_test, false) is not true then
    raise notice 'Reconciliation SKIPPED: tenant "Demo Properties Ltd" (id %) exists but is_test is not true.', v_tenant_id;
    return;
  end if;

  select count(*) into v_lease_count
  from public.ungani_commitments
  where tenant_id = v_tenant_id and commitment_type = 'lease' and status = 'active' and deleted_at is null;

  if v_lease_count <> 8 then
    raise notice 'Reconciliation SKIPPED: expected exactly 8 active leases on "Demo Properties Ltd", found %. Refusing to guess a mix against a different count.', v_lease_count;
    return;
  end if;

  v_rn := 0;
  for v_rec in
    select c.id, c.amount, c.person_id, c.linked_item_id
    from public.ungani_commitments c
    where c.tenant_id = v_tenant_id
      and c.commitment_type = 'lease'
      and c.status = 'active'
      and c.deleted_at is null
    order by c.created_at asc
  loop
    v_rn := v_rn + 1;

    if v_rec.amount is null or v_rec.amount <= 0 then
      raise notice 'Lease % skipped: no monthly rent amount set.', v_rec.id;
      continue;
    end if;

    select full_name into v_person_name from public.client_people where id = v_rec.person_id;

    -- Bucket by position: 1-3 fully paid, 4-5 partly paid (60% paid),
    -- 6-7 owing one month untouched, 8 owing two months + water invoice.
    if v_rn <= 3 then
      v_bucket := 'fully_paid';
      v_target_owed := 0;
      v_required_paid := v_rec.amount;
    elsif v_rn <= 5 then
      v_bucket := 'partly_paid';
      v_target_owed := round(v_rec.amount * 0.4, 2);
      v_required_paid := round(v_rec.amount * 0.6, 2);
    elsif v_rn <= 7 then
      v_bucket := 'owing_one_month';
      v_target_owed := v_rec.amount;
      v_required_paid := null; -- no top-up: leave existing history as-is
    else
      v_bucket := 'owing_two_months_plus_water';
      v_target_owed := v_rec.amount * 2;
      v_required_paid := null;
    end if;

    -- Top up the real transaction history for fully/partly paid buckets
    -- so the balance is never unbacked by an actual payment record.
    if v_required_paid is not null then
      select coalesce(sum(amount), 0) into v_existing_paid
      from public.transactions
      where commitment_id = v_rec.id and category = 'Rental Income';

      v_shortfall := round(v_required_paid - v_existing_paid, 2);

      if v_shortfall > 0 then
        select count(*) + 1 into v_receipt_seq
        from public.transactions
        where tenant_id = v_tenant_id and receipt_number is not null;
        v_receipt_number := 'RCT-' || lpad(v_receipt_seq::text, 6, '0');

        v_payment_method := (array['M-Pesa', 'Bank Transfer', 'Cash', 'M-Pesa', 'Bank Transfer'])[((v_rn - 1) % 5) + 1];

        insert into public.transactions (
          tenant_id, type, transaction_type, category, amount, currency, exchange_rate, amount_kes,
          transaction_date, payment_method, status, description,
          related_person_id, related_item_id, commitment_id,
          receipt_number, created_at, updated_at
        ) values (
          v_tenant_id, 'income', 'income', 'Rental Income', v_shortfall, 'KES', 1, v_shortfall,
          current_date, v_payment_method, 'completed',
          'Demo reconciliation: rent payment for ' || coalesce(v_person_name, 'tenant'),
          v_rec.person_id, v_rec.linked_item_id, v_rec.id,
          v_receipt_number, now(), now()
        );
      end if;
    end if;

    update public.ungani_commitments
    set balance_owed = v_target_owed,
        credit_balance = 0,
        last_accrued_period = to_char(current_date, 'YYYY-MM'),
        updated_at = now()
    where id = v_rec.id;

    -- The one lease with an open extras invoice (water) - 'general'
    -- type so it isn't blocked by the rent-exclusivity trigger. Idempotent
    -- via the notes marker below.
    if v_bucket = 'owing_two_months_plus_water' then
      if not exists (
        select 1 from public.ungani_customer_invoices
        where tenant_id = v_tenant_id
          and customer_person_id = v_rec.person_id
          and notes = 'Demo reconciliation: water bill'
          and deleted_at is null
      ) then
        insert into public.ungani_customer_invoices (
          tenant_id, invoice_number, invoice_type, customer_person_id, customer_name,
          issue_date, due_date, payment_terms, vat_applicable, vat_rate, vat_pricing_mode,
          discount_amount, subtotal, vat_amount, total_amount, amount_paid, currency, status, notes
        ) values (
          v_tenant_id,
          'WTR-' || to_char(current_date, 'YYYYMM') || '-' || substr(replace(v_rec.person_id::text, '-', ''), 1, 6),
          'general', v_rec.person_id, coalesce(v_person_name, 'Tenant'),
          current_date, current_date + interval '14 days', 'Net 14', false, null, 'inclusive',
          0, 1500, 0, 1500, 0, 'KES', 'sent', 'Demo reconciliation: water bill'
        )
        returning id into v_invoice_id;

        insert into public.ungani_customer_invoice_items (
          invoice_id, tenant_id, description, quantity, unit_price, line_subtotal, sort_order
        ) values (
          v_invoice_id, v_tenant_id, 'Water bill', 1, 1500, 1500, 1
        );
      end if;
    end if;

    raise notice 'Lease % (rn %, %): balance_owed -> %, bucket %', v_rec.id, v_rn, coalesce(v_person_name, '?'), v_target_owed, v_bucket;
  end loop;

  raise notice 'Reconciliation APPLIED to "Demo Properties Ltd" (id %): % leases processed.', v_tenant_id, v_rn;
end;
$$;

commit;

-- ============================================================
-- PART 4: final per-lease verification of the resulting mix.
-- ============================================================

select
  cp.full_name as tenant_name,
  c.amount as monthly_rent,
  c.balance_owed,
  c.credit_balance,
  c.last_accrued_period,
  (select coalesce(sum(amount), 0) from public.transactions where commitment_id = c.id and category = 'Rental Income') as total_rent_paid_on_record,
  (select coalesce(sum(total_amount - amount_paid), 0) from public.ungani_customer_invoices where customer_person_id = c.person_id and status in ('sent', 'partially_paid') and deleted_at is null) as open_invoice_balance,
  c.balance_owed + (select coalesce(sum(total_amount - amount_paid), 0) from public.ungani_customer_invoices where customer_person_id = c.person_id and status in ('sent', 'partially_paid') and deleted_at is null) as combined_total_owed
from public.ungani_commitments c
join public.client_people cp on cp.id = c.person_id
join public.tenants t on t.id = c.tenant_id
where lower(trim(t.business_name)) = lower(trim('Demo Properties Ltd'))
  and c.commitment_type = 'lease'
order by c.created_at;
