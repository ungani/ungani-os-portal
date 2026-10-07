-- New RPC: owner_enable_ungani_team_member(p_team_member_id)
--
-- Counterpart to owner_disable_ungani_team_member. The Team page's
-- "Disable Staff" button never relabels to "Enable Staff" for an already-
-- disabled member - re-enabling currently only works by re-submitting the
-- top Add/Update Staff form with the same email, which upserts by email
-- via owner_upsert_ungani_team_member. That path works (confirmed live:
-- is_active/deactivated_at correctly reset, per the fix already live from
-- sql/fix-team-member-reenable-bug.sql) but it's not discoverable, and it
-- resets role_key to whatever the form currently has selected even though
-- the member's permissions/role should just be restored as-is.
--
-- This RPC does the minimal thing: flip status back to active without
-- touching role_key, permissions, branch_id, salary, or anything else -
-- exactly mirroring how owner_disable_ungani_team_member only flips
-- status/is_active/deactivated_at. Ownership check copied verbatim from
-- the pattern in owner_upsert_ungani_team_member (get_my_ungani_tenant_id
-- + is_my_ungani_tenant_owner), both confirmed live this session.

create or replace function public.owner_enable_ungani_team_member(
  p_team_member_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
  v_member_id uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;
  if public.is_my_ungani_tenant_owner(v_tenant_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'Only the business owner can manage staff access.');
  end if;

  update public.ungani_team_members
  set
    status = 'active',
    is_active = true,
    deactivated_at = null,
    updated_at = now()
  where id = p_team_member_id
    and tenant_id = v_tenant_id
  returning id into v_member_id;

  if v_member_id is null then
    return jsonb_build_object('ok', false, 'message', 'Staff member not found.');
  end if;

  perform public.log_ungani_activity(
    'staff_enabled',
    'settings',
    'ungani_team_members',
    v_member_id,
    'Re-enabled staff member.',
    jsonb_build_object()
  );

  return jsonb_build_object('ok', true, 'id', v_member_id, 'team_member_id', v_member_id);
end;
$function$;

grant execute on function public.owner_enable_ungani_team_member(uuid) to authenticated;

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================
select proname, pg_get_function_identity_arguments(oid) as args
from pg_proc
where proname = 'owner_enable_ungani_team_member'
  and pronamespace = 'public'::regnamespace;
