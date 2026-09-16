-- UNGANI OS: business_items.variant_group (Product Variants feature)
-- Run this once in the Supabase SQL editor.
--
-- Design notes:
--   - Additive only: one new nullable text column, no default. Every
--     existing item row gets NULL and renders/behaves exactly as today
--     everywhere it's read (POS, Quotations, Orders, Invoices, Nia,
--     low-stock alerts, item search) - nothing queries or filters on
--     this column yet, so nothing existing can regress.
--   - Deliberately a plain free-text label, not a foreign key to a
--     separate "products" table - a tester's real example was "Coca-Cola
--     / Fanta Orange / Sprite" grouped under "Soda", but the same column
--     needs to work unmodified for a boutique's "T-Shirt Size" or a
--     hotel's "Room Type" without any schema change per industry. Each
--     variant (Coke, Fanta, Sprite) stays its own full business_items
--     row - own stock, own price, own name - only sharing this one label
--     string so pickers can group them visually. This matches the
--     existing custom_fields design (business-items-custom-fields.sql):
--     schema-free, business-type-agnostic values, real structure lives
--     in the picker UI code, not the database.
--   - Partial index (WHERE variant_group is not null) since most items
--     won't set this - keeps the index small and only helps the exact
--     query the grouped pickers will run (group items by this label
--     within one tenant).

alter table public.business_items
  add column if not exists variant_group text;

create index if not exists business_items_variant_group_idx
  on public.business_items (tenant_id, variant_group)
  where variant_group is not null;
