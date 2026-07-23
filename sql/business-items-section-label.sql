-- UNGANI OS: business_items.section_label (multi-section business-type support)
-- Run this once in the Supabase SQL editor.
--
-- Design notes:
--   - Genuinely missing column, not a code bug - same root cause as
--     sql/documents-section-label.sql. Commit a167d2b (2026-07-18,
--     "Add section_label tagging to items/people/records/documents/support")
--     explicitly added section_label read/write/filter support to
--     my-items.html (applyItemCommonFilters()'s .eq("section_label", ...),
--     the "Section" dropdown in the add/edit form, saveItem()'s payload) -
--     the commit's own message lists "items" as one of the five tables it
--     was extending. The corresponding database migration for
--     business_items specifically appears to have never been run, exactly
--     parallel to the documents gap found and fixed earlier - business_items
--     was evidently left out of whatever untracked, manual batch added
--     this column elsewhere.
--   - Confirmed via a live error ("Could not load properties - column
--     business_items.section_label does not exist") and cross-checked
--     against the tenant's own full business_items schema dump, which
--     does not list section_label among its real columns.
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

alter table public.business_items
  add column if not exists section_label text;

create index if not exists business_items_section_label_idx
  on public.business_items (tenant_id, section_label);
