-- Staff Role Presets: give Manager/Staff/Viewer sensible default
-- permissions across all 16 sections, instead of every new staff member
-- starting with zero permissions and the owner manually checking ~64
-- boxes (16 sections x 4 actions) by hand.
--
-- Real sources confirmed before writing this, not guessed:
--   - Permissions are NOT a jsonb column on ungani_team_members - they
--     live in a separate table, public.ungani_staff_section_permissions
--     (team_member_id, tenant_id, section_key, can_view, can_create,
--     can_edit, can_delete), confirmed via the real, current source of
--     get_my_ungani_staff_access() (sql/fix-staff-access-status-coalesce-
--     order.sql) and owner_get_ungani_team_members() (sql/payroll-staff-
--     payment-tracking.sql), both of which jsonb_object_agg from it.
--   - owner_set_ungani_staff_permission(p_team_member_id, p_section_key,
--     p_can_view, p_can_create, p_can_edit, p_can_delete) is the existing,
--     already-live, already-correct single-section writer (confirmed via
--     its real call site in my-team-access.html's savePermission()) - its
--     own SQL body isn't checked into any tracked migration (created
--     ad-hoc, like several other core RPCs this session), so rather than
--     guess its internals, this migration calls it as a black box from a
--     new orchestrator, exactly the same way a client would, 16 times in
--     a loop - no risk of diverging from its real owner/tenant checks.
--   - owner_upsert_ungani_team_member's real, current body (reproduced
--     verbatim below except the new preset-application block) is from
--     sql/fix-user-limit-enforcement.sql, the latest confirmed-live
--     version (includes the user-limit check).
--   - get_my_ungani_staff_access() force-overrides dashboard/tools/
--     notifications to view-only for every staff member regardless of
--     what's stored - confirmed in the same real source above. The
--     presets below still write sensible values for those 3 sections (so
--     the raw checkboxes in my-team-access.html look right), but they
--     have no actual effect on real access for those 3 - not a bug this
--     migration introduces, a pre-existing behavior.
--
-- Design decisions:
--   - Only 3 roles exist today (manager/staff/viewer) - CHECKed in
--     owner_upsert_ungani_team_member itself. This migration presets
--     those 3, does not add new roles (a separate scope decision if
--     wanted later).
--   - Viewer: view-only across all operational sections. No access at
--     all to billing/package/branches/settings (financial/subscription/
--     structural admin - owner-only).
--   - Staff: view+create+edit (no delete) on the 8 day-to-day operational
--     sections (money/tasks/items/people/records/documents/calendar/
--     support) - trusted to log and update, not trusted to permanently
--     remove records by default. View-only on dashboard/reports/
--     notifications/tools. Same billing/package/branches/settings
--     lockout as Viewer.
--   - Manager: full view+create+edit+delete on the same 8 operational
--     sections - a manager is trusted with cleanup/corrections. Adds
--     view-only on branches (useful context) on top of Staff's view-only
--     set. billing/package/settings STILL locked out even for Manager -
--     these touch the tenant's actual UNGANI subscription/payment/global
--     config, a step beyond operational management.
--   - Presets auto-apply in owner_upsert_ungani_team_member: on a
--     genuinely NEW member (seeds sensible defaults instead of nothing),
--     and whenever an EXISTING member's role_key actually changes
--     (promoting Staff -> Manager should visibly change what they can
--     do, not silently do nothing). If role_key is unchanged on an edit
--     (e.g. only salary or status changed), permissions are left
--     untouched - never clobbers an owner's manual per-member tweaks
--     just because they saved the form again.
--   - owner_apply_ungani_staff_role_preset() is also exposed as its own
--     RPC so my-team-access.html can offer an explicit "Reset to Role
--     Defaults" button on already-existing members (added before this
--     feature existed, or whose permissions have drifted) - retrofits
--     the same defaults on demand without waiting for a role change.

-- ============================================================
-- PART A: the preset data itself, as a small table-returning function -
-- one place to edit if the defaults ever need to change.
-- ============================================================

create or replace function public.ungani_role_preset_sections(p_role_key text)
returns table(section_key text, can_view boolean, can_create boolean, can_edit boolean, can_delete boolean)
language plpgsql
immutable
as $function$
declare
  v_role text := lower(trim(coalesce(p_role_key, 'staff')));
