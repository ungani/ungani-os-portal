-- UNGANI OS: business_items.custom_fields (Phase 2 - type-aware items form)
-- Run this once in the Supabase SQL editor.
--
-- Design notes:
--   - Additive only: one new nullable JSONB column, default '{}'::jsonb.
--     No existing column is touched, so all existing property/item rows
--     and every dashboard/query that reads today's top-level columns
--     (bedrooms, bathrooms, property_price, total_units, etc.) keep
--     working unchanged.
--   - Holds section-specific extra field values (e.g. a Logistics/Cold
--     Chain item's fuel_capacity_liters/last_service_date, a Retail/
--     Pharmacy item's expiry_date/batch_number) that don't have a
--     dedicated top-level column. The field SCHEMA (which fields exist
--     per section, their labels/types) lives in code
--     (ungani-business-config.js's ITEM_FIELD_SETS), not in the
--     database - this column just stores whatever values that schema
--     currently defines, so adding/renaming a section's fields later
--     never requires another migration.
--   - GIN index added since Phase 3 dashboard work will likely want to
--     query into this JSONB (e.g. "items expiring in the next 7 days"
--     across all Pharmacy tenants) - cheap to add now, expensive to
--     retrofit under load later.

alter table public.business_items
  add column if not exists custom_fields jsonb not null default '{}'::jsonb;

create index if not exists business_items_custom_fields_gin_idx
  on public.business_items using gin (custom_fields);
