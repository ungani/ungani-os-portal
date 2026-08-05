-- Ungani Connect - Phase 3: roll the Discussion + Timeline + Attachments
-- panel out to the remaining 4 record types (Payments/transactions,
-- Documents, Customers-People/client_people, Employees/
-- ungani_team_members), using the proven Phase 2 pattern built for Tasks.
--
-- Real sources pulled before writing this, not guessed:
--   - Discussion + Timeline need ZERO new schema - Phase 0's
--     ungani_record_comments/ungani_record_activity/
--     can_access_ungani_record()/add_ungani_record_comment()/
--     log_ungani_record_activity() already dispatch on all 7 tables
--     this session ever named, including transactions, documents,
--     client_people, and ungani_team_members - confirmed by re-reading
--     can_access_ungani_record()'s live CASE statement (Phase 0).
--   - Attachments: same linked_<type>_id pattern as Phase 2's
--     documents.linked_task_id (itself modeled on the already-shipped
--     documents.linked_item_id). Confirmed via real grep of every
--     existing linked_/related_ column in this codebase before adding
--     new ones - transactions.related_person_id and
--     client_people.linked_item_id already exist (from earlier
--     Property Management linking work) but nothing currently lets a
--     DOCUMENT be linked to a transaction, a person, or a team member -
--     these 3 columns are the real, missing gap.
--   - Documents (the record type itself) gets NO Attachments tab - a
--     document attaching other documents to itself doesn't match any
--     existing pattern in this app and wasn't asked for; its panel is
--     Discussion + Timeline only. Not an oversight - a deliberate scope
--     decision made during investigation.
--   - Employees (ungani_team_members): confirmed again via Phase 0's
--     own finding, still true - no staff-facing permission section
--     exists for this table, so can_access_ungani_record() already
--     denies non-owners here. The client-side panel is ALSO hidden from
--     non-owners as good UX (belt-and-suspenders, not a security
--     control - RLS is the real control).

alter table public.documents
  add column if not exists linked_transaction_id uuid references public.transactions(id);

alter table public.documents
  add column if not exists linked_person_id uuid references public.client_people(id);

alter table public.documents
  add column if not exists linked_team_member_id uuid references public.ungani_team_members(id);

create index if not exists idx_documents_linked_transaction_id
  on public.documents(linked_transaction_id)
  where linked_transaction_id is not null;

create index if not exists idx_documents_linked_person_id
  on public.documents(linked_person_id)
  where linked_person_id is not null;

create index if not exists idx_documents_linked_team_member_id
  on public.documents(linked_team_member_id)
  where linked_team_member_id is not null;

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================

select column_name, data_type, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name = 'documents'
  and column_name in ('linked_transaction_id', 'linked_person_id', 'linked_team_member_id')
order by column_name;

select indexname
from pg_indexes
where schemaname = 'public'
  and tablename = 'documents'
  and indexname in ('idx_documents_linked_transaction_id', 'idx_documents_linked_person_id', 'idx_documents_linked_team_member_id')
order by indexname;