begin
  if v_role = 'viewer' then
    return query select * from (values
      ('dashboard', true, false, false, false),
      ('money', true, false, false, false),
      ('tasks', true, false, false, false),
      ('items', true, false, false, false),
      ('people', true, false, false, false),
      ('records', true, false, false, false),
      ('documents', true, false, false, false),
      ('calendar', true, false, false, false),
      ('support', true, false, false, false),
      ('reports', true, false, false, false),
      ('billing', false, false, false, false),
      ('package', false, false, false, false),
      ('branches', false, false, false, false),
      ('settings', false, false, false, false),
      ('notifications', true, false, false, false),
      ('tools', true, false, false, false)
    ) as t(section_key, can_view, can_create, can_edit, can_delete);
  elsif v_role = 'manager' then
    return query select * from (values
      ('dashboard', true, false, false, false),
      ('money', true, true, true, true),
      ('tasks', true, true, true, true),
      ('items', true, true, true, true),
      ('people', true, true, true, true),
      ('records', true, true, true, true),
      ('documents', true, true, true, true),
      ('calendar', true, true, true, true),
      ('support', true, true, true, true),
      ('reports', true, false, false, false),
      ('billing', false, false, false, false),
      ('package', false, false, false, false),
      ('branches', true, false, false, false),
      ('settings', false, false, false, false),
      ('notifications', true, false, false, false),
      ('tools', true, false, false, false)
    ) as t(section_key, can_view, can_create, can_edit, can_delete);
  else
    -- 'staff' (also the fallback for any unrecognized role_key, matching
    -- owner_upsert_ungani_team_member's own default-to-'staff' behavior).
    return query select * from (values
      ('dashboard', true, false, false, false),
      ('money', true, true, false, false),
      ('tasks', true, true, true, false),
      ('items', true, true, true, false),
      ('people', true, true, true, false),
      ('records', true, true, true, false),
      ('documents', true, true, true, false),
      ('calendar', true, true, true, false),
      ('support', true, true, true, false),
      ('reports', true, false, false, false),
      ('billing', false, false, false, false),
      ('package', false, false, false, false),
      ('branches', false, false, false, false),
      ('settings', false, false, false, false),
      ('notifications', true, false, false, false),
      ('tools', true, false, false, false)
    ) as t(section_key, can_view, can_create, can_edit, can_delete);
  end if;
end;
$function$;

-- ============================================================
-- PART B: the orchestrator - owner-only, verifies the team member
-- belongs to the caller's own tenant, then calls the existing (proven)
-- single-section writer once per section.
-- ============================================================

create or replace function public.owner_apply_ungani_staff_role_preset(p_team_member_id uuid, p_role_key text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_member_tenant_id uuid;
  v_row record;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;

  if public.is_my_ungani_tenant_owner(v_tenant_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'Only the business owner can manage staff access.');
  end if;

  select tenant_id into v_member_tenant_id
  from public.ungani_team_members
  where id = p_team_member_id;

  if v_member_tenant_id is null or v_member_tenant_id <> v_tenant_id then
    return jsonb_build_object('ok', false, 'message', 'Staff member not found.');
  end if;

  for v_row in select * from public.ungani_role_preset_sections(p_role_key) loop
    perform public.owner_set_ungani_staff_permission(
      p_team_member_id,
      v_row.section_key,
      v_row.can_view,
      v_row.can_create,
      v_row.can_edit,
      v_row.can_delete
    );
  end loop;

  return jsonb_build_object('ok', true, 'message', 'Role defaults applied.');
end;
$function$;

grant execute on function public.owner_apply_ungani_staff_role_preset(uuid, text) to authenticated;

-- ============================================================
-- PART C: owner_upsert_ungani_team_member - real current body
-- (verbatim from sql/fix-user-limit-enforcement.sql) plus the new
-- preset-application block. Everything above the "-- NEW: apply role
-- preset" comment is unchanged from the live version.
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
    returning id into v_member_id;
  end if;

  -- NEW: apply role preset permissions - on a genuinely new member
  -- (nothing was ever set for them), or when an existing member's role
  -- actually changed (promoting/demoting should visibly change what they
  -- can do). Leaves permissions alone on any other edit (salary, status,
  -- name, etc.) so per-member manual tweaks survive routine saves.
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

-- 1. Both new functions exist with correct signatures.
select p.proname, pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('ungani_role_preset_sections', 'owner_apply_ungani_staff_role_preset')
order by p.proname;

-- 2. authenticated has EXECUTE on the new client-facing RPC.
select routine_name, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name = 'owner_apply_ungani_staff_role_preset'
  and grantee = 'authenticated';

-- 3. owner_upsert_ungani_team_member now includes the preset-application
-- call.
select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'owner_upsert_ungani_team_member';

-- 4. Spot-check the preset data itself for all 3 roles.
select 'manager' as role, * from public.ungani_role_preset_sections('manager')
union all
select 'staff' as role, * from public.ungani_role_preset_sections('staff')
union all
select 'viewer' as role, * from public.ungani_role_preset_sections('viewer')
order by role, section_key;
