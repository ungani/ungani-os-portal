-- UNGANI OS: URGENT fix for "Could not find the 'sender_name' column of
-- 'admin_client_messages' in the schema cache" - blocking real admin-to-
-- client communication right now.
--
-- Root cause: admin_client_messages already exists (this is a missing-
-- COLUMN error, not a missing-table error) but code shipped ahead of a
-- migration - same bug class as tonight's other missing-column issues.
-- The table is written to by TWO different code paths with different
-- column sets that were never reconciled into one real migration:
--   - admin-chat.html's sendAdminMessage(): tenant_id, sender_id,
--     sender_name, sender_role, message_body, is_internal,
--     read_by_admin_at, created_at
--   - my-chat.html's sendMessage() (client side): tenant_id,
--     sender_user_id, sender_role, message_type, message_body, message,
--     body, attachment_url, is_read, created_at, updated_at
--   - admin-shared.js / admin-home.html's unread-badge counts also read
--     sender_role + read_by_admin_at
--
-- Every ADD COLUMN below is IF NOT EXISTS - safe to run regardless of
-- what the table's current real columns are; anything already present is
-- a no-op, anything missing gets added. No drops, no renames, no data
-- loss risk.

alter table public.admin_client_messages
  add column if not exists tenant_id uuid,
  add column if not exists sender_id uuid,
  add column if not exists sender_user_id uuid,
  add column if not exists sender_name text,
  add column if not exists sender_role text,
  add column if not exists message_type text,
  add column if not exists message_body text,
  add column if not exists message text,
  add column if not exists body text,
  add column if not exists attachment_url text,
  add column if not exists is_internal boolean not null default false,
  add column if not exists is_read boolean not null default false,
  add column if not exists read_by_admin_at timestamptz,
  add column if not exists created_at timestamptz not null default now(),
  add column if not exists updated_at timestamptz not null default now();

-- ============================================================================
-- VERIFICATION - paste back the literal output. Confirms every column the
-- app code needs now actually exists, with the right type.
-- ============================================================================
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'admin_client_messages'
order by ordinal_position;
