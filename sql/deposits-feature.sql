-- DEPOSITS (Real Estate lease security deposits) — CORRECTED VERSION
--
-- Rules (from Chris, verbatim):
--   1. A deposit is held money, NOT income. Collecting it must never create
--      a Money/transactions row.
--   2. At move-out: refund in full, or deduct for damages/unpaid rent (the
--      deduction becomes income or clears rent owed), the rest refunded.
--      REFUND IS NOT AN EXPENSE — it's giving back money that was never
--      income in the first place. The refund is recorded on the deposit
--      itself (amount/date/method/who), never as a transactions row, so
--      it never touches Money totals or Profit per property.
--   3. Shows on tenant statement, Person 360, and the lease.
--
-- FIXES TWO BUGS from the first version of this migration (never run live,
-- caught before it touched the real DB):
--   BUG 1 — CREATE OR REPLACE with a different parameter list does NOT
--   replace a Postgres function, it creates a SECOND overload (Postgres
--   function identity includes the parameter signature). The first
--   version added p_deposit_amount as a 14th param without dropping the
--   old 13-param owner_upsert_ungani_commitment — every lease/commitment
--   save in the whole app would have started failing with "could not
--   choose the best candidate function" the moment two overloads existed.
--   Fixed here by explicitly DROPping the exact old 13-param signature
--   before creating the 14-param one, so exactly one overload exists.
--   BUG 2 — the first version posted the refund as a real expense
--   transaction. That's wrong: holding a deposit was never income, so
--   giving it back is not a real cash expense for the business in the
--   P&L sense Chris means here — it's a liability settling, not new
--   spend. Fixed by removing that transaction insert entirely; the
--   refund amount/method only ever lives on the ungani_commitments row.
--
-- STEP 2's function body is otherwise byte-identical to the live body
-- from sql/fix-commitments-generic-type-allow-list.sql (confirmed live
-- 2026-10-06) except the new p_deposit_amount param and the deposit
-- read/write block.

-- ============================================================
-- STEP 1: new columns on ungani_commitments
-- ============================================================
alter table public.ungani_commitments
  add column if not exists deposit_amount_kes numeric,
  add column if not exists deposit_status text,
  -- null (no deposit on this lease) | 'held' | 'settled'
  add column if not exists deposit_refunded_kes numeric,
  add column if not exists deposit_refund_method text,
  add column if not exists deposit_deducted_kes numeric,
  add column if not exists deposit_deduction_type text,
  -- 'damages' | 'unpaid_rent' — only meaningful once settled
  add column if not exists deposit_settlement_note text,
  add column if not exists deposit_settled_at timestamptz,
  add column if not exists deposit_settled_by uuid;

alter table public.ungani_commitments
  drop constraint if exists ungani_commitments_deposit_status_check,
  add constraint ungani_commitments_deposit_status_check
    check (deposit_status is null or deposit_status in ('held', 'settled'));

-- ============================================================
-- STEP 2: drop the old 13-param overload, then create the 14-param
-- replacement. Order matters here only in the sense that both must run
-- in the same migration — doing the drop first makes the intent
-- unambiguous on re-read.
-- ============================================================
drop function if exists public.owner_upsert_ungani_commitment(
  uuid, text, uuid, uuid, text, numeric, text, date, date, text, boolean, text, text
);

