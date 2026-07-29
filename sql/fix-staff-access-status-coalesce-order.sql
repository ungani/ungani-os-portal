-- Fixes a confirmed data-correctness bug in get_my_ungani_staff_access(),
-- the app's single source of truth for owner detection (used by
-- client.html, staff-permission-guard.js, staff-visibility-filter.js,
-- my-security.html's 2FA gate, and now my-support-access.html /
-- sql/ungani-support-access.sql's RLS policies).
--
-- Root cause: public.registrations has two status-like columns.
-- `status` is the ONLY one any tracked application code path ever
-- writes to (index.html's signup insert, and whatever the approve_
-- ungani_registration RPC updates on approval - confirmed live: Billy
-- Logistics' owner has status = 'approved'). `registration_status` is a
-- dead column - grepped every .html/.js/.sql file in the repo, nothing
-- writes to it. Its stale value (often 'pending') was being preferred
-- by `coalesce(registration_status, status, 'pending')`, silently
-- misclassifying real approved owners as having no valid registration.
--
-- Fix: swap the coalesce order to prefer the actively-maintained
-- column. This is the ONLY change from the original definition -
-- everything else below is identical to what's currently live.
--
-- This function is SECURITY DEFINER and used app-wide - after running
-- this, re-check owner-dependent behavior beyond just Support Access
-- (sidebar visibility, page gating, 2FA owner gate) if you want extra
-- confidence, though those all already have a defensive fallback for
-- exactly this failure mode (see sql/fix-support-access-owner-check-v2.sql
-- for why Support Access didn't have that same protection).

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
