-- Fixes a confirmed, live security gap found while running the Demo
-- Properties Ltd TEAM test tonight: a staff member who is still logged in
-- (valid browser session) keeps FULL access to every page/data they could
-- see before being disabled - confirmed live by disabling Samuel Kiptoo
-- (sales) in one browser context while he was already loaded in another,
-- then navigating his still-open session straight to my-money.html, which
-- rendered all 10 real money records with full totals, instead of being
-- blocked.
--
-- Root cause: get_my_ungani_staff_access()'s member lookup already
-- correctly excludes disabled rows (is_active=false / deactivated_at set /
-- status='disabled' - confirmed via sql/fix-team-member-reenable-bug.sql),
-- but when that lookup finds nothing it falls through to the SAME generic
-- 'guest' response used for a real owner who has never touched Team
-- Access. staff-permission-guard.js was deliberately written to treat
-- role_key='guest' as "not a confirmed staff record, don't restrict" -
-- correct for that owner case, but it can't distinguish "never was staff"
-- from "was staff, now disabled." A disabled staff member hits the same
-- bucket and the guard waves them through.
--
-- Fix: add a second lookup (ignoring the is_active/status filters) that
-- specifically detects "this login matches a team_members row that exists
-- but is disabled," and return a distinct account_type='disabled_staff'
-- signal instead of the generic guest response. Paired with a
-- staff-permission-guard.js change (already in this commit) that checks
-- for that signal first and force-signs-out + blocks, rather than letting
-- it fall into the "maybe this is an owner" skip path.
--
-- Full body below is reproduced verbatim from sql/fix-staff-access-status-
-- coalesce-order.sql (that file's own header states it matches what's
-- currently live, save for one documented coalesce-order change) - the
-- ONLY change here is the new disabled-member branch inserted before the
-- final generic guest return.

CREATE OR REPLACE FUNCTION public.get_my_ungani_staff_access()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_user_id uuid := auth.uid();
  v_email text;
  v_owner_tenant_id uuid;
  v_member record;
  v_permissions jsonb;
  v_role_key text;
  v_disabled_member_id uuid;
