-- Payroll / staff-payment tracking (deliberately simple, NOT full payroll
-- processing - no PAYE/NSSF/NHIF, no payslips):
-- 1. A salary/wage figure recorded directly on the staff profile
--    (ungani_team_members), for reference only - nothing here calculates
--    or auto-generates anything from it.
-- 2. Individual payment records tagged to a real team member via a new
--    transactions.related_team_member_id column - same pattern as the
--    existing transactions.related_person_id column already used for
--    Property Management client_people linking.
-- 3. owner_upsert_ungani_team_member() / owner_get_ungani_team_members()
--    extended (NOT rewritten) to carry the two new salary fields. Real
--    current source pulled via sql/diagnose-payroll-tracking-source.sql
--    first and confirmed live - every existing permission check,
--    validation branch, and the insert/update-by-email logic is preserved
--    verbatim; only the two new fields are threaded through.
-- No changes needed to get_my_ungani_team_members_for_assignment() - it
-- already returns exactly {id, full_name, role_key} for active members,
-- which is all the Money form's "tag to a team member" dropdown needs.

-- ============================================================
-- STEP 1: schema
-- ============================================================

alter table public.ungani_team_members
  add column if not exists monthly_salary numeric,
  add column if not exists pay_frequency text;

alter table public.transactions
  add column if not exists related_team_member_id uuid references public.ungani_team_members(id);

-- ============================================================
-- STEP 2: owner_upsert_ungani_team_member - two new params appended
-- after the existing ones (both defaulted, so this is backward-
-- compatible with the current my-team-access.html call, which sends a
-- named-argument JSON body, not positional args).
-- ============================================================

create or replace function public.owner_upsert_ungani_team_member(
  p_full_name text,
  p_email text default null::text,
  p_phone text default null::text,
  p_role_key text default 'staff'::text,
  p_status text default 'active'::text,
  p_monthly_salary numeric default null,
  p_pay_frequency text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_member_id uuid;
  v_role text;
  v_status text;
  v_monthly_salary numeric;
  v_pay_frequency text;
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
  if v_role not in ('owner', 'manager', 'staff', 'viewer') then
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
  insert into public.ungani_team_members (
    tenant_id,
    full_name,
    email,
    phone,
    role_key,
    status,
    monthly_salary,
    pay_frequency,
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
    auth.uid()
  )
  on conflict do nothing
  returning id into v_member_id;
  if v_member_id is null and p_email is not null then
    select id
    into v_member_id
    from public.ungani_team_members
    where tenant_id = v_tenant_id
      and lower(coalesce(email, '')) = lower(trim(p_email))
    order by created_at desc
    limit 1;
    update public.ungani_team_members
    set
      full_name = nullif(trim(coalesce(p_full_name, full_name)), ''),
      phone = nullif(trim(coalesce(p_phone, phone)), ''),
      role_key = v_role,
      status = v_status,
      monthly_salary = v_monthly_salary,
      pay_frequency = v_pay_frequency,
      updated_at = now()
    where id = v_member_id;
  end if;
  perform public.log_ungani_activity(
    'staff_saved',
    'settings',
    'ungani_team_members',
    v_member_id,
    'Staff member saved or updated.',
    jsonb_build_object('role_key', v_role, 'status', v_status)
  );
  return jsonb_build_object(
    'ok', true,
    'team_member_id', v_member_id,
    'message', 'Staff member saved.'
  );
end;
$function$;

-- ============================================================
-- STEP 3: owner_get_ungani_team_members - adds monthly_salary/
-- pay_frequency to each returned member object, everything else
-- (permissions aggregation, ordering, owner-only gate) unchanged.
-- ============================================================

create or replace function public.owner_get_ungani_team_members()
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
    return jsonb_build_object('ok', false, 'members', '[]'::jsonb);
  end if;
  if public.is_my_ungani_tenant_owner(v_tenant_id) is not true then
    return jsonb_build_object('ok', false, 'members', '[]'::jsonb, 'message', 'Owner access required.');
  end if;
  return jsonb_build_object(
    'ok', true,
    'members',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', tm.id,
            'full_name', tm.full_name,
            'email', tm.email,
            'phone', tm.phone,
            'role_key', tm.role_key,
            'status', tm.status,
            'created_at', tm.created_at,
            'monthly_salary', tm.monthly_salary,
            'pay_frequency', tm.pay_frequency,
            'permissions',
            coalesce(
              (
                select jsonb_object_agg(
                  p.section_key,
                  jsonb_build_object(
                    'view', p.can_view,
                    'create', p.can_create,
                    'edit', p.can_edit,
                    'delete', p.can_delete
                  )
                )
                from public.ungani_staff_section_permissions p
                where p.team_member_id = tm.id
              ),
              '{}'::jsonb
            )
          )
          order by tm.created_at desc
        )
        from public.ungani_team_members tm
        where tm.tenant_id = v_tenant_id
      ),
      '[]'::jsonb
    )
  );
end;
$function$;

-- ============================================================
-- STEP 4: verification queries (read-only)
-- ============================================================

select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_team_members'
  and column_name in ('monthly_salary', 'pay_frequency');

select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'transactions'
  and column_name = 'related_team_member_id';
