-- Diagnoses + fixes the live 404 on get_my_ungani_commitments() found during
-- tonight's testing (PGRST202 "function not found in schema cache"). The
-- SQL in sql/cluster4-commitments.sql is internally correct (table, RPC,
-- and grant all defined properly) - this 404 means that file was likely
-- only PARTIALLY run live, or this one function's creation silently failed.
-- CONFIRMED (see PART 1B below): both owner_upsert_ungani_commitment
-- (write) and get_my_ungani_commitments (read) were never created live -
-- this file fixes both, not just the read function.
--
-- Deliberately NOT re-running the whole 989-line cluster4-commitments.sql -
-- its backfill INSERT (real-estate lease rows) has no dedup guard, so
-- re-running it would risk duplicate lease commitment rows for any tenant
-- already backfilled. This file only re-applies the pieces that are safe
-- to run any number of times: both function definitions (CREATE OR
-- REPLACE) and their grants.

-- ============================================================
-- PART 1: DIAGNOSTIC - run this first and paste back the output, so we
-- know what's actually missing before assuming the fix below is complete.
-- ============================================================

select table_name
from information_schema.tables
where table_schema = 'public' and table_name = 'ungani_commitments';

select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'tenants' and column_name = 'commitments_enabled';

select routine_name, security_type
from information_schema.routines
where routine_schema = 'public'
  and routine_name in ('owner_upsert_ungani_commitment', 'get_my_ungani_commitments')
order by routine_name;

select count(*) as existing_commitment_rows from public.ungani_commitments;

-- ============================================================
-- PART 1B: CONFIRMED (2026-09-23) - Chris ran PART 1 and pasted back the
-- output: ungani_commitments table exists, tenants.commitments_enabled
-- exists, existing_commitment_rows = 0, and BOTH
-- owner_upsert_ungani_commitment and get_my_ungani_commitments returned
-- zero rows from information_schema.routines - neither function was ever
-- created live. Confirms the "partially run migration" theory exactly.
-- PART 2 below now fixes both functions, not just the read one.
-- ============================================================

-- ============================================================
-- PART 2: FIX - re-creates both RPCs, byte-identical to
-- sql/cluster4-commitments.sql lines 100-261. Safe to run regardless of
-- what PART 1 shows, since CREATE OR REPLACE + GRANT are both idempotent.
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
-- PART 3: RE-VERIFY - run after PART 2, paste back the output. Should now
-- return both rows (it returned zero before PART 2 ran).
-- ============================================================

select routine_name, security_type from information_schema.routines
where routine_schema = 'public'
  and routine_name in ('owner_upsert_ungani_commitment', 'get_my_ungani_commitments')
order by routine_name;
