-- Multi-branch Phase A: genuine branch-based visibility RESTRICTION
-- (not just tagging) for Tasks, Money (transactions), and People
-- (client_people) - the 3 highest-traffic operational tables. Items/
-- Records/Documents/Calendar are a proposed Phase B, not built here.
--
-- Design decisions confirmed with the user before writing this:
--   - NULL branch_id (all existing records, and any record created by
--     the owner or an unassigned staff member) is visible to EVERYONE -
--     the safe default, so nothing silently disappears the day this
--     ships. Only records with a REAL branch_id get restricted.
--   - Owner always sees everything, regardless of branch_id, always.
--   - A staff member can be granted can_access_all_branches to bypass
--     restriction (explicit cross-branch grant) even if they also have
--     their own branch_id set.
--
-- Real sources confirmed before writing this, not guessed:
--   - ungani_branches(id, tenant_id, branch_name, location, status,
--     created_at) - confirmed via the real RPC response shape rendered
--     in my-branches.html (renderBranches() reads branch.id/
--     branch_name/location/status/created_at).
--   - ungani_team_members.auth_user_id - confirmed real column, referenced
--     in sql/task-assignment-linking-my-tasks-notifications.sql.
--   - get_my_ungani_tenant_id() and is_my_ungani_tenant_owner(tenant_id)
--     are existing, already-live functions (used as black boxes here,
--     same pattern as staff-role-permission-presets.sql).
--   - tasks/transactions/client_people all have a tenant_id column
--     (used throughout this session's other migrations on these same
--     3 tables).
--
-- Technical approach - why a RESTRICTIVE policy instead of editing the
-- existing SELECT/INSERT/UPDATE/DELETE policies on these tables: this
-- session doesn't have the exact current text of those policies checked
-- into any tracked migration, and per the standing "never extend from a
-- guessed body" rule, editing them blind is exactly the kind of mistake
-- to avoid. Postgres RLS ANDs together all RESTRICTIVE policies with
-- the (OR-combined) set of PERMISSIVE policies for a given command -
-- so adding a RESTRICTIVE policy here layers the branch check on top of
-- whatever tenant/permission logic already exists, without needing to
-- know or touch it.
--
-- Why an auto-tagging trigger instead of a UI branch-picker on the
-- Tasks/Money/People forms: "by default" was the user's own phrasing -
-- a record created by a branch-restricted staff member should
-- automatically belong to their branch without them having to remember
-- to pick it from a dropdown every time. This also means zero changes
-- are needed to my-tasks.html/my-money.html/my-people.html's forms.

-- ============================================================
-- PART A: schema - branch_id on the 3 operational tables, plus the
-- staff-assignment columns on ungani_team_members.
-- ============================================================

alter table public.ungani_team_members
  add column if not exists branch_id uuid references public.ungani_branches(id) on delete set null,
  add column if not exists can_access_all_branches boolean not null default false;

alter table public.tasks
  add column if not exists branch_id uuid references public.ungani_branches(id) on delete set null;

alter table public.transactions
  add column if not exists branch_id uuid references public.ungani_branches(id) on delete set null;

alter table public.client_people
  add column if not exists branch_id uuid references public.ungani_branches(id) on delete set null;

-- ============================================================
-- PART B: auto-tagging trigger - on INSERT, if branch_id wasn't
-- explicitly provided, fill it from the inserting staff member's own
-- branch assignment. Owner inserts (no ungani_team_members row) and
-- unassigned-staff inserts both leave branch_id NULL, correctly.
-- ============================================================

create or replace function public.ungani_auto_tag_branch_id()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_branch_id uuid;
begin
  if new.branch_id is not null then
    return new;
  end if;

  select tm.branch_id
  into v_branch_id
  from public.ungani_team_members tm
  where tm.tenant_id = new.tenant_id
    and tm.auth_user_id = auth.uid()
  limit 1;

  new.branch_id := v_branch_id;
  return new;
end;
$function$;

drop trigger if exists tasks_auto_tag_branch_id on public.tasks;
create trigger tasks_auto_tag_branch_id
  before insert on public.tasks
  for each row execute function public.ungani_auto_tag_branch_id();

drop trigger if exists transactions_auto_tag_branch_id on public.transactions;
create trigger transactions_auto_tag_branch_id
  before insert on public.transactions
  for each row execute function public.ungani_auto_tag_branch_id();

drop trigger if exists client_people_auto_tag_branch_id on public.client_people;
create trigger client_people_auto_tag_branch_id
  before insert on public.client_people
  for each row execute function public.ungani_auto_tag_branch_id();

-- ============================================================
-- PART C: the access-check function + RESTRICTIVE RLS policies.
-- ============================================================

create or replace function public.ungani_can_access_branch(p_branch_id uuid, p_row_tenant_id uuid)
returns boolean
language plpgsql
stable
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_is_owner boolean;
  v_staff_branch_id uuid;
  v_can_access_all boolean;
