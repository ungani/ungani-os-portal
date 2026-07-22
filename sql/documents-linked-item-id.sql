-- UNGANI OS: documents.linked_item_id (Phase 4 - Asset Management module,
-- Documents per asset). Run this once in the Supabase SQL editor.
--
-- Design notes:
--   - Additive only: one new nullable uuid column with a real foreign
--     key to business_items(id). No existing column is touched - the
--     existing free-text `related_item` field (a human-typed
--     description, e.g. "Delivery Van" or "Website Redesign") is
--     untouched and still available for describing things that AREN'T
--     a literal business_items row (a project, a person, a one-off
--     job). This new column is a real, structured link alongside it,
--     not a replacement.
--   - on delete set null: if the linked item is ever deleted, the
--     document itself is NOT deleted - it just becomes unlinked,
--     matching how the rest of this app treats orphaned references
--     (e.g. my-item-profile.html shows "not found" gracefully rather
--     than assuming a link is always valid).
--   - No RLS changes needed: documents' existing tenant-scoped RLS
--     policies already govern every column on the row, including this
--     new one.
--   - Assumes business_items.id is uuid, matching every other table's
--     primary key type in this app. If that assumption is wrong the
--     ALTER fails loudly with a clear type-mismatch error rather than
--     silently doing the wrong thing.

alter table public.documents
  add column if not exists linked_item_id uuid references public.business_items(id) on delete set null;

create index if not exists documents_linked_item_id_idx
  on public.documents (linked_item_id);
