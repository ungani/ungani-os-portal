-- Cluster 2 (Job/work-order with stages): Automotive, Printing, Furniture, Construction
-- Additive, nullable columns on business_items - jobs/orders/projects already live in
-- this table as generic items (Print Job, Order, Project/Work Package); unlike Trip/
-- Booking/Deployment this isn't a calendar activity, so business_items (not
-- business_events) is the correct additive extension point.
-- job_stage: free text, same precedent as Real Estate's existing completion_status
--   field - per-type example placeholders (production stages vs Construction milestones).
-- job_total_amount: what the client owes, connects to Money via the existing
--   transactions.related_item_id column (already live for Real Estate/Logistics).
-- job_materials_cost / job_labor_cost: informational job-costing fields - real cost
--   tracking happens via Money expense records tagged to the same job.
-- job_due_date: persistent deadline on the job itself.

ALTER TABLE business_items
  ADD COLUMN IF NOT EXISTS job_stage text,
  ADD COLUMN IF NOT EXISTS job_total_amount numeric,
  ADD COLUMN IF NOT EXISTS job_materials_cost numeric,
  ADD COLUMN IF NOT EXISTS job_labor_cost numeric,
  ADD COLUMN IF NOT EXISTS job_due_date date;