begin
  -- No branch assigned to this row = visible to everyone (the safe
  -- default agreed with the user - nothing disappears on launch day).
  if p_branch_id is null then
    return true;
  end if;

  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null or v_tenant_id <> p_row_tenant_id then
    return false;
  end if;

  v_is_owner := coalesce(public.is_my_ungani_tenant_owner(v_tenant_id), false);
  if v_is_owner then
    return true;
  end if;

  select tm.branch_id, coalesce(tm.can_access_all_branches, false)
  into v_staff_branch_id, v_can_access_all
  from public.ungani_team_members tm
  where tm.tenant_id = v_tenant_id
    and tm.auth_user_id = auth.uid()
  limit 1;

  if coalesce(v_can_access_all, false) then
    return true;
  end if;

  return v_staff_branch_id is not null and v_staff_branch_id = p_branch_id;
end;
$function$;

grant execute on function public.ungani_can_access_branch(uuid, uuid) to authenticated;

alter table public.tasks enable row level security;
alter table public.transactions enable row level security;
alter table public.client_people enable row level security;

drop policy if exists tasks_branch_restrict on public.tasks;
create policy tasks_branch_restrict on public.tasks
  as restrictive
  for all
  using (public.ungani_can_access_branch(branch_id, tenant_id))
  with check (public.ungani_can_access_branch(branch_id, tenant_id));

drop policy if exists transactions_branch_restrict on public.transactions;
create policy transactions_branch_restrict on public.transactions
  as restrictive
  for all
  using (public.ungani_can_access_branch(branch_id, tenant_id))
  with check (public.ungani_can_access_branch(branch_id, tenant_id));

drop policy if exists client_people_branch_restrict on public.client_people;
create policy client_people_branch_restrict on public.client_people
  as restrictive
  for all
  using (public.ungani_can_access_branch(branch_id, tenant_id))
  with check (public.ungani_can_access_branch(branch_id, tenant_id));

-- ============================================================
-- PART D: extend owner_upsert_ungani_team_member with branch
-- assignment. Reproduces the version from
-- sql/staff-role-presets-accountant-frontdesk.sql verbatim (run that
-- file BEFORE this one) plus 2 new trailing optional parameters,
-- marked below.
-- ============================================================

