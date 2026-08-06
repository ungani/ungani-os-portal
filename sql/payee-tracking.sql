-- Payee tracking: a lightweight way to log payments to people who get
-- paid by the business but should never need a system login (a driver,
-- cleaner, waiter, casual laborer, etc.) - separate from
-- ungani_team_members, which is the login/role/permission table and
-- whose active rows count toward the package's paid user limit
-- (confirmed real in owner_upsert_ungani_team_member: every active,
-- non-disabled row is counted). Adding a no-login payee as a team
-- member would have silently eaten into the client's licensed seats -
-- this avoids that entirely by being a wholly separate, much simpler
-- table with no auth/role/permission concept at all.
--
-- Scope, confirmed with the user: expense-only, matching how
-- related_team_member_id already behaves today (no change to that
-- column or its existing behavior - this is purely additive).
--
-- Real sources confirmed before writing this:
--   - get_my_ungani_tenant_id() - existing, already-live function.
--   - transactions has a tenant_id column and an existing
--     related_team_member_id nullable FK (used throughout tonight's
--     payroll work) - related_payee_id is added the same way,
--     alongside it, not replacing it.

-- ============================================================
-- PART A: the payee table itself.
-- ============================================================

create table if not exists public.ungani_payees (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  full_name text not null,
  job_title text,
  status text not null default 'active',
  created_at timestamptz not null default now(),
  created_by uuid
);

alter table public.ungani_payees enable row level security;

drop policy if exists ungani_payees_tenant_select on public.ungani_payees;
create policy ungani_payees_tenant_select on public.ungani_payees
  for select
  using (tenant_id = public.get_my_ungani_tenant_id());

drop policy if exists ungani_payees_tenant_insert on public.ungani_payees;
create policy ungani_payees_tenant_insert on public.ungani_payees
  for insert
  with check (tenant_id = public.get_my_ungani_tenant_id());

drop policy if exists ungani_payees_tenant_update on public.ungani_payees;
create policy ungani_payees_tenant_update on public.ungani_payees
  for update
  using (tenant_id = public.get_my_ungani_tenant_id())
  with check (tenant_id = public.get_my_ungani_tenant_id());

-- ============================================================
-- PART B: related_payee_id on transactions, alongside (not replacing)
-- the existing related_team_member_id.
-- ============================================================

alter table public.transactions
  add column if not exists related_payee_id uuid references public.ungani_payees(id) on delete set null;

-- ============================================================
-- PART C: RPCs. All 3 only require real tenant membership (not
-- owner-only, unlike real staff invites) - deliberately low-friction,
-- since "add the new driver's name" shouldn't need the owner
-- personally, matching the user's "keep it simple" instruction.
-- ============================================================

create or replace function public.owner_upsert_ungani_payee(
  p_full_name text,
  p_job_title text default null,
  p_payee_id uuid default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_payee_id uuid;
  v_clean_name text;
  v_clean_title text;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  v_clean_name := nullif(trim(coalesce(p_full_name, '')), '');
  if v_clean_name is null then
    return jsonb_build_object('ok', false, 'message', 'Payee name is required.');
  end if;

  v_clean_title := nullif(trim(coalesce(p_job_title, '')), '');

  if p_payee_id is not null then
    update public.ungani_payees
    set full_name = v_clean_name,
        job_title = v_clean_title
    where id = p_payee_id and tenant_id = v_tenant_id
    returning id into v_payee_id;

    if v_payee_id is null then
      return jsonb_build_object('ok', false, 'message', 'Payee not found.');
    end if;
  else
    insert into public.ungani_payees (tenant_id, full_name, job_title, created_by)
    values (v_tenant_id, v_clean_name, v_clean_title, auth.uid())
    returning id into v_payee_id;
  end if;

  return jsonb_build_object('ok', true, 'id', v_payee_id, 'payee_id', v_payee_id);
end;
$function$;

grant execute on function public.owner_upsert_ungani_payee(text, text, uuid) to authenticated;

create or replace function public.owner_set_ungani_payee_status(p_payee_id uuid, p_status text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_status text;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  v_status := lower(trim(coalesce(p_status, 'active')));
  if v_status not in ('active', 'inactive') then
    v_status := 'active';
  end if;

  update public.ungani_payees
  set status = v_status
  where id = p_payee_id and tenant_id = v_tenant_id;

  return jsonb_build_object('ok', true);
end;
$function$;

grant execute on function public.owner_set_ungani_payee_status(uuid, text) to authenticated;

create or replace function public.get_my_ungani_payees()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_payees jsonb;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  select jsonb_agg(
    jsonb_build_object('id', id, 'full_name', full_name, 'job_title', job_title, 'status', status)
    order by full_name
  )
  into v_payees
  from public.ungani_payees
  where tenant_id = v_tenant_id
    and status = 'active';

  return jsonb_build_object('ok', true, 'payees', coalesce(v_payees, '[]'::jsonb));
end;
$function$;

grant execute on function public.get_my_ungani_payees() to authenticated;

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================

select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and (table_name = 'ungani_payees' or (table_name = 'transactions' and column_name = 'related_payee_id'))
order by table_name, column_name;

select routine_name, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name in ('owner_upsert_ungani_payee', 'owner_set_ungani_payee_status', 'get_my_ungani_payees')
  and grantee = 'authenticated'
order by routine_name;

select schemaname, tablename, policyname, cmd
from pg_policies
where schemaname = 'public' and tablename = 'ungani_payees'
order by policyname;
