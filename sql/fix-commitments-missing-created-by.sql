-- Third time this exact table has silently drifted from the migration
-- file (RPCs missing, then deleted_at + 4 siblings missing, now
-- created_by). Confirmed via a live column diagnostic that this was the
-- ONLY gap - every other column from cluster4-commitments.sql's design
-- (14 business columns + created_at/updated_at + the 5 soft-delete
-- columns) was already live. Additive only, safe to run regardless of
-- state.
--
-- CONFIRMED FIXED via a real owner_upsert_ungani_commitment() test call
-- (see fix-commitments-missing-created-by-test in conversation history -
-- all scenarios PASS including created_by being populated with the
-- acting user's id).

alter table public.ungani_commitments
  add column if not exists created_by uuid;

-- VERIFICATION
select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_commitments'
  and column_name = 'created_by';