create or replace function public.owner_upsert_ungani_team_member(
  p_full_name text,
  p_email text default null::text,
  p_phone text default null::text,
  p_role_key text default 'staff'::text,
  p_status text default 'active'::text,
  p_monthly_salary numeric default null,
  p_pay_frequency text default null,
  p_branch_id uuid default null,
  p_can_access_all_branches boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_member_id uuid;
  v_existing_id uuid;
  v_old_role text;
  v_role text;
  v_status text;
  v_monthly_salary numeric;
  v_pay_frequency text;
  v_clean_email text;
  v_tenant_name text;
  v_email_queue_error text;
  v_user_limit int;
  v_active_members int;
  v_is_new_member boolean;
  v_branch_id uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;
  if public.is_my_ungani_tenant_owner(v_tenant_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'Only the business owner can manage staff access.');
  end if;
  v_role := lower(trim(coalesce(p_role_key, 'staff')));
  v_status := lower(trim(coalesce(p_status, 'active')));
  if v_role not in ('owner', 'manager', 'staff', 'viewer', 'accountant', 'frontdesk') then
    v_role := 'staff';
  end if;
  if v_status not in ('active', 'invited', 'disabled') then
    v_status := 'active';
  end if;
  v_monthly_salary := case when p_monthly_salary is not null and p_monthly_salary >= 0 then p_monthly_salary else null end;
  v_pay_frequency := lower(trim(coalesce(p_pay_frequency, '')));
  if v_pay_frequency not in ('monthly', 'weekly', 'daily') then
    v_pay_frequency := null;
  end if;

  -- NEW: verify the requested branch actually belongs to this tenant,
  -- same pattern as owner_apply_ungani_staff_role_preset's team-member
  -- ownership check - never trust a client-supplied ID without
  -- re-checking it's actually this tenant's own row.
  if p_branch_id is not null then
    select id into v_branch_id
    from public.ungani_branches
    where id = p_branch_id and tenant_id = v_tenant_id;
  else
    v_branch_id := null;
  end if;

  if p_email is not null then
    select id, role_key into v_existing_id, v_old_role
    from public.ungani_team_members
    where tenant_id = v_tenant_id
      and lower(coalesce(email, '')) = lower(trim(p_email))
    order by created_at desc
    limit 1;
  end if;

  if v_existing_id is null then
    select p.user_limit
    into v_user_limit
    from public.tenants t
    join public.ungani_packages p on p.package_key = t.package_key
    where t.id = v_tenant_id;

    if v_user_limit is not null then
      select count(*)
      into v_active_members
      from public.ungani_team_members tm
      where tm.tenant_id = v_tenant_id
        and coalesce(tm.is_active, true) = true
        and tm.deactivated_at is null
        and lower(coalesce(tm.status, 'active')) <> 'disabled';

      if (v_active_members + 1) >= v_user_limit then
        return jsonb_build_object(
          'ok', false,
          'message', 'Your package allows up to ' || v_user_limit || ' user(s) (including you). Upgrade your package to add more staff.',
          'limit_reached', true,
          'user_limit', v_user_limit,
          'current_users', v_active_members + 1
        );
      end if;
    end if;
  end if;

  v_is_new_member := v_existing_id is null;

  if v_existing_id is not null then
    v_member_id := v_existing_id;

    update public.ungani_team_members
    set
      full_name = nullif(trim(coalesce(p_full_name, full_name)), ''),
      phone = nullif(trim(coalesce(p_phone, phone)), ''),
      role_key = v_role,
      status = v_status,
      monthly_salary = v_monthly_salary,
      pay_frequency = v_pay_frequency,
      branch_id = v_branch_id,
      can_access_all_branches = coalesce(p_can_access_all_branches, false),
      updated_at = now()
    where id = v_member_id;
  else
    insert into public.ungani_team_members (
      tenant_id,
      full_name,
      email,
      phone,
      role_key,
      status,
      monthly_salary,
      pay_frequency,
      branch_id,
      can_access_all_branches,
      created_by
    )
    values (
      v_tenant_id,
      nullif(trim(coalesce(p_full_name, '')), ''),
      nullif(lower(trim(coalesce(p_email, ''))), ''),
      nullif(trim(coalesce(p_phone, '')), ''),
      v_role,
      v_status,
      v_monthly_salary,
      v_pay_frequency,
      v_branch_id,
      coalesce(p_can_access_all_branches, false),
      auth.uid()
    )
    returning id into v_member_id;
  end if;

  if v_member_id is not null and (v_is_new_member or coalesce(v_old_role, '') <> v_role) then
    perform public.owner_apply_ungani_staff_role_preset(v_member_id, v_role);
  end if;

  perform public.log_ungani_activity(
    'staff_saved',
    'settings',
    'ungani_team_members',
    v_member_id,
    'Staff member saved or updated.',
    jsonb_build_object('role_key', v_role, 'status', v_status)
  );

  if v_member_id is not null then
    begin
      v_clean_email := nullif(trim(coalesce(p_email, '')), '');

      if v_clean_email is not null then
        select business_name into v_tenant_name from public.tenants where id = v_tenant_id;

        if not exists (
          select 1 from public.ungani_email_queue
          where email_type = 'team_invitation'
            and related_table = 'ungani_team_members'
            and related_id = v_member_id
        ) then
          insert into public.ungani_email_queue (
            tenant_id,
            recipient_email,
            recipient_name,
            email_subject,
            email_body,
            email_type,
            related_table,
            related_id,
            send_status,
            created_at
          ) values (
            v_tenant_id,
            v_clean_email,
            coalesce(nullif(trim(p_full_name), ''), 'there'),
            'You''ve been added to ' || coalesce(v_tenant_name, 'a UNGANI OS business') || ' on UNGANI OS',
            'Hi ' || coalesce(nullif(trim(p_full_name), ''), 'there') || E',\n\n' ||
            'You''ve been added as staff for ' || coalesce(v_tenant_name, 'a business') || ' on UNGANI OS.' || E'\n\n' ||
            'To get started, create your password here: https://ungani-os-portal.vercel.app/staff-login.html' || E'\n\n' ||
            'Use this email address (' || v_clean_email || ') when creating your password.' || E'\n\n' ||
            'Regards,' || E'\n' ||
            'UNGANI' || E'\n' ||
            'info@ungani.com',
            'team_invitation',
            'ungani_team_members',
            v_member_id,
            'pending',
            now()
          );
        end if;
      end if;
    exception
      when others then
        v_email_queue_error := sqlerrm;
        raise warning 'Could not queue team invitation email for member %: %', v_member_id, v_email_queue_error;
    end;
  end if;

  return jsonb_build_object('ok', true, 'id', v_member_id, 'team_member_id', v_member_id);
end;
$function$;

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================

-- 1. New columns exist.
select table_name, column_name, data_type
from information_schema.columns
where table_schema = 'public'
  and (
    (table_name = 'ungani_team_members' and column_name in ('branch_id', 'can_access_all_branches'))
    or (table_name in ('tasks', 'transactions', 'client_people') and column_name = 'branch_id')
  )
order by table_name, column_name;

-- 2. Triggers exist on all 3 tables.
select event_object_table, trigger_name, action_timing, event_manipulation
from information_schema.triggers
where trigger_schema = 'public'
  and trigger_name like '%auto_tag_branch_id'
order by event_object_table;

-- 3. Restrictive policies exist on all 3 tables.
select schemaname, tablename, policyname, permissive, cmd
from pg_policies
where schemaname = 'public'
  and policyname like '%branch_restrict'
order by tablename;

-- 4. authenticated has EXECUTE on the new function.
select routine_name, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name = 'ungani_can_access_branch'
  and grantee = 'authenticated';
