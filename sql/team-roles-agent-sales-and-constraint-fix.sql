-- TEAM test prep (2026-10-07). Three things, one migration:
--
-- 1. ungani_team_members_role_key_check only allows ('owner','manager',
--    'staff','viewer','accountant','frontdesk') - confirmed live via
--    sql/fix-team-members-role-check-constraint.sql. But
--    owner_upsert_ungani_team_member's own allowlist was widened to add
--    'teacher'/'administration' on 2026-09-23 (sql/education-vertical-
--    phase1-followup.sql) and the constraint was NEVER updated to match -
--    same bug class as the accountant/frontdesk miss before it. Real,
--    live consequence: hiring a Teacher or Administration role today
--    fails with a constraint violation. Fixing that here too, not just
--    adding agent/sales.
--
-- 2. owner_upsert_ungani_team_member: add 'agent' and 'sales' to the
--    allowlist. Full body below reproduced verbatim from the real,
--    confirmed-live 9-param definition (sql/trial-control-feature.sql,
--    run 2026-10-06) - only the allowlist line changes. Receptionist is
--    deliberately NOT a new role_key - Chris asked to keep using
--    'frontdesk' and relabel it "Front Desk / Receptionist" client-side
--    only (my-team-access.html), so nothing here.
--
-- 3. ungani_role_preset_sections: add 'agent' and 'sales' branches.
--    Full body below reproduced verbatim from the real, confirmed-live
--    definition (sql/fix-missing-accountant-frontdesk-preset-branches.sql) -
--    only two new elsif branches are added before the final else.
--    Presets (agreed with Chris):
--      Agent: People/Tasks/Calendar/Items view+create+edit (field agent
--        managing clients/listings/appointments), no Money/Reports/
--        delete, same dashboard/notifications/tools baseline as every
--        other role, same owner-only lockout on billing/package/
--        branches/settings.
--      Sales: Money view+create only (log a sale, can't edit/delete it
--        afterward) + Items view + People create/edit + Reports view,
--        no delete anywhere, same baseline/lockout as above.

begin;

alter table public.ungani_team_members
  drop constraint if exists ungani_team_members_role_key_check;

alter table public.ungani_team_members
  add constraint ungani_team_members_role_key_check
  check (role_key in (
    'owner', 'manager', 'staff', 'viewer', 'accountant', 'frontdesk',
    'teacher', 'administration', 'agent', 'sales'
  ));

create or replace function public.owner_upsert_ungani_team_member(
  p_full_name text,
  p_email text default null::text,
  p_phone text default null::text,
  p_role_key text default 'staff'::text,
  p_status text default 'active'::text,
  p_monthly_salary numeric default null::numeric,
  p_pay_frequency text default null::text,
  p_branch_id uuid default null::uuid,
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
  v_subscription_status text;
  v_package_key text;
  v_trial_granted_package_key text;
  v_trial_user_limit int;
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
  -- CHANGED: added 'agent' and 'sales' to the recognized list.
  if v_role not in ('owner', 'manager', 'staff', 'viewer', 'accountant', 'frontdesk', 'teacher', 'administration', 'agent', 'sales') then
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

  if p_branch_id is not null then
    select id into v_branch_id
    from public.branches
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

  select package_key into v_package_key
  from public.ungani_subscriptions
  where tenant_id = v_tenant_id;

  if v_package_key is null then
    select package_key into v_package_key
    from public.tenants
    where id = v_tenant_id;
  end if;

  select subscription_status, trial_granted_package_key
  into v_subscription_status, v_trial_granted_package_key
  from public.ungani_subscriptions
  where tenant_id = v_tenant_id;

  select p.user_limit
  into v_user_limit
  from public.ungani_packages p
  where p.package_key = v_package_key;

  if lower(coalesce(v_subscription_status, '')) = 'trial' then
    select p2.user_limit
    into v_trial_user_limit
    from public.ungani_packages p2
    where p2.package_key = v_trial_granted_package_key;

    v_user_limit := coalesce(v_trial_user_limit, 1);
  end if;

  if v_existing_id is null then
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
          'message', case
            when lower(coalesce(v_subscription_status, '')) = 'trial'
              then 'Your trial is limited to ' || v_user_limit || ' user(s) (including you). Choose a package to add more staff, or contact UNGANI to extend your trial.'
            else 'Your package allows up to ' || v_user_limit || ' user(s) (including you). Upgrade your package to add more staff.'
          end,
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

    if v_status = 'active' and v_user_limit is not null then
      select count(*)
      into v_active_members
      from public.ungani_team_members tm
      where tm.tenant_id = v_tenant_id
        and tm.id <> v_member_id
        and coalesce(tm.is_active, true) = true
        and tm.deactivated_at is null
        and lower(coalesce(tm.status, 'active')) <> 'disabled';

      if (v_active_members + 1) >= v_user_limit then
        return jsonb_build_object(
          'ok', false,
          'message', case
            when lower(coalesce(v_subscription_status, '')) = 'trial'
              then 'Your trial is limited to ' || v_user_limit || ' user(s) (including you). Choose a package to add more staff, or contact UNGANI to extend your trial.'
            else 'Your package allows up to ' || v_user_limit || ' user(s) (including you). Upgrade your package to add more staff.'
          end,
          'limit_reached', true,
          'user_limit', v_user_limit,
          'current_users', v_active_members + 1
        );
      end if;
    end if;

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
      is_active = (v_status <> 'disabled'),
      deactivated_at = case when v_status = 'disabled' then coalesce(deactivated_at, now()) else null end,
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
  elsif v_role = 'agent' then
    return query select * from (values
      ('dashboard', true, false, false, false),
      ('money', false, false, false, false),
      ('tasks', true, true, true, false),
      ('items', true, true, true, false),
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
  elsif v_role = 'sales' then
    return query select * from (values
      ('dashboard', true, false, false, false),
      ('money', true, true, false, false),
      ('tasks', false, false, false, false),
      ('items', true, false, false, false),
      ('people', true, true, true, false),
      ('records', false, false, false, false),
      ('documents', false, false, false, false),
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
  else
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

-- VERIFICATION
select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.ungani_team_members'::regclass
  and conname = 'ungani_team_members_role_key_check';

select proname, pg_get_function_identity_arguments(oid) as args
from pg_proc
where proname = 'owner_upsert_ungani_team_member'
  and pronamespace = 'public'::regnamespace;

select 'agent' as role, * from public.ungani_role_preset_sections('agent')
union all
select 'sales' as role, * from public.ungani_role_preset_sections('sales')
order by role, section_key;

commit;
