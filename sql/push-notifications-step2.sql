-- UNGANI OS: Browser Push Notifications - Step 2/3 (event-triggered push).
-- Run this once in the Supabase SQL editor.
--
-- Adds ungani_push_sent_log, a generic per-event dedup guard used by the
-- new api/send-event-push.js (Node, service-role only). No RPCs needed
-- here - push sending only ever happens server-side via the web-push
-- library, never from Postgres, so this table is read/written exclusively
-- by the service role.
--
-- Explicit service_role grant included this time (see the diagnostic +
-- fix given earlier tonight for ungani_push_subscriptions - RLS-enabled-
-- with-no-policies does NOT imply any role has table access; that's a
-- separate GRANT-layer permission that has to be added on purpose).

create table if not exists public.ungani_push_sent_log (
  id uuid primary key default gen_random_uuid(),
  event_type text not null,
  related_id uuid not null,
  recipient_scope text not null default 'broadcast',
  created_at timestamptz not null default now(),
  constraint ungani_push_sent_log_unique unique (event_type, related_id, recipient_scope)
);

create index if not exists ungani_push_sent_log_event_related_idx
  on public.ungani_push_sent_log (event_type, related_id);

alter table public.ungani_push_sent_log enable row level security;

grant select, insert, update, delete on table public.ungani_push_sent_log to service_role;

-- ============================================================
-- Fix for the live bug hit tonight - service_role was never explicitly
-- granted base table access on ungani_push_subscriptions (Step 1's
-- migration only added it for the two RPCs, which are SECURITY DEFINER
-- and owned by a role that already had implicit access; api/send-push.js
-- reads/deletes this table directly as service_role, which needs its own
-- grant). Safe to run again if already applied.
-- ============================================================

grant select, insert, update, delete on table public.ungani_push_subscriptions to service_role;

-- ============================================================
-- Verification (read-only)
-- ============================================================

select grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('ungani_push_subscriptions', 'ungani_push_sent_log')
order by table_name, grantee, privilege_type;
