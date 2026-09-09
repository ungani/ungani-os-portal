-- BUG (found live-testing 2026-09-09, not part of any prior request):
-- ungani_team_members has a DB-level CHECK constraint on role_key that
-- was never updated when 'accountant'/'frontdesk' were added as valid
-- roles (sql/staff-role-presets-accountant-frontdesk.sql). That file's
-- own comment claimed "role_key is validated by a soft
-- normalize-or-fallback-to-'staff' check ... not a DB-level CHECK
-- constraint" - that assumption was wrong. A live test just confirmed
-- inserting a new team member with p_role_key = 'accountant' fails
-- with: "new row for relation \"ungani_team_members\" violates check
-- constraint \"ungani_team_members_role_key_check\"" - even though
-- owner_upsert_ungani_team_member's own validation and
-- ungani_role_preset_sections() both fully support this role. So any
-- brand-new Accountant/Front Desk hire is silently blocked at the DB
-- layer (existing/edited members with other roles are unaffected).
--
-- Fix: widen the constraint to match the RPC's own validated list -
-- ('owner', 'manager', 'staff', 'viewer', 'accountant', 'frontdesk') -
-- exactly. Safe, additive, no data changes.

alter table public.ungani_team_members
  drop constraint if exists ungani_team_members_role_key_check;

alter table public.ungani_team_members
  add constraint ungani_team_members_role_key_check
  check (role_key in ('owner', 'manager', 'staff', 'viewer', 'accountant', 'frontdesk'));

-- ============================================================
-- VERIFICATION - run this and confirm the constraint now includes all 6 roles.
-- ============================================================

select conname, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.ungani_team_members'::regclass
  and conname = 'ungani_team_members_role_key_check';
