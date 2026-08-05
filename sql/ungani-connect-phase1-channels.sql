-- Ungani Connect - Phase 1: hub foundation - owner-defined Department
-- Channels, layered onto the EXISTING team_chat_messages engine (no new
-- message table - same real-time/read-tracking/RLS-tested pipe that
-- already powers the "Team" broadcast tab and DMs).
--
-- Real sources pulled before writing this, not guessed:
--   - sql/team-chat-direct-messages.sql: team_chat_messages' real columns
--     (id, tenant_id, sender_user_id, sender_name, sender_role,
--     message_type, message_body, message, body, is_read, created_at,
--     updated_at, recipient_team_member_id, recipient_is_owner) and its
--     existing can_access_ungani_chat_message()/INSERT policy - reused
--     as-is, not duplicated (see the note in Step 3 on why the visibility
--     function needs no changes at all).
--   - team-chat-shared.js: confirmed "Team" (the default/general
--     broadcast) is already every row where recipient_team_member_id is
--     null and recipient_is_owner is false - so Department Channels are
--     ADDITIVE (a new channel_id column). Zero migration needed for
--     existing rows; "Team" keeps working exactly as it does today.
--   - get_my_ungani_staff_access()'s real is_owner/tenant_id/can_access
--     shape, already relied on throughout this session and in Phase 0.
--   - public.users' real columns (id = auth.uid(), full_name, email) -
--     same confirmed pattern as Phase 0, reused for the channel
--     creator's display name.
--
-- Design decision (channel visibility): Phase 1 channels are visible to
-- every active member of the tenant, same as the existing "Team" tab -
-- no separate per-channel membership table. This matches the same
-- "don't build a second permission system" principle the user already
-- confirmed for record comments in Phase 0. Per-channel membership can
-- be added later as a real, scoped decision if a genuine need for
-- private/restricted channels shows up - not invented speculatively now.
--
-- Explicitly OUT of this file (deferred, matches the Phase 1 task scope
-- - "hub page + owner-defined department channels" only):
--   - Company Announcements (owner-only-post channels) - a real
--     permission-asymmetry decision, not part of this pass.
--   - Shared Files, Search - later phases (6, 7).
--   - Mentions / Smart Notifications on channel messages - Phase 4.

-- ============================================================
-- STEP 1: ungani_chat_channels - owner-defined, tenant-wide.
-- ============================================================