begin
  if v_user_id is null then
    return jsonb_build_object(
      'ok', false,
      'can_access', false,
      'role_key', 'guest',
      'account_type', 'guest',
      'message', 'No authenticated user found.'
    );
  end if;

  select email
  into v_email
  from auth.users
  where id = v_user_id
  limit 1;

  select r.tenant_id
  into v_owner_tenant_id
  from public.registrations r
  where r.tenant_id is not null
    and lower(coalesce(r.status, r.registration_status, 'pending')) in ('approved', 'active', 'trial')
    and (
      r.auth_user_id = v_user_id
      or lower(coalesce(r.contact_email, r.email, '')) = lower(coalesce(v_email, ''))
    )
  order by r.created_at desc
  limit 1;

  if v_owner_tenant_id is not null then
    return jsonb_build_object(
      'ok', true,
      'can_access', true,
      'tenant_id', v_owner_tenant_id,
      'role_key', 'owner',
      'access_level', 'owner',
      'is_owner', true,
      'account_type', 'owner',
      'permissions', jsonb_build_object(
        'dashboard', jsonb_build_object('view', true, 'create', true, 'edit', true, 'delete', true),
        'money', jsonb_build_object('view', true, 'create', true, 'edit', true, 'delete', true),
        'tasks', jsonb_build_object('view', true, 'create', true, 'edit', true, 'delete', true),
        'items', jsonb_build_object('view', true, 'create', true, 'edit', true, 'delete', true),
        'people', jsonb_build_object('view', true, 'create', true, 'edit', true, 'delete', true),
        'records', jsonb_build_object('view', true, 'create', true, 'edit', true, 'delete', true),
        'documents', jsonb_build_object('view', true, 'create', true, 'edit', true, 'delete', true),
        'calendar', jsonb_build_object('view', true, 'create', true, 'edit', true, 'delete', true),
        'support', jsonb_build_object('view', true, 'create', true, 'edit', true, 'delete', true),
        'reports', jsonb_build_object('view', true, 'create', true, 'edit', true, 'delete', true),
        'billing', jsonb_build_object('view', true, 'create', true, 'edit', true, 'delete', true),
        'package', jsonb_build_object('view', true, 'create', true, 'edit', true, 'delete', true),
        'branches', jsonb_build_object('view', true, 'create', true, 'edit', true, 'delete', true),
        'settings', jsonb_build_object('view', true, 'create', true, 'edit', true, 'delete', true),
        'notifications', jsonb_build_object('view', true, 'create', true, 'edit', true, 'delete', true),
        'tools', jsonb_build_object('view', true, 'create', true, 'edit', true, 'delete', true)
      )
    );
  end if;

  select *
  into v_member
  from public.ungani_team_members tm
  where tm.tenant_id is not null
    and coalesce(tm.is_owner, false) = false
    and coalesce(tm.is_active, true) = true
    and tm.deactivated_at is null
    and lower(coalesce(tm.status, 'active')) in ('active', 'accepted')
    and (
      tm.auth_user_id = v_user_id
      or lower(coalesce(tm.email, '')) = lower(coalesce(v_email, ''))
    )
  order by tm.created_at desc
  limit 1;

  if v_member.id is not null then
    begin
      perform public.sync_my_ungani_staff_workspace();
    exception
      when others then
        null;
    end;

    select coalesce(
      jsonb_object_agg(
        lower(trim(p.section_key)),
        jsonb_build_object(
          'view', coalesce(p.can_view, false),
          'create', coalesce(p.can_create, false),
          'edit', coalesce(p.can_edit, false),
          'delete', coalesce(p.can_delete, false)
        )
      ),
      '{}'::jsonb
    )
    into v_permissions
    from public.ungani_staff_section_permissions p
    where p.team_member_id = v_member.id
      and p.tenant_id = v_member.tenant_id;

    v_permissions :=
      coalesce(v_permissions, '{}'::jsonb)
      || jsonb_build_object(
        'dashboard', jsonb_build_object('view', true, 'create', false, 'edit', false, 'delete', false),
        'tools', jsonb_build_object('view', true, 'create', false, 'edit', false, 'delete', false),
        'notifications', jsonb_build_object('view', true, 'create', false, 'edit', false, 'delete', false)
      );

    v_role_key := coalesce(
      nullif(v_member.role_key, ''),
      nullif(v_member.access_level, ''),
      case
        when coalesce(v_member.is_branch_manager, false) = true then 'branch_manager'
        when coalesce(v_member.is_client_admin, false) = true then 'client_admin'
        else 'staff'
      end
    );

    return jsonb_build_object(
      'ok', true,
      'can_access', true,
      'tenant_id', v_member.tenant_id,
      'team_member_id', v_member.id,
      'branch_id', v_member.branch_id,
      'role_key', v_role_key,
      'access_level', coalesce(v_member.access_level, v_role_key),
      'is_owner', false,
      'is_client_admin', coalesce(v_member.is_client_admin, false),
      'is_branch_manager', coalesce(v_member.is_branch_manager, false),
      'account_type', 'staff',
      'permissions', v_permissions
    );
  end if;

  -- NEW: this login doesn't match an active staff row, but before
  -- treating it as "maybe an owner who never touched Team Access" (the
  -- generic guest fallback below), check whether it matches a DISABLED
  -- team_members row - i.e. this really was a staff account, and the
  -- reason the lookup above found nothing is specifically that it was
  -- disabled, not that it never existed.
  select tm.id
  into v_disabled_member_id
  from public.ungani_team_members tm
  where tm.tenant_id is not null
    and coalesce(tm.is_owner, false) = false
    and (
      tm.auth_user_id = v_user_id
      or lower(coalesce(tm.email, '')) = lower(coalesce(v_email, ''))
    )
  order by tm.created_at desc
  limit 1;

  if v_disabled_member_id is not null then
    return jsonb_build_object(
      'ok', false,
      'can_access', false,
      'role_key', 'guest',
      'is_owner', false,
      'account_type', 'disabled_staff',
      'disabled', true,
      'message', 'This staff account has been disabled by the business owner.'
    );
  end if;

  return jsonb_build_object(
    'ok', false,
    'can_access', false,
    'role_key', 'guest',
    'is_owner', false,
    'account_type', 'guest',
    'message', 'No approved owner or active staff workspace found for this login.'
  );
end;
$function$;

-- Verification - confirm the redefinition landed.
select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'get_my_ungani_staff_access';
