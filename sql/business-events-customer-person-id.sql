-- Phase 4 (Business Events 360) - customer-person link for Booking,
-- Deployment, and Appointment. Trip (Logistics) already has its own
-- client_person_id column (sql/logistics-trip-columns.sql), live and
-- unchanged - this is deliberately a NEW, separate column rather than a
-- rename, so already-shipped Trip code (my-calendar.html's eventTripClient
-- field, computeTripSettlement, the Money picker, Nia's trip intent) is
-- not touched at all. Anywhere the app needs "this person's full event
-- history" it does client_person_id.eq.X OR customer_person_id.eq.X - one
-- extra clause, not two schemas.
--
-- Same additive/nullable pattern as every prior cluster on this shared
-- table (driver_person_id, deployed_person_id, staff_person_id, etc.) -
-- one column, gated client-side per business type, not a separate table.
--
-- Priority order (approved): Booking first, Appointment second,
-- Deployment third - all three share this one column, added together.

ALTER TABLE business_events
  ADD COLUMN IF NOT EXISTS customer_person_id uuid REFERENCES client_people(id) ON DELETE SET NULL;

CREATE INDEX IF NOT EXISTS idx_business_events_customer_person_id
  ON business_events (customer_person_id)
  WHERE customer_person_id IS NOT NULL;

-- ============================================================
-- VERIFICATION - run and paste back the output.
-- ============================================================

SELECT column_name, data_type, is_nullable
FROM information_schema.columns
WHERE table_name = 'business_events'
  AND column_name IN ('client_person_id', 'customer_person_id')
ORDER BY column_name;

SELECT indexname
FROM pg_indexes
WHERE tablename = 'business_events'
  AND indexname = 'idx_business_events_customer_person_id';
