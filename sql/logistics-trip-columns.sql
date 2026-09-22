-- UNGANI OS: Logistics Trip depth (Transport + Cold Chain sub-sectors
-- only - Clearing & Forwarding's "Container" concept doesn't fit this
-- shape, see client_person_id/clearance_fee added directly to the
-- container item instead, no migration needed for that part).
--
-- Design notes:
--   - Additive only: 5 new nullable columns on business_events, real FKs
--     where the target is a real table (business_items, client_people).
--     No existing column touched. Every other business type's use of
--     business_events (calendar entries, generic events) is completely
--     unaffected - these columns simply stay null for them.
--   - on delete set null: if the linked vehicle/driver/client is ever
--     deleted, the Trip event itself is NOT deleted - it just becomes
--     unlinked, matching every other linked_*_id column in this app.
--   - rate is numeric, not tied to a currency column here - follows the
--     same convention as transactions.amount (KES-denominated unless
--     multi-currency is separately opted into).
--   - No RLS changes needed: business_events' existing tenant-scoped RLS
--     policies already govern every column on the row, including these.

alter table public.business_events
  add column if not exists vehicle_item_id uuid references public.business_items(id) on delete set null,
  add column if not exists driver_person_id uuid references public.client_people(id) on delete set null,
  add column if not exists client_person_id uuid references public.client_people(id) on delete set null,
  add column if not exists route text,
  add column if not exists rate numeric;

create index if not exists business_events_vehicle_item_id_idx on public.business_events (vehicle_item_id);
create index if not exists business_events_driver_person_id_idx on public.business_events (driver_person_id);
create index if not exists business_events_client_person_id_idx on public.business_events (client_person_id);