CREATE OR REPLACE FUNCTION public.owner_upsert_ungani_commitment(p_commitment_id uuid DEFAULT NULL::uuid, p_commitment_type text DEFAULT NULL::text, p_person_id uuid DEFAULT NULL::uuid, p_linked_item_id uuid DEFAULT NULL::uuid, p_plan_name text DEFAULT NULL::text, p_amount numeric DEFAULT NULL::numeric, p_billing_frequency text DEFAULT 'monthly'::text, p_start_date date DEFAULT NULL::date, p_end_date date DEFAULT NULL::date, p_status text DEFAULT 'active'::text, p_auto_renew boolean DEFAULT false, p_section_label text DEFAULT NULL::text, p_notes text DEFAULT NULL::text, p_deposit_amount numeric DEFAULT NULL::numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_commitment_id uuid;
  v_clean_type text;
  v_clean_status text;
  v_person_tenant_check uuid;
  v_item_tenant_check uuid;
  v_existing_deposit_status text;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  v_clean_type := lower(trim(coalesce(p_commitment_type, '')));
  if v_clean_type not in ('lease', 'membership', 'service_contract', 'generic') then
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
    select deposit_status into v_existing_deposit_status
    from public.ungani_commitments
    where id = p_commitment_id and tenant_id = v_tenant_id;

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
        -- Once settled, deposit fields are frozen — only
        -- owner_settle_ungani_commitment_deposit may change them again.
        deposit_amount_kes = case
          when v_existing_deposit_status = 'settled' then deposit_amount_kes
          else p_deposit_amount
        end,
        deposit_status = case
          when v_existing_deposit_status = 'settled' then deposit_status
          when p_deposit_amount is not null and p_deposit_amount > 0 then 'held'
          else null
        end,
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
      notes, created_by, deposit_amount_kes, deposit_status
    )
    values (
      v_tenant_id, v_clean_type, p_person_id, p_linked_item_id,
      nullif(trim(coalesce(p_plan_name, '')), ''), p_amount,
      coalesce(nullif(trim(coalesce(p_billing_frequency, '')), ''), 'monthly'),
      p_start_date, p_end_date, v_clean_status, coalesce(p_auto_renew, false),
      nullif(trim(coalesce(p_section_label, '')), ''), nullif(trim(coalesce(p_notes, '')), ''),
      auth.uid(),
      p_deposit_amount,
      case when p_deposit_amount is not null and p_deposit_amount > 0 then 'held' else null end
    )
    returning id into v_commitment_id;
  end if;
return jsonb_build_object('ok', true, 'id', v_commitment_id, 'commitment_id', v_commitment_id);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

revoke all on function public.owner_upsert_ungani_commitment(
  uuid, text, uuid, uuid, text, numeric, text, date, date, text, boolean, text, text, numeric
) from public, anon;

grant execute on function public.owner_upsert_ungani_commitment(
  uuid, text, uuid, uuid, text, numeric, text, date, date, text, boolean, text, text, numeric
) to authenticated;

-- ============================================================
-- STEP 3: owner_settle_ungani_commitment_deposit
-- Deduction -> real Money income transaction (unpaid_rent uses the
-- 'Rental Income' category so it correctly clears Outstanding Rent;
-- damages uses 'Deposit Deduction' so it doesn't get miscounted as
-- rent). Refund -> NO transaction at all — amount/method/date/who are
-- recorded only on the lease row, so it never appears in Money totals
-- or Profit per property (both of which only ever read `transactions`).
-- ============================================================
CREATE OR REPLACE FUNCTION public.owner_settle_ungani_commitment_deposit(
  p_commitment_id uuid,
  p_refund_amount numeric DEFAULT 0,
  p_deduction_amount numeric DEFAULT 0,
  p_deduction_type text DEFAULT NULL::text,
  -- 'damages' | 'unpaid_rent'
  p_refund_method text DEFAULT NULL::text,
  p_note text DEFAULT NULL::text
)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
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

  -- Deduction only: a real income transaction. Refund never creates one.
  if v_deduction_amount > 0 then
    insert into public.transactions (
      tenant_id, transaction_type, amount, amount_kes, currency, category, category_name,
      description, transaction_date, related_person_id, related_item_id, created_by
    )
    values (
      v_tenant_id, 'income', v_deduction_amount, v_deduction_amount, 'KES',
      case when v_clean_deduction_type = 'unpaid_rent' then 'Rental Income' else 'Deposit Deduction' end,
      case when v_clean_deduction_type = 'unpaid_rent' then 'Rental Income' else 'Deposit Deduction (Damages)' end,
      'Deposit deduction — ' || coalesce(v_tenant_name, 'Tenant') ||
        coalesce(' (' || v_unit_name || ')', '') ||
        case when v_clean_deduction_type = 'unpaid_rent' then ' — applied to unpaid rent' else ' — damages' end,
      current_date, v_lease.person_id, v_lease.linked_item_id, auth.uid()
    )
    returning id into v_deduction_transaction_id;
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

