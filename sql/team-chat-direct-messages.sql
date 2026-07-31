-- UNGANI OS: Team Chat direct messages (DMs) - real per-recipient privacy.
-- Run this whole file in order in the Supabase SQL editor.
--
-- Built entirely from literal, user-confirmed current state:
--   - pg_class: relrowsecurity = true, relforcerowsecurity = false
--   - pg_policy: all 7 existing policies (literal polqual/polwithcheck)
--   - information_schema.columns: real current column list
-- Nothing here is guessed.
--
-- ============================================================================
-- STEP 1: team_chat_messages - real recipient columns.
-- ============================================================================
--
-- Same shape as tonight's task-assignment work (assigned_to_team_member_id /
-- assigned_to_is_owner) - the owner isn't a ungani_team_members row, so a DM
-- recipient needs two columns, mutually exclusive. Both null/false means
-- "broadcast Team message" - matches every existing row, so this is a no-op
-- for current data.

alter table public.team_chat_messages
  add column if not exists recipient_team_member_id uuid references public.ungani_team_members(id),
  add column if not exists recipient_is_owner boolean not null default false;

alter table public.team_chat_messages
  drop constraint if exists team_chat_recipient_not_both_check;

alter table public.team_chat_messages
  add constraint team_chat_recipient_not_both_check
  check (not (recipient_is_owner = true and recipient_team_member_id is not null));

create index if not exists idx_team_chat_recipient_team_member_id
  on public.team_chat_messages(recipient_team_member_id);

create index if not exists idx_team_chat_recipient_is_owner
  on public.team_chat_messages(recipient_is_owner)
  where recipient_is_owner = true;

-- ============================================================================
-- STEP 2: visibility helper - single source of truth for "can this caller
-- see this row", reused by both the new SELECT and UPDATE policies.
-- ============================================================================
--
-- Deliberately reuses get_my_ungani_staff_access() (the app's existing single
-- source of truth for owner/staff identity, same one every other guard/RPC
-- tonight already relies on) rather than re-deriving tenant/owner/team-member
-- resolution a second time in raw SQL.

create or replace function public.can_access_ungani_chat_message(
  p_tenant_id uuid,
  p_sender_user_id uuid,
  p_recipient_team_member_id uuid,
  p_recipient_is_owner boolean
) returns boolean
language plpgsql
security definer
set search_path to 'public'
stable
as $function$
declare
  v_access jsonb;
  v_my_tenant_id uuid;
begin
  if public.is_ungani_admin() then
    return true;
  end if;

  v_access := public.get_my_ungani_staff_access();
  v_my_tenant_id := nullif(v_access->>'tenant_id', '')::uuid;

  if v_my_tenant_id is null or v_my_tenant_id != p_tenant_id then
    return false;
  end if;

  -- Broadcast (Team) message - visible to everyone in the tenant, same as
  -- every existing row's behavior today.
  if coalesce(p_recipient_is_owner, false) = false and p_recipient_team_member_id is null then
    return true;
  end if;

  -- The sender can always see their own message.
  if p_sender_user_id = auth.uid() then
    return true;
  end if;

  -- The resolved recipient can see it.
  if coalesce(p_recipient_is_owner, false) and coalesce((v_access->>'is_owner')::boolean, false) then
    return true;
  end if;

  if p_recipient_team_member_id is not null
     and nullif(v_access->>'team_member_id', '') is not null
     and p_recipient_team_member_id = (v_access->>'team_member_id')::uuid then
    return true;
  end if;

  return false;
end;
$function$;

-- ============================================================================
-- STEP 3: SELECT - drop both existing broad tenant-wide policies, replace
-- with one that's actually recipient-aware.
-- ============================================================================
--
-- team_chat_messages_select_own and team_chat_select_same_tenant_or_admin
-- both only ever checked tenant_id - since RLS OR's multiple permissive
-- policies together, leaving either one in place would silently let anyone
-- in the tenant read every DM regardless of any new policy added alongside
-- them. Both must go.

drop policy if exists team_chat_messages_select_own on public.team_chat_messages;
drop policy if exists team_chat_select_same_tenant_or_admin on public.team_chat_messages;

create policy team_chat_select_sender_recipient_or_broadcast
  on public.team_chat_messages
  for select
  using (
    public.can_access_ungani_chat_message(tenant_id, sender_user_id, recipient_team_member_id, recipient_is_owner)
  );

