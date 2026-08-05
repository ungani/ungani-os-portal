-- Ungani Connect - Phase 2: mount the Discussion + Timeline + Attachments
-- panel on Tasks (the first record type, per the confirmed rollout order).
--
-- Real sources pulled before writing this, not guessed:
--   - Phase 0 already built everything Discussion + Timeline need
--     (ungani_record_comments, ungani_record_activity,
--     can_access_ungani_record(), add_ungani_record_comment(),
--     log_ungani_record_activity()) - confirmed live, zero new tables or
--     functions required for those two tabs.
--   - Attachments: read my-items.html's ALREADY-SHIPPED "Documents"
--     panel section (commit 43ddbc0) - it links documents to an item via
--     a real documents.linked_item_id column + a "Link to Item / Asset"
--     dropdown in my-documents.html's own form (loadLinkableItems()).
--     This migration adds the exact same column for tasks
--     (documents.linked_task_id), so Attachments reuses that proven
--     pattern instead of inventing new file storage - Google Drive/file
--     upload already exists on the Documents page, nothing new needed
--     there either.
--   - documents' existing RLS already allows direct authenticated
--     .update()/.insert() from tenant members (confirmed via
--     my-documents.html's own working save flow) - no RLS changes
--     needed for this column.
--
-- This is the ONLY schema change Phase 2 needs. Everything else (the
-- Task discussion panel UI, the linking dropdown, wiring real task
-- events into the timeline) is client-side, in my-tasks.html and
-- my-documents.html.

alter table public.documents
  add column if not exists linked_task_id uuid references public.tasks(id);

create index if not exists idx_documents_linked_task_id
  on public.documents(linked_task_id)
  where linked_task_id is not null;

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public' and table_name = 'documents' and column_name = 'linked_task_id';

select indexname
from pg_indexes
where schemaname = 'public' and tablename = 'documents' and indexname = 'idx_documents_linked_task_id';