revoke all on function public.owner_settle_ungani_commitment_deposit(
  uuid, numeric, numeric, text, text, text
) from public, anon;

grant execute on function public.owner_settle_ungani_commitment_deposit(
  uuid, numeric, numeric, text, text, text
) to authenticated;

-- ============================================================
-- STEP 4: get_my_ungani_commitments — add deposit fields (incl. the new
-- deposit_refund_method) to the returned JSON. Built from the LIVE body
-- (sql/diagnose-and-fix-commitments-rpc-missing.sql:166, confirmed the
-- version that fixed the earlier 404) — every line unchanged except the
-- new keys in jsonb_build_object.
-- ============================================================
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
      'created_at', c.created_at,
      'deposit_amount_kes', c.deposit_amount_kes,
      'deposit_status', c.deposit_status,
      'deposit_refunded_kes', c.deposit_refunded_kes,
      'deposit_refund_method', c.deposit_refund_method,
      'deposit_deducted_kes', c.deposit_deducted_kes,
      'deposit_deduction_type', c.deposit_deduction_type,
      'deposit_settlement_note', c.deposit_settlement_note,
      'deposit_settled_at', c.deposit_settled_at,
      'deposit_settled_by', c.deposit_settled_by
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
-- COMBINED VERIFICATION
-- ============================================================

-- 1. Exactly one overload of owner_upsert_ungani_commitment should exist.
select count(*) as owner_upsert_overload_count
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'owner_upsert_ungani_commitment';

-- 2. Its real signature, to eyeball (should be the 14-param list ending
-- in ..., text, text, numeric).
select p.proname, pg_get_function_identity_arguments(p.oid) as args
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('owner_upsert_ungani_commitment', 'owner_settle_ungani_commitment_deposit', 'get_my_ungani_commitments');

-- 3. Grant check: PUBLIC and anon should NOT be able to execute;
-- authenticated SHOULD. Expect false / false / true on every row.
select
  'owner_upsert_ungani_commitment' as fn,
  has_function_privilege('public', 'public.owner_upsert_ungani_commitment(uuid, text, uuid, uuid, text, numeric, text, date, date, text, boolean, text, text, numeric)', 'execute') as public_can_execute,
  has_function_privilege('anon', 'public.owner_upsert_ungani_commitment(uuid, text, uuid, uuid, text, numeric, text, date, date, text, boolean, text, text, numeric)', 'execute') as anon_can_execute,
  has_function_privilege('authenticated', 'public.owner_upsert_ungani_commitment(uuid, text, uuid, uuid, text, numeric, text, date, date, text, boolean, text, text, numeric)', 'execute') as authenticated_can_execute
union all
select
  'owner_settle_ungani_commitment_deposit',
  has_function_privilege('public', 'public.owner_settle_ungani_commitment_deposit(uuid, numeric, numeric, text, text, text)', 'execute'),
  has_function_privilege('anon', 'public.owner_settle_ungani_commitment_deposit(uuid, numeric, numeric, text, text, text)', 'execute'),
  has_function_privilege('authenticated', 'public.owner_settle_ungani_commitment_deposit(uuid, numeric, numeric, text, text, text)', 'execute')
union all
select
  'get_my_ungani_commitments',
  has_function_privilege('public', 'public.get_my_ungani_commitments()', 'execute'),
  has_function_privilege('anon', 'public.get_my_ungani_commitments()', 'execute'),
  has_function_privilege('authenticated', 'public.get_my_ungani_commitments()', 'execute');

-- 4. Deposit columns present (should list 9 rows incl. deposit_refund_method).
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_commitments'
  and column_name like 'deposit_%'
order by column_name;

commit;
