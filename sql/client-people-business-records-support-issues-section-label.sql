-- UNGANI OS: section_label on client_people, business_records,
-- support_issues (multi-section business-type support).
-- Run this once in the Supabase SQL editor - URGENT, live-blocking bug
-- on client_people (confirmed: "Add Person" fails with "Could not find
-- the 'section_label' column of 'client_people' in the schema cache").
--
-- Design notes:
--   - Same exact bug shape as sql/business-items-section-label.sql and
--     sql/documents-section-label.sql: my-people.html, my-records.html,
--     and my-support.html all already have full read/write/filter
--     support for section_label (the .eq("section_label", ...) filter,
--     the Section dropdown in each add/edit form, each save function's
--     payload) - code shipped ahead of its migration, on three tables at
--     once. tasks/transactions/business_events/business_items/documents
--     all already have this column (confirmed working); client_people/
--     business_records/support_issues were the ones left out.
--   - client_people is the confirmed, live-reported break (blocks adding
--     a person for any multi-section tenant). business_records and
--     support_issues were found via the same investigation - both write
--     section_label the identical way and have no migration either, so
--     they carry the identical risk even though not yet reported broken.
--     Fixed together now rather than waiting for each to surface
--     separately.
--   - All three: additive only, one new nullable text column each, no
--     existing column touched. Nullable because a tenant with only one
--     section selected (or a business type with no optional sections at
--     all) never sets this field - already-established, safe pattern.
--   - This is a schema-level fix, not a per-business-type one: all 19
--     business types share these same three tables. Once the column
--     exists, every tenant regardless of type can save a person/record/
--     support issue - a multi-section tenant (Real Estate, Hospitality,
--     Retail, etc.) will populate section_label from its Section
--     dropdown; a single/no-section tenant (School, Gym, Warehouse,
--     etc.) simply never sets it and the column stays null, which the
--     app's own code already treats as "no section filter applies."

alter table public.client_people
  add column if not exists section_label text;

create index if not exists client_people_section_label_idx
  on public.client_people (tenant_id, section_label);

alter table public.business_records
  add column if not exists section_label text;

create index if not exists business_records_section_label_idx
  on public.business_records (tenant_id, section_label);

alter table public.support_issues
  add column if not exists section_label text;

create index if not exists support_issues_section_label_idx
  on public.support_issues (tenant_id, section_label);
