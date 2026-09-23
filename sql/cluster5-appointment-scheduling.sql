-- Cluster 5 (Appointment scheduling): Salon, Healthcare, Gym (class variant)
-- Additive, nullable columns on business_events - same pattern as Trip/Booking/
-- Deployment/Job. Duration reuses the existing universal start_time/end_time
-- columns (already saved for every business type on every calendar event) -
-- no new duration column needed. Only a staff assignment and a session/
-- service amount are genuinely new.
-- staff_person_id: stylist/barber/therapist (Salon), doctor/nurse/dentist/
--   surgeon/lab technician (Healthcare), trainer (Gym) - staff assigned to
--   this appointment/class/session.
-- appointment_amount: session/service price, paired with the existing
--   rate_currency column (added for Trip) and transactions.related_event_id,
--   same settlement pattern as Trip/Deployment/Job.
-- No-double-booking conflict checking is enforced client-side in
-- my-calendar.html (queries existing rows for the same staff_person_id +
-- event_date + overlapping start_time/end_time before allowing a save) -
-- this is the first cluster to add real conflict detection, and it is an
-- optimistic client-side check, not a DB-level exclusion constraint, so a
-- true race under concurrent simultaneous saves is possible (same honest-gap
-- category as the previously-flagged branch-creation race condition).

ALTER TABLE business_events
  ADD COLUMN IF NOT EXISTS staff_person_id uuid,
  ADD COLUMN IF NOT EXISTS appointment_amount numeric;