-- ============================================================================
-- STEP 4: INSERT - drop both existing policies, replace with one that also
-- closes the sender-spoofing gap found while reading the real policy text.
-- ============================================================================
--
-- team_chat_insert_same_tenant_or_admin checks the sender_id column - which
-- no app code has ever written (confirmed via full-repo grep; it's always
-- null). team_chat_messages_insert_own checks nothing about sender identity
-- at all. Combined, ANY authenticated tenant member can currently insert a
-- row with any sender_user_id they like - pre-existing, unrelated to DMs,
-- but worth closing while these policies are already being rewritten:
-- sender_user_id must now equal auth.uid().

drop policy if exists team_chat_insert_same_tenant_or_admin on public.team_chat_messages;
drop policy if exists team_chat_messages_insert_own on public.team_chat_messages;

create policy team_chat_insert_own_tenant_and_identity
  on public.team_chat_messages
  for insert
  with check (
    public.is_ungani_admin()
    or (
      tenant_id = public.get_my_ungani_tenant_id()
      and sender_user_id = auth.uid()
    )
  );

-- ============================================================================
-- STEP 5: UPDATE - drop both existing broad policies, replace with the same
-- visibility helper used for SELECT (used for is_read marking today; app
-- code never edits message content).
-- ============================================================================

drop policy if exists team_chat_messages_update_own on public.team_chat_messages;
drop policy if exists team_chat_update_same_tenant_or_admin on public.team_chat_messages;

create policy team_chat_update_sender_recipient_or_broadcast
  on public.team_chat_messages
  for update
  using (
    public.can_access_ungani_chat_message(tenant_id, sender_user_id, recipient_team_member_id, recipient_is_owner)
  )
  with check (
    public.can_access_ungani_chat_message(tenant_id, sender_user_id, recipient_team_member_id, recipient_is_owner)
  );

-- team_chat_delete_admin_only is unchanged - already admin-only, unrelated
-- to DM privacy.

-- ============================================================================
-- STEP 6: extend get_my_ungani_team_members_for_assignment() with each
-- member's auth_user_id + the owner's identity - additive only, existing
-- callers (the task-assignment picker) ignore the new fields.
-- ============================================================================
--
-- Chat conversation threading needs to merge "a message I sent to Mary" and
-- "Mary's reply to me" into the same thread - the first is keyed by
-- recipient_team_member_id, the second by sender_user_id (a raw auth uid).
-- Merging those two views requires knowing each teammate's auth_user_id
-- client-side, which the original response didn't include (it only needed
-- id/full_name/role_key for a picker dropdown). Exposing auth_user_id here
-- is a proportionate extension, not a new exposure: it's already visible
-- indirectly via sender_user_id on every message row, and this RPC is only
-- ever telling tenant peers about their own teammates.

create or replace function public.get_my_ungani_team_members_for_assignment()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_access jsonb;
  v_tenant_id uuid;
  v_owner record;
begin
  v_access := public.get_my_ungani_staff_access();

  if coalesce((v_access->>'can_access')::boolean, false) is not true then
    return jsonb_build_object('ok', false, 'members', '[]'::jsonb, 'message', 'No active account found for this login.');
  end if;

  v_tenant_id := nullif(v_access->>'tenant_id', '')::uuid;

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'members', '[]'::jsonb, 'message', 'No tenant found for this login.');
  end if;

  select r.auth_user_id, coalesce(nullif(trim(r.contact_person), ''), nullif(trim(r.contact_name), ''), 'Owner') as full_name
  into v_owner
  from public.registrations r
  where r.tenant_id = v_tenant_id
    and lower(coalesce(r.status, r.registration_status, 'pending')) in ('approved', 'active', 'trial')
  order by r.created_at desc
  limit 1;

  return jsonb_build_object(
    'ok', true,
    'owner',
    case
      when v_owner.auth_user_id is not null
        then jsonb_build_object('auth_user_id', v_owner.auth_user_id, 'full_name', v_owner.full_name)
      else null
    end,
    'members',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', tm.id,
            'full_name', tm.full_name,
            'role_key', tm.role_key,
            'auth_user_id', tm.auth_user_id
          )
          order by tm.full_name
        )
        from public.ungani_team_members tm
        where tm.tenant_id = v_tenant_id
          and coalesce(tm.is_active, true) = true
          and tm.deactivated_at is null
          and lower(coalesce(tm.status, 'active')) in ('active', 'accepted')
      ),
      '[]'::jsonb
    )
  );
end;
$function$;

-- ============================================================================
-- Verification - confirm everything landed as expected.
-- ============================================================================

select policyname, cmd, permissive, qual as using_expr, with_check as with_check_expr
from pg_policies
where schemaname = 'public' and tablename = 'team_chat_messages'
order by cmd, policyname;

select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'team_chat_messages'
  and column_name in ('recipient_team_member_id', 'recipient_is_owner');
