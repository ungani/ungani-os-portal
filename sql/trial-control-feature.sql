-- =====================================================================
-- sql/trial-control-feature.sql
--
-- Trial Control: lets an admin grant a specific tenant an extended
-- trial (any package's user_limit, e.g. "business" = 10 users) with a
-- start/end date and a note, and have that number flow through to the
-- real gate instead of the hardcoded 1-user cap.
--
-- Real live body of owner_upsert_ungani_team_member below was pulled
-- directly via pg_get_functiondef() by the user and pasted back, not
-- guessed - two local sql/*.sql files disagreed with each other about
-- which version was "real" (one had the trial-cap check, one didn't),
-- so this is reproduced verbatim from the actual live function with
-- ONE targeted change: the hardcoded `v_user_limit := 1` block is
-- replaced with a lookup against the new trial_granted_package_key
-- column, defaulting to 1 when no admin grant exists (so every
-- existing/organic trial keeps behaving exactly as before - this is
-- additive, not a behavior change for anyone who hasn't been granted
-- an extended trial). Everything else - the 'teacher'/'administration'
-- role additions, the public.branches table reference, the
-- reactivation-path limit re-check, the email-queue block - is
-- untouched, byte-for-byte.
--
-- admin_update_ungani_subscription (the existing RPC behind the 19
-- billing scenarios in sql/item1-subscription-billing-test.sql) is
-- deliberately NOT touched - Trial Control gets its own RPC
-- (admin_set_ungani_trial_grant) so this migration can't regress any
-- of those already-tested billing paths.
-- =====================================================================

-- ---------------------------------------------------------------------
-- STEP 1: new columns on ungani_subscriptions. trial_start_at and
-- trial_end_at already exist (used by admin-subscriptions.html and
-- api/check-trial-warnings.js) - Trial Control reuses them directly
-- rather than adding parallel date columns.
-- ---------------------------------------------------------------------

alter table public.ungani_subscriptions
  add column if not exists trial_granted_package_key text null,
  add column if not exists trial_granted_by uuid null,
  add column if not exists trial_granted_at timestamptz null,
  add column if not exists trial_grant_note text null;

-- ---------------------------------------------------------------------
-- STEP 2: admin_set_ungani_trial_grant - the one write path for Trial
-- Control. Passing p_trial_package_key = null clears a grant (reverts
-- the tenant to the default 1-user trial cap) without touching
-- trial_start_at/trial_end_at, so an admin can "un-grant" the extra
-- seats without losing the trial's own date window.
-- ---------------------------------------------------------------------

create or replace function public.admin_set_ungani_trial_grant(
  p_tenant_id uuid,
  p_trial_package_key text default null,
  p_trial_start_at timestamptz default null,
  p_trial_end_at timestamptz default null,
  p_note text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_package_exists boolean;
begin
  if not (select public.is_ungani_admin()) then
    raise exception 'Access denied: admin only';
  end if;

  if p_trial_package_key is not null then
    select exists(
      select 1 from public.ungani_packages
      where package_key = p_trial_package_key and is_active = true
    ) into v_package_exists;

    if not v_package_exists then
      return jsonb_build_object('ok', false, 'message', 'Unknown or inactive package key: ' || p_trial_package_key);
    end if;
  end if;

  update public.ungani_subscriptions
  set
    trial_granted_package_key = p_trial_package_key,
    trial_start_at = coalesce(p_trial_start_at, trial_start_at),
    trial_end_at = coalesce(p_trial_end_at, trial_end_at),
    trial_grant_note = p_note,
    trial_granted_by = auth.uid(),
    trial_granted_at = now(),
    updated_at = now()
  where tenant_id = p_tenant_id;

  if not found then
    return jsonb_build_object('ok', false, 'message', 'No subscription row found for this tenant.');
  end if;

  perform public.log_ungani_activity(
    'trial_grant_updated',
    'subscriptions',
    'ungani_subscriptions',
    p_tenant_id,
    case when p_trial_package_key is null
      then 'Trial grant cleared (reverted to default 1-user trial).'
      else 'Trial grant set to package ' || p_trial_package_key || '.'
    end,
    jsonb_build_object('trial_package_key', p_trial_package_key, 'trial_end_at', p_trial_end_at)
  );

  return jsonb_build_object('ok', true);
end;
$function$;

revoke all on function public.admin_set_ungani_trial_grant(uuid, text, timestamptz, timestamptz, text) from public, anon;
grant execute on function public.admin_set_ungani_trial_grant(uuid, text, timestamptz, timestamptz, text) to authenticated;

-- ---------------------------------------------------------------------
-- STEP 3: owner_upsert_ungani_team_member - real live body (pulled via
-- pg_get_functiondef by the user), with only the trial-limit block
-- changed. Diff against the pasted live version: the single
-- `if ... then v_user_limit := 1; end if;` block is replaced with a
-- join against trial_granted_package_key, and both "limit reached"
-- messages now use the dynamic v_user_limit instead of a hardcoded
-- "1 user" string, since that number is no longer always 1.
-- ---------------------------------------------------------------------

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
  -- CHANGED: added 'teacher' and 'administration' to the recognized list.
  if v_role not in ('owner', 'manager', 'staff', 'viewer', 'accountant', 'frontdesk', 'teacher', 'administration') then
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

  -- TRIAL CONTROL: a trial tenant defaults to a 1-user cap, same as
  -- before - unless an admin has explicitly granted this tenant an
  -- extended trial via admin_set_ungani_trial_grant(), in which case
  -- the granted package's own user_limit applies (e.g. "business" =
  -- 10 users). No grant -> coalesce falls back to 1, so every existing
  -- trial tenant keeps today's exact behavior.
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

-- ---------------------------------------------------------------------
-- VERIFICATION - confirm exactly one row, 9 arguments.
-- ---------------------------------------------------------------------

select
  p.oid::regprocedure as signature,
  pg_get_function_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname = 'owner_upsert_ungani_team_member';
