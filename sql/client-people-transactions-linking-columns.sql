-- UNGANI OS: client_people.linked_item_id + transactions.related_person_id
-- (tenant-unit-lease linking work). Run this ONLY after confirming via
-- sql/check-transactions-client-people-types.sql that these columns are
-- genuinely missing - do not run blind.
--
-- Why this file exists now: the app code (my-people.html's linkedItemId
-- field, my-money.html's moneyRelatedPerson picker) already reads and
-- writes both columns, and a migration for the sibling column
-- documents.linked_item_id exists (sql/documents-linked-item-id.sql,
-- committed in fe231aa) - but no equivalent file or commit exists for
-- these two, in the sql/ directory or git history. That gap is the exact
-- shape of the business_items.section_label bug from earlier this
-- session: code shipped ahead of its migration. Confirm before running.
--
-- Design notes (mirrors documents-linked-item-id.sql exactly):
--   - Additive only, nullable uuid, real foreign key.
--   - client_people.linked_item_id -> business_items(id): the unit,
--     room, or item a person (tenant, guest, occupant) is linked to.
--     The existing free-text fields on this table are untouched.
--   - transactions.related_person_id -> client_people(id): the person a
--     transaction relates to (e.g. which tenant paid rent). The existing
--     free-text `related_person` field (written by Quick Add) is
--     untouched and still available for cases with no structured link.
--   - on delete set null: if the linked item/person is ever deleted, the
--     referencing row is NOT deleted, just unlinked - matching the same
--     orphaned-reference handling as documents.linked_item_id.

alter table public.client_people
  add column if not exists linked_item_id uuid references public.business_items(id) on delete set null;

create index if not exists client_people_linked_item_id_idx
  on public.client_people (linked_item_id);

alter table public.transactions
  add column if not exists related_person_id uuid references public.client_people(id) on delete set null;

create index if not exists transactions_related_person_id_idx
  on public.transactions (related_person_id);
