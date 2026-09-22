-- UNGANI OS: tasks.linked_item_id (Location/Property 360 view - Level 3
-- of the Person/Company/Location connected-records work). Run this once
-- in the Supabase SQL editor.
--
-- Design notes:
--   - Additive only: one new nullable uuid column with a real foreign
--     key to business_items(id). Exact same pattern as
--     documents-linked-item-id.sql (already run/live) - no existing
--     column is touched.
--   - Why this closes the "watchman/electrician/maintenance" gap without
--     any new subsystem: tasks already support assignment to a specific
--     staff member (Task assignment feature, shipped earlier this
--     session). Tagging a task to a business_items row via this column
--     turns "electrician visiting Nyali Apartment" or "watchman shift
--     note" into a real, queryable record - a task assigned to a person
--     AND linked to a property - with zero new schema for roles.
--   - on delete set null: if the linked item is ever deleted, the task
--     itself is NOT deleted - it just becomes unlinked, matching every
--     other linked_item_id column in this app.
--   - No RLS changes needed: tasks' existing tenant-scoped RLS policies
--     already govern every column on the row, including this new one.

alter table public.tasks
  add column if not exists linked_item_id uuid references public.business_items(id) on delete set null;

create index if not exists tasks_linked_item_id_idx
  on public.tasks (linked_item_id);
