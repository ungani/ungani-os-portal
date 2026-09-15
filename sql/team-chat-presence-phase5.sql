-- Team Chat redesign Phase 5 (see memory team_chat_redesign_and_duplicate_
-- detection.md): presence had zero infra anywhere in the codebase before
-- this - confirmed via full-repo grep. Lightweight heartbeat chosen over
-- introducing Supabase Realtime Presence fresh, consistent with this
-- app's existing polling-based patterns (Team Chat's own message polling
-- already ticks every 12s).
--
-- One row per real person (auth_user_id), not per tenant/team-member row -
-- an owner has no ungani_team_members row of their own, so a dedicated
-- table keyed by auth_user_id is the only clean way to cover both owner
-- and staff with one mechanism. RLS allows reading any row for your own
-- tenant (so a staff member's online dot is visible to the owner and vice
-- versa); writes only ever go through ping_my_ungani_presence() (security
-- definer, always writes the CALLER's own row) - no direct insert/update
-- policy exists, so a client can't spoof another user's presence.

create table if not exists public.ungani_user_presence (
  auth_user_id uuid primary key references auth.users(id) on delete cascade,
  tenant_id uuid not null references public.tenants(id) on delete cascade,
  last_seen_at timestamptz not null default now()
);

create index if not exists idx_ungani_user_presence_tenant on public.ungani_user_presence(tenant_id);

alter table public.ungani_user_presence enable row level security;

drop policy if exists "tenant members can read their tenant's presence" on public.ungani_user_presence;
create policy "tenant members can read their tenant's presence"
  on public.ungani_user_presence for select
  using (tenant_id = public.get_my_ungani_tenant_id());

-- Heartbeat - called every ~45s while any page with team-chat-shared.js
-- loaded is open (see nia-assistant.js-style fire-and-forget pattern in
-- team-chat-shared.js's own pingPresence()). Upserts the caller's own row
-- only; auth.uid() is server-derived, not client-supplied, so this can't
-- be used to write anyone else's presence.
create or replace function public.ping_my_ungani_presence()
returns void
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return;
  end if;

  insert into public.ungani_user_presence (auth_user_id, tenant_id, last_seen_at)
  values (auth.uid(), v_tenant_id, now())
  on conflict (auth_user_id) do update
    set last_seen_at = excluded.last_seen_at,
        tenant_id = excluded.tenant_id;
end;
$function$;

grant execute on function public.ping_my_ungani_presence() to authenticated;

-- Read - returns every presence row for the caller's own tenant in one
-- call, so team-chat-shared.js can compute online/away/offline for the
-- whole roster (owner + every staff member) without one query per person.
create or replace function public.get_my_ungani_team_presence()
returns table (auth_user_id uuid, last_seen_at timestamptz)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_tenant_id uuid;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return;
  end if;

  return query
  select p.auth_user_id, p.last_seen_at
  from public.ungani_user_presence p
  where p.tenant_id = v_tenant_id;
end;
$function$;

grant execute on function public.get_my_ungani_team_presence() to authenticated;
