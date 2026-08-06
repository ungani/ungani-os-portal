-- Adds two new staff roles - Accountant and Front Desk - alongside the
-- existing Manager/Staff/Viewer. Purely additive: role_key is validated
-- by a soft normalize-or-fallback-to-'staff' check inside
-- owner_upsert_ungani_team_member (not a DB-level CHECK constraint), so
-- no migration risk there - just extending that list and adding two new
-- branches to ungani_role_preset_sections().
--
-- Defaults (confirmed with the user before writing this):
--   Accountant: full control (view/create/edit/delete) on Money - that
--     is their whole job. View-only on Reports, People (context: who a
--     payment is to/from), Documents (context: view receipts/invoices).
--     Same dashboard/notifications/tools view-only baseline as every
--     other role. No access to Tasks/Items/Records/Calendar/Support, and
--     the usual owner-only lockout on billing/package/branches/settings.
--   Front Desk: view/create/edit (no delete, same "trusted to log, not
--     to permanently remove" pattern as Staff) on People/Tasks/Calendar.
--     Same dashboard/notifications/tools view-only baseline. Deliberately
--     NO Reports access (unlike every other role) - Front Desk is scoped
--     tightly to People/Tasks/Calendar as requested. No access to
--     Money/Items/Records/Documents/Support, same owner-only lockout.
--
-- ============================================================
-- PART A: extend ungani_role_preset_sections() with 2 new branches.
-- Reproduces the real, current 3-role body verbatim (from
-- sql/staff-role-permission-presets.sql) and adds 'accountant' and
-- 'frontdesk' as two new elsif branches before the final else.
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
  elsif v_role = 'accountant' then
    return query select * from (values
      ('dashboard', true, false, false, false),
      ('money', true, true, true, true),
      ('tasks', false, false, false, false),
      ('items', false, false, false, false),
      ('people', true, false, false, false),
      ('records', false, false, false, false),
      ('documents', true, false, false, false),
      ('calendar', false, false, false, false),
      ('support', false, false, false, false),
      ('reports', true, false, false, false),
      ('billing', false, false, false, false),
      ('package', false, false, false, false),
      ('branches', false, false, false, false),
      ('settings', false, false, false, false),
      ('notifications', true, false, false, false),
      ('tools', true, false, false, false)
    ) as t(section_key, can_view, can_create, can_edit, can_delete);
  elsif v_role = 'frontdesk' then
    return query select * from (values
      ('dashboard', true, false, false, false),
      ('money', false, false, false, false),
      ('tasks', true, true, true, false),
      ('items', false, false, false, false),
      ('people', true, true, true, false),
      ('records', false, false, false, false),
      ('documents', false, false, false, false),
      ('calendar', true, true, true, false),
      ('support', false, false, false, false),
      ('reports', false, false, false, false),
      ('billing', false, false, false, false),
      ('package', false, false, false, false),
      ('branches', false, false, false, false),
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
-- PART B: extend owner_upsert_ungani_team_member's role normalize list.
-- Reproduces the real, current body verbatim (from
-- sql/fix-user-limit-enforcement.sql, the latest confirmed-live
-- version) except the one changed line, marked below.
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
  -- CHANGED: added 'accountant' and 'frontdesk' to the recognized list.
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

select 'accountant' as role, * from public.ungani_role_preset_sections('accountant')
union all
select 'frontdesk' as role, * from public.ungani_role_preset_sections('frontdesk')
order by role, section_key;

select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'owner_upsert_ungani_team_member';
