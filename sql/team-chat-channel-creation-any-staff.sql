-- Team Chat: loosen channel creation from owner-only to any active staff
-- member (matches the WhatsApp-simplicity direction - starting a channel
-- is low-risk, no need to gate it behind the owner). Archiving a channel
-- stays owner-only (owner_archive_ungani_chat_channel, untouched here) -
-- removal is a more consequential action than creation.
--
-- Renamed owner_upsert_ungani_chat_channel -> upsert_ungani_chat_channel
-- to accurately reflect it's no longer owner-gated - every other
-- "owner_"-prefixed RPC in this app really does mean owner-only, so
-- keeping the old name here would be misleading. The old function is
-- dropped; team-chat-shared.js's createChannel() has already been
-- updated to call the new name in the same deploy as this migration.
--
-- Gate changed from is_owner to can_access (get_my_ungani_staff_access()'s
-- existing "is this login an active member of this tenant at all" flag) -
-- the same gate get_my_ungani_chat_channels() already uses to decide who
-- can even see the channel list, so this makes create/read consistent.

drop function if exists public.owner_upsert_ungani_chat_channel(uuid, text, text);

create or replace function public.upsert_ungani_chat_channel(
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

  if coalesce((v_access->>'can_access')::boolean, false) is not true then
    return jsonb_build_object('ok', false, 'message', 'No active account found for this login.');
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
      v_tenant_id, v_name, nullif(trim(coalesce(p_description, '')), ''), auth.uid(), coalesce(v_creator_name, 'Team Member')
    )
    returning id into v_channel_id;
  end if;

  return jsonb_build_object('ok', true, 'channel_id', v_channel_id);
end;
$function$;

grant execute on function public.upsert_ungani_chat_channel(uuid, text, text) to authenticated;
