-- Team Chat: read receipts (WhatsApp-style single/double tick).
--
-- DMs need no new table: team_chat_messages.is_read is already an
-- accurate per-message read flag for a DM, since a DM has exactly one
-- possible reader. Real bug avoided here: is_read is a SINGLE shared
-- column, not per-reader - for Team broadcast/channel messages (multiple
-- possible readers) it means "at least one member has read this", which
-- is fine for the existing unread-count/badge logic (a pre-existing,
-- unrelated limitation, left untouched) but cannot express "read by how
-- many members" for a real "Seen by N" receipt. This table exists ONLY
-- to answer that question for Team/channel messages - it does not
-- replace or duplicate is_read.
--
-- No row is ever written for a DM message here (client-side gates this),
-- and no row is written for your own sent message (no self-read
-- receipts).

create table if not exists public.team_chat_message_reads (
  message_id uuid not null references public.team_chat_messages(id) on delete cascade,
  reader_user_id uuid not null,
  tenant_id uuid not null,
  read_at timestamptz not null default now(),
  primary key (message_id, reader_user_id)
);

create index if not exists team_chat_message_reads_message_idx
  on public.team_chat_message_reads (message_id);

alter table public.team_chat_message_reads enable row level security;

-- Select: same visibility as the underlying message - reuses
-- can_access_ungani_chat_message() exactly as team_chat_messages' own
-- SELECT/UPDATE policies already do, rather than inventing a second
-- rule.
drop policy if exists team_chat_message_reads_select on public.team_chat_message_reads;
create policy team_chat_message_reads_select
  on public.team_chat_message_reads
  for select
  to authenticated
  using (
    public.is_ungani_admin()
    or exists (
      select 1 from public.team_chat_messages m
      where m.id = message_id
        and public.can_access_ungani_chat_message(m.tenant_id, m.sender_user_id, m.recipient_team_member_id, m.recipient_is_owner)
    )
  );

-- Insert: only your own read receipt, only for a Team broadcast or
-- channel message (recipient_team_member_id/recipient_is_owner both
-- null/false - a DM never qualifies), only for a message you can
-- actually see, and never for your own message.
drop policy if exists team_chat_message_reads_insert_own on public.team_chat_message_reads;
create policy team_chat_message_reads_insert_own
  on public.team_chat_message_reads
  for insert
  to authenticated
  with check (
    reader_user_id = auth.uid()
    and exists (
      select 1 from public.team_chat_messages m
      where m.id = message_id
        and m.tenant_id = tenant_id
        and m.recipient_team_member_id is null
        and m.recipient_is_owner = false
        and m.sender_user_id != auth.uid()
        and public.can_access_ungani_chat_message(m.tenant_id, m.sender_user_id, m.recipient_team_member_id, m.recipient_is_owner)
    )
  );

grant select, insert on public.team_chat_message_reads to authenticated;
