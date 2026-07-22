-- UNGANI OS: documents.section_label (multi-section business-type support)
-- Run this once in the Supabase SQL editor.
--
-- Design notes:
--   - Genuinely missing column, not a code bug. my-documents.html already
--     has full read/write/filter support for section_label
--     (applyDocumentCommonFilters()'s .eq("section_label", ...), the
--     "Section" dropdown in the add/edit form, saveDocument()'s payload) -
--     the exact same shape as tasks/transactions/business_events, which
--     all have this column already and work today. There is no sql/
--     migration file for section_label on ANY table, meaning it was added
--     to those tables via an untracked, manual change that predates this
--     repo's sql/ migration-tracking convention - documents was evidently
--     left out of that original batch.
--   - Additive only: one new nullable text column. No existing column
--     touched.
--   - Nullable: tenants with only one section selected (or a business
--     type with no optional sections at all) never set this field - the
--     app's own code already treats an empty/missing value as "no
--     section filter applies" (sectionOptions.length > 1 gates whether
--     the Section field even shows in the form).
--   - Indexed since it's used in equality filters
--     (.eq("section_label", currentSectionFilter)), always alongside the
--     existing tenant_id filter.

alter table public.documents
  add column if not exists section_label text;

create index if not exists documents_section_label_idx
  on public.documents (tenant_id, section_label);
