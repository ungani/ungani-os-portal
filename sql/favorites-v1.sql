-- Favorites/Saved Items v1
-- One row per (user, record) - toggled directly by the client (insert to
-- favorite, delete to unfavorite), no RPC layer needed since this is a
-- personal action with no cross-user visibility concern (unlike
-- ungani_record_comments, which routes all writes through a RPC because
-- comments ARE visible to other users on the same tenant).
--
-- RLS idiom modeled on team_chat_message_reads (direct client insert/
-- delete scoped to auth.uid()) rather than ungani_record_comments (RPC-
-- gated writes) - confirmed the right precedent since favorites, like
-- read-receipts, are a private per-user flag, not shared content.
--
-- can_access_ungani_record(record_table, record_id) already exists
-- (Phase 0 foundation, sql/ungani-connect-phase0-foundation.sql) and
-- already knows the same 7 real table names - reused directly on INSERT
-- so a user can only favorite a record they can actually see, rather
-- than re-deriving per-table permission rules here.

create table if not exists public.ungani_favorites (
  id uuid primary key default gen_random_uuid(),
  tenant_id uuid not null references public.tenants(id),
  user_id uuid not null,
  record_table text not null check (record_table in (
    'tasks', 'transactions', 'documents', 'client_people',
    'business_items', 'business_records'
  )),
  record_id uuid not null,
  created_at timestamptz not null default now(),
  unique (user_id, record_table, record_id)
);

alter table public.ungani_favorites enable row level security;

drop policy if exists ungani_favorites_select on public.ungani_favorites;
create policy ungani_favorites_select
  on public.ungani_favorites for select to authenticated
  using (public.is_ungani_admin() or user_id = auth.uid());

drop policy if exists ungani_favorites_insert on public.ungani_favorites;
create policy ungani_favorites_insert
  on public.ungani_favorites for insert to authenticated
  with check (
    user_id = auth.uid()
    and public.can_access_ungani_record(record_table, record_id)
  );

drop policy if exists ungani_favorites_delete on public.ungani_favorites;
create policy ungani_favorites_delete
  on public.ungani_favorites for delete to authenticated
  using (user_id = auth.uid());

grant select, insert, delete on public.ungani_favorites to authenticated;

create index if not exists idx_ungani_favorites_user on public.ungani_favorites (user_id);
create index if not exists idx_ungani_favorites_tenant on public.ungani_favorites (tenant_id);
