-- CORRECTION to the migration run earlier tonight: that version copied
-- owner_upsert_ungani_team_member's body from sql/fix-user-limit-enforcement.sql
-- (Aug 5), a STALE 7-param signature from before multi-branch support was
-- added. Running it recreated the exact overload conflict already fixed
-- once (see sql/drop-stale-team-member-overload.sql, task #429) - the
-- real, currently-used function is the 9-param version from
-- sql/multi-branch-phase-a-schema-rls.sql (p_branch_id,
-- p_can_access_all_branches), which my-team-access.html always calls.
-- That version also has extended role validation ('accountant',
-- 'frontdesk') and applies role presets via
-- owner_apply_ungani_staff_role_preset() - none of which the stale
-- 7-param body has, so simply "picking the other one" would have
-- silently dropped that functionality for every future staff save.
--
-- Fix, in order:
-- 1. Drop the accidental 7-param overload this session created.
-- 2. Redefine the REAL 9-param version, reproduced verbatim from
--    sql/multi-branch-phase-a-schema-rls.sql, with the trial-cap check
--    inserted in the same spot as before (right after the package
--    user_limit lookup, before the existing "if v_user_limit is not
--    null" block) - everything else byte-for-byte unchanged, including
--    branch validation, role-preset application, and the email queue
--    block.

-- ============================================================
-- STEP 1: drop the accidental 7-param overload.
-- ============================================================

drop function if exists public.owner_upsert_ungani_team_member(
  text, text, text, text, text, numeric, text
);

-- ============================================================
-- STEP 2: redefine the real 9-param version with the trial cap added.
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
  v_subscription_status text;
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

  -- verify the requested branch actually belongs to this tenant, same
  -- pattern as owner_apply_ungani_staff_role_preset's team-member
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

    -- NEW: trial tenants are capped at 1 user (owner only) regardless of
    -- whatever the fallback package's own user_limit would allow -
    -- keyed off ungani_subscriptions.subscription_status (tenant_id is
    -- unique on that table, confirmed via the "on conflict (tenant_id)"
    -- constraint in sql/subscription-reminder-cadence-and-suspension.sql).
    select subscription_status
    into v_subscription_status
    from public.ungani_subscriptions
    where tenant_id = v_tenant_id;

    if lower(coalesce(v_subscription_status, '')) = 'trial' then
      v_user_limit := 1;
    end if;

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
              then 'Your free trial is limited to 1 user. Choose a package to add more staff.'
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
-- VERIFICATION - run this and confirm: exactly ONE row, 9 arguments,
-- and it includes p_branch_id/p_can_access_all_branches.
-- ============================================================

select
  p.oid::regprocedure as signature,
  pg_get_function_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'owner_upsert_ungani_team_member';