create table if not exists public.ungani_chat_channels (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  name text not null,
  description text,
  created_by_user_id uuid,
  created_by_name text,
  is_archived boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

comment on table public.ungani_chat_channels is 'Ungani Connect Phase 1: owner-defined Department Channels. Visible tenant-wide to every active team member (no per-channel membership) - same visibility model as the existing "Team" broadcast tab.';

create unique index if not exists ungani_chat_channels_unique_active_name
  on public.ungani_chat_channels (tenant_id, lower(name))
  where is_archived = false;

create index if not exists ungani_chat_channels_tenant_idx
  on public.ungani_chat_channels (tenant_id, is_archived, created_at);

alter table public.ungani_chat_channels enable row level security;

drop policy if exists "Tenant members can read their channels" on public.ungani_chat_channels;
create policy "Tenant members can read their channels"
  on public.ungani_chat_channels
  for select
  to authenticated
  using (
    public.is_ungani_admin()
    or tenant_id = public.get_my_ungani_tenant_id()
  );

-- No INSERT/UPDATE/DELETE policy for authenticated - channel management
-- goes exclusively through the owner-only RPCs below, same "narrow
-- wrapper only" pattern as Phase 0 and create_ungani_notification.
grant select on public.ungani_chat_channels to authenticated;

-- ============================================================
-- STEP 2: extend team_chat_messages with channel_id. Existing rows are
-- entirely unaffected (channel_id defaults to null = the existing
-- Team/DM behavior, unchanged).
-- ============================================================

alter table public.team_chat_messages
  add column if not exists channel_id uuid references public.ungani_chat_channels(id);

create index if not exists idx_team_chat_channel_id
  on public.team_chat_messages(channel_id)
  where channel_id is not null;

-- ============================================================
-- STEP 3: SELECT/UPDATE policies need NO changes. A channel message
-- always has recipient_team_member_id = null and recipient_is_owner =
-- false (it's never a DM), so the EXISTING broadcast branch inside
-- can_access_ungani_chat_message() ("recipient_is_owner = false and
-- recipient_team_member_id is null -> visible to everyone in the
-- tenant") already covers channel messages correctly under Phase 1's
-- "tenant-wide" visibility decision above - reused verbatim, not
-- reopened. Only the INSERT policy needs a real change: validate that a
-- posted channel_id actually belongs to the caller's own tenant and
-- isn't archived (defense-in-depth against a forged/foreign channel_id,
-- same resolve-from-source-table pattern used everywhere else this
-- session; also a free win - it naturally blocks posting into an
-- archived channel).
-- ============================================================

drop policy if exists team_chat_insert_own_tenant_and_identity on public.team_chat_messages;

create policy team_chat_insert_own_tenant_and_identity
  on public.team_chat_messages
  for insert
  with check (
    public.is_ungani_admin()
    or (
      tenant_id = public.get_my_ungani_tenant_id()
      and sender_user_id = auth.uid()
      and (
        channel_id is null
        or exists (
          select 1 from public.ungani_chat_channels c
          where c.id = channel_id
            and c.tenant_id = tenant_id
            and c.is_archived = false
        )
      )
    )
  );

-- ============================================================
-- STEP 4: owner-only channel management RPCs.
-- ============================================================

create or replace function public.owner_upsert_ungani_chat_channel(
  p_channel_id uuid default null,
  p_name text default null,
  p_description text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_access jsonb;
  v_tenant_id uuid;
  v_name text;
  v_creator_name text;
  v_channel_id uuid;
begin
  v_access := public.get_my_ungani_staff_access();

  if coalesce((v_access->>'is_owner')::boolean, false) is not true then
    return jsonb_build_object('ok', false, 'message', 'Only the business owner can manage Department Channels.');
  end if;

  v_tenant_id := nullif(v_access->>'tenant_id', '')::uuid;
  v_name := nullif(trim(coalesce(p_name, '')), '');

  if v_name is null then
    return jsonb_build_object('ok', false, 'message', 'Channel name is required.');
  end if;

  if exists (
    select 1 from public.ungani_chat_channels
    where tenant_id = v_tenant_id
      and lower(name) = lower(v_name)
      and is_archived = false
      and (p_channel_id is null or id != p_channel_id)
  ) then
    return jsonb_build_object('ok', false, 'message', 'A channel with this name already exists.');
  end if;

  select coalesce(nullif(trim(full_name), ''), split_part(email, '@', 1))
  into v_creator_name
  from public.users
  where id = auth.uid();

  if p_channel_id is not null then
    update public.ungani_chat_channels
    set name = v_name,
        description = nullif(trim(coalesce(p_description, '')), ''),
        updated_at = now()
    where id = p_channel_id and tenant_id = v_tenant_id
    returning id into v_channel_id;

    if v_channel_id is null then
      return jsonb_build_object('ok', false, 'message', 'Channel not found.');
    end if;
  else
    insert into public.ungani_chat_channels (
      tenant_id, name, description, created_by_user_id, created_by_name
    ) values (
      v_tenant_id, v_name, nullif(trim(coalesce(p_description, '')), ''), auth.uid(), coalesce(v_creator_name, 'Owner')
    )
    returning id into v_channel_id;
  end if;

  return jsonb_build_object('ok', true, 'channel_id', v_channel_id);
end;
$function$;

grant execute on function public.owner_upsert_ungani_chat_channel(uuid, text, text) to authenticated;

create or replace function public.owner_archive_ungani_chat_channel(p_channel_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_access jsonb;
  v_tenant_id uuid;
  v_updated_id uuid;
begin
  v_access := public.get_my_ungani_staff_access();

  if coalesce((v_access->>'is_owner')::boolean, false) is not true then
    return jsonb_build_object('ok', false, 'message', 'Only the business owner can archive Department Channels.');
  end if;

  v_tenant_id := nullif(v_access->>'tenant_id', '')::uuid;

  update public.ungani_chat_channels
  set is_archived = true, updated_at = now()
  where id = p_channel_id and tenant_id = v_tenant_id
  returning id into v_updated_id;

  if v_updated_id is null then
    return jsonb_build_object('ok', false, 'message', 'Channel not found.');
  end if;

  return jsonb_build_object('ok', true);
end;
$function$;

grant execute on function public.owner_archive_ungani_chat_channel(uuid) to authenticated;

create or replace function public.get_my_ungani_chat_channels()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_access jsonb;
  v_tenant_id uuid;
begin
  v_access := public.get_my_ungani_staff_access();

  if coalesce((v_access->>'can_access')::boolean, false) is not true then
    return jsonb_build_object('ok', false, 'channels', '[]'::jsonb, 'message', 'No active account found for this login.');
  end if;

  v_tenant_id := nullif(v_access->>'tenant_id', '')::uuid;

  return jsonb_build_object(
    'ok', true,
    'channels', coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', c.id,
            'name', c.name,
            'description', c.description,
            'created_by_name', c.created_by_name,
            'created_at', c.created_at
          )
          order by c.name
        )
        from public.ungani_chat_channels c
        where c.tenant_id = v_tenant_id and c.is_archived = false
      ),
      '[]'::jsonb
    ),
    'is_owner', coalesce((v_access->>'is_owner')::boolean, false)
  );
end;
$function$;

grant execute on function public.get_my_ungani_chat_channels() to authenticated;

-- ============================================================
-- VERIFICATION - run all of these and paste back the output.
-- ============================================================

-- 1. Table exists, RLS enabled.
select relname, relrowsecurity
from pg_class
where relname = 'ungani_chat_channels' and relnamespace = 'public'::regnamespace;

-- 2. Real column list.
select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_chat_channels'
order by ordinal_position;

-- 3. channel_id landed on team_chat_messages.
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'team_chat_messages' and column_name = 'channel_id';

-- 4. Policies: exactly 1 select policy on ungani_chat_channels, no
-- write policies for authenticated; team_chat_messages' insert policy
-- now references channel_id.
select tablename, policyname, cmd, qual as using_expr, with_check as with_check_expr
from pg_policies
where schemaname = 'public'
  and tablename in ('ungani_chat_channels', 'team_chat_messages')
order by tablename, cmd, policyname;

-- 5. All 3 new functions exist.
select p.proname, pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('owner_upsert_ungani_chat_channel', 'owner_archive_ungani_chat_channel', 'get_my_ungani_chat_channels')
order by p.proname;

-- 6. Grants: authenticated has SELECT only on the new table, EXECUTE on
-- all 3 new functions.
select table_name, privilege_type
from information_schema.role_table_grants
where table_schema = 'public' and table_name = 'ungani_chat_channels' and grantee = 'authenticated';

select routine_name, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name in ('owner_upsert_ungani_chat_channel', 'owner_archive_ungani_chat_channel', 'get_my_ungani_chat_channels')
  and grantee = 'authenticated';

-- ============================================================
-- OPTIONAL real-data sanity check, as the OWNER of a real tenant:
-- ============================================================

-- select public.owner_upsert_ungani_chat_channel(null, 'Operations', 'Phase 1 test channel - safe to archive/rename.');
-- select public.get_my_ungani_chat_channels();
