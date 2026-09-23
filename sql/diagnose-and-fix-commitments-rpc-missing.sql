-- Diagnoses + fixes the live 404 on get_my_ungani_commitments() found during
-- tonight's testing (PGRST202 "function not found in schema cache"). The
-- SQL in sql/cluster4-commitments.sql is internally correct (table, RPC,
-- and grant all defined properly) - this 404 means that file was likely
-- only PARTIALLY run live, or this one function's creation silently failed.
--
-- Deliberately NOT re-running the whole 989-line cluster4-commitments.sql -
-- its backfill INSERT (real-estate lease rows) has no dedup guard, so
-- re-running it would risk duplicate lease commitment rows for any tenant
-- already backfilled. This file only re-applies the two pieces that are
-- safe to run any number of times: the function definition (CREATE OR
-- REPLACE) and its grant.

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
-- PART 2: FIX - re-creates only get_my_ungani_commitments(), byte-identical
-- to sql/cluster4-commitments.sql lines 213-261. Safe to run regardless of
-- what PART 1 shows, since CREATE OR REPLACE + GRANT are both idempotent.
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
-- PART 3: RE-VERIFY - run after PART 2, paste back the output.
-- ============================================================

select routine_name from information_schema.routines
where routine_schema = 'public' and routine_name = 'get_my_ungani_commitments';
