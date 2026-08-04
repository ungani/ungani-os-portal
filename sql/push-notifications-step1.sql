-- UNGANI OS: Browser Push Notifications - Step 1 (infrastructure only).
-- Run this once in the Supabase SQL editor.
--
-- This is infra ONLY - no event is wired to send a push yet. It adds:
--   1. A subscription registry table (one row per browser/device that has
--      granted push permission).
--   2. Two RPCs an authenticated user calls to save/remove their OWN
--      subscription (endpoint/p256dh/auth keys from PushManager.subscribe()).
--
-- No FK to auth.users/tenants deliberately - this is a new, self-contained
-- table with no existing callers to break, and skipping the auth.users FK
-- avoids any cross-schema grant surprises on a table that's brand new
-- tonight. Both RPCs are SECURITY DEFINER (bypass RLS safely, matching
-- every other RPC in this app) - RLS is enabled on the table with NO
-- policies for anon/authenticated, so the ONLY ways to touch this table
-- are: these two RPCs (scoped to auth.uid()'s own rows), or the service
-- role used server-side in /api/send-push.js (which bypasses RLS
-- entirely, same as /api/send-email-queue.js's use of the queue table).

create table if not exists public.ungani_push_subscriptions (
  id uuid primary key default gen_random_uuid(),
  auth_user_id uuid not null,
  tenant_id uuid null,
  user_type text not null default 'client',
  endpoint text not null,
  p256dh text not null,
  auth_key text not null,
  user_agent text null,
  created_at timestamptz not null default now(),
  last_seen_at timestamptz not null default now(),
  constraint ungani_push_subscriptions_endpoint_key unique (endpoint)
);

create index if not exists ungani_push_subscriptions_auth_user_id_idx
  on public.ungani_push_subscriptions (auth_user_id);

create index if not exists ungani_push_subscriptions_user_type_idx
  on public.ungani_push_subscriptions (user_type);

alter table public.ungani_push_subscriptions enable row level security;

-- ============================================================
-- save_ungani_push_subscription - called right after
-- PushManager.subscribe() succeeds in the browser. Upserts by endpoint
-- (the natural per-device dedupe key - a device's subscription endpoint
-- is unique per browser+origin), so re-subscribing the same device
-- updates the existing row (including correctly reassigning it if a
-- different user is now logged in on a shared device) rather than
-- creating duplicates.
-- ============================================================

create or replace function public.save_ungani_push_subscription(
  p_endpoint text,
  p_p256dh text,
  p_auth_key text,
  p_user_agent text default null
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_id uuid;
  v_is_admin boolean;
  v_access jsonb;
  v_user_type text;
  v_tenant_id uuid;
  v_clean_endpoint text;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    return jsonb_build_object('ok', false, 'message', 'Not authenticated.');
  end if;

  v_clean_endpoint := nullif(trim(coalesce(p_endpoint, '')), '');

  if v_clean_endpoint is null or p_p256dh is null or p_auth_key is null then
    return jsonb_build_object('ok', false, 'message', 'Missing subscription details.');
  end if;

  v_is_admin := coalesce(public.is_ungani_admin(), false);

  if v_is_admin then
    v_user_type := 'admin';
    v_tenant_id := null;
  else
    v_access := public.get_my_ungani_staff_access();
    v_user_type := 'client';
    v_tenant_id := nullif(v_access->>'tenant_id', '')::uuid;
  end if;

  insert into public.ungani_push_subscriptions (
    auth_user_id,
    tenant_id,
    user_type,
    endpoint,
    p256dh,
    auth_key,
    user_agent,
    created_at,
    last_seen_at
  ) values (
    v_user_id,
    v_tenant_id,
    v_user_type,
    v_clean_endpoint,
    p_p256dh,
    p_auth_key,
    nullif(trim(coalesce(p_user_agent, '')), ''),
    now(),
    now()
  )
  on conflict (endpoint) do update set
    auth_user_id = excluded.auth_user_id,
    tenant_id = excluded.tenant_id,
    user_type = excluded.user_type,
    p256dh = excluded.p256dh,
    auth_key = excluded.auth_key,
    user_agent = excluded.user_agent,
    last_seen_at = now();

  return jsonb_build_object('ok', true, 'message', 'Push subscription saved.');
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

grant execute on function public.save_ungani_push_subscription(text, text, text, text) to authenticated;

-- ============================================================
-- remove_ungani_push_subscription - called when the user turns off
-- push notifications from within the app, or when the browser's own
-- subscription is invalidated client-side. Only ever removes the
-- CALLER's own row (auth_user_id = auth.uid()) - cannot be used to
-- remove another user's subscription.
-- ============================================================

create or replace function public.remove_ungani_push_subscription(p_endpoint text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_id uuid;
  v_clean_endpoint text;
begin
  v_user_id := auth.uid();

  if v_user_id is null then
    return jsonb_build_object('ok', false, 'message', 'Not authenticated.');
  end if;

  v_clean_endpoint := nullif(trim(coalesce(p_endpoint, '')), '');

  if v_clean_endpoint is null then
    return jsonb_build_object('ok', false, 'message', 'Missing endpoint.');
  end if;

  delete from public.ungani_push_subscriptions
  where endpoint = v_clean_endpoint
    and auth_user_id = v_user_id;

  return jsonb_build_object('ok', true, 'message', 'Push subscription removed.');
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

grant execute on function public.remove_ungani_push_subscription(text) to authenticated;

-- ============================================================
-- Verification (read-only)
-- ============================================================

select
  p.proname,
  pg_get_function_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in ('save_ungani_push_subscription', 'remove_ungani_push_subscription')
order by p.proname;

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_push_subscriptions'
order by ordinal_position;
