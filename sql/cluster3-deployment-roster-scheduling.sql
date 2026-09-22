-- Cluster 3 (Deployment/roster scheduling): Security, Cleaning, Logistics, Tourism
-- Additive, nullable columns on business_events - same pattern as Cluster 1 (Booking).
-- deployed_person_id: guard/cleaner assigned (Security, Cleaning). Tourism reuses the
--   existing driver_person_id for guide assignment; Logistics unchanged.
-- deployed_site_item_id: site assigned (Security, Cleaning only).
-- deployment_rate: amount tied to this shift/job, paired with the existing
--   rate_currency column (added for Trip) and transactions.related_event_id.

ALTER TABLE business_events
  ADD COLUMN IF NOT EXISTS deployed_person_id uuid,
  ADD COLUMN IF NOT EXISTS deployed_site_item_id uuid,
  ADD COLUMN IF NOT EXISTS deployment_rate numeric;
