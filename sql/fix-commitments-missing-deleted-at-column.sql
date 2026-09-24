-- URGENT: get_my_ungani_commitments() is returning HTTP 400 in production
-- right now, on EVERY tenant's dashboard/People page load (it's called
-- unconditionally, not just for Cluster 4 business types), and it fully
-- blocks Cluster 4 (Commitments/Leases/Memberships/Contracts) for Real
-- Estate/Gym/Security/Cleaning - confirmed via live network response:
--   {"code":"42703","message":"column c.deleted_at does not exist",
--    "hint":"Perhaps you meant to reference the column \"p.deleted_at\"."}
--
-- The Postgres hint itself is the smoking gun: it found deleted_at on
-- "p" (client_people, joined in the same query) but not on "c"
-- (ungani_commitments) - meaning the LIVE ungani_commitments table
-- doesn't actually have the deleted_at column that
-- sql/cluster4-commitments.sql:68 defines and that this session's own
-- memory says was already run. Same "file says X, live DB has Y" bug
-- class this project has hit before (the commitments RPC gap earlier
-- tonight, the audit_log grant, etc).
--
-- ============================================================
-- PART 1: DIAGNOSTIC - run first, paste back the output, so we know
-- ungani_commitments' real live columns before assuming the fix below
-- is complete.
-- ============================================================

select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_commitments'
order by ordinal_position;

-- ============================================================
-- PART 2: FIX - additive only, safe to run regardless of what PART 1
-- shows (IF NOT EXISTS). Restores the full soft-delete column set from
-- the original design (cluster4-commitments.sql:64-72) that the read
-- RPC (and the write RPC's soft-delete path, if it references these)
-- depend on.
-- ============================================================

alter table public.ungani_commitments
  add column if not exists deleted_at timestamptz,
  add column if not exists deleted_by uuid,
  add column if not exists delete_reason text,
  add column if not exists restored_at timestamptz,
  add column if not exists restored_by uuid;

-- ============================================================
-- PART 3: RE-VERIFY - run after PART 2, then reload any dashboard page
-- and confirm the 400 error is gone (browser dev tools Network tab,
-- filter for "get_my_ungani_commitments").
-- ============================================================

select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_commitments'
  and column_name in ('deleted_at', 'deleted_by', 'delete_reason', 'restored_at', 'restored_by')
order by column_name;
