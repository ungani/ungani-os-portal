-- Real gap confirmed via investigation + the user's own real schema
-- output: owner_upsert_ungani_team_member had ZERO limit-checking logic,
-- ungani_packages.user_limit is real (starter=2, growth=5, business=10,
-- custom=null/unlimited), and tenants.package_key is the live pointer.
--
-- Design decision (app-level, not a rebuilt trigger): every staff-
-- creation path in the app goes through this one RPC - there is no
-- other way to insert into ungani_team_members client-side - so
-- enforcing here covers 100% of the real surface. The limit is resolved
-- FRESH from the canonical ungani_packages table on every call, never a
-- denormalized copy that can drift stale - avoids the exact staleness
-- risk that made the old trigger (permanently dropped, see
-- sql/drop-broken-subscription-package-trigger.sql) both buggy and
-- unnecessary in the first place.
--
-- "User limit" is interpreted as TOTAL seats INCLUDING the owner
-- (matches the package copy - "Up to 2 users" - and standard SaaS
-- convention). The owner is never a row in ungani_team_members
-- (confirmed: get_my_ungani_staff_access() resolves the owner via
-- registrations entirely separately from the team-member lookup), so
-- the check is "1 (owner) + active team member count >= limit".
--
-- "Active" mirrors the exact definition get_my_ungani_staff_access()
-- already uses for real staff-access matching: coalesce(is_active,true)
-- = true, deactivated_at is null, status not 'disabled' - so someone
-- who's disabled or deactivated doesn't count against the limit,
-- freeing their seat immediately.
--
-- Restructured the new-vs-existing detection: instead of the old
-- "insert with on conflict do nothing, then fall back to find-by-email
-- if it silently no-op'd" indirection, this checks for an existing
-- member by email UP FRONT - gives a definite, direct answer to "is
-- this actually a new seat" before anything is written, which the
-- limit check needs. The limit is ONLY ever checked on a genuinely new
-- seat - editing an existing member (role, salary, status, etc.) never
-- triggers it, no matter how full the tenant's package is.
--
-- Everything else (role/status normalization, log_ungani_activity,
-- the team-invitation email queueing block) is reproduced verbatim
-- from the current live version.

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
  v_role text;
  v_status text;
  v_monthly_salary numeric;
  v_pay_frequency text;
  v_clean_email text;
  v_tenant_name text;
  v_email_queue_error text;
  v_user_limit int;
  v_active_members int;
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

  -- NEW: determine up front whether this is an edit to an existing
  -- member (matched by email) or a genuinely new seat.
  if p_email is not null then
    select id into v_existing_id
    from public.ungani_team_members
    where tenant_id = v_tenant_id
      and lower(coalesce(email, '')) = lower(trim(p_email))
    order by created_at desc
    limit 1;
  end if;

  -- NEW: enforce the package's user limit - only when this save would
  -- actually add a new seat.
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
        raise warning 'Could not queue team-invitation email for member %: %', v_member_id, sqlerrm;
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'team_member_id', v_member_id,
    'message', 'Staff member saved.',
    'email_queue_error', v_email_queue_error
  );
end;
$function$;

-- ============================================================
-- Verification - confirm the redefinition landed.
-- ============================================================

select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'owner_upsert_ungani_team_member';

-- ============================================================
-- Sanity check against real data - DENWILL BUILDERS LIMITED (starter,
-- limit 2, 1 active team member) should now be AT its limit (1 owner +
-- 1 staff = 2). Confirms the exact real-world case the diagnostic
-- surfaced.
-- ============================================================

select
  t.business_name,
  t.package_key,
  p.user_limit,
  (
    select count(*) from public.ungani_team_members tm
    where tm.tenant_id = t.id
      and coalesce(tm.is_active, true) = true
      and tm.deactivated_at is null
      and lower(coalesce(tm.status, 'active')) <> 'disabled'
  ) as active_team_members,
  1 + (
    select count(*) from public.ungani_team_members tm
    where tm.tenant_id = t.id
      and coalesce(tm.is_active, true) = true
      and tm.deactivated_at is null
      and lower(coalesce(tm.status, 'active')) <> 'disabled'
  ) as total_users_including_owner
from public.tenants t
join public.ungani_packages p on p.package_key = t.package_key
where t.business_name = 'DENWILL BUILDERS LIMITED';
