-- Read-only. Investigates the 2 leftover "registrations" rows found by
-- sql/ice-cold-logistics-remaining-check.sql's query 3, before deleting
-- anything - same verify-before-delete discipline as the original
-- 12-tenant cleanup (sql/tenant-cleanup-verify.sql before
-- sql/tenant-cleanup-delete.sql).
--
-- Why these 2 rows likely survived the original cleanup even though its
-- last step was `delete from registrations where email in (select email
-- from _cleanup_targets where email is not null)`: registrations is only
-- ever linked to a tenant informally, by matching email - if any of the
-- 6 already-deleted "Ice cold Worldwide Logistics Limited" tenant rows
-- had a different (or null) tenants.email value than
-- olensie@gmail.com, that email-based match simply wouldn't have caught
-- these 2 registrations rows. Nothing suspicious - just a loose join
-- that missed a case, not a sign anything else is wrong.
--
-- registrations has no downstream FK dependents anywhere in this schema
-- (confirmed by the original cleanup script's own design - it deletes
-- FROM registrations LAST, as pure leaf cleanup, with no table
-- referencing it afterward). The one thing that DOES matter here:
-- registrations.auth_user_id can point to a real Supabase Auth account
-- (confirmed real column - index.html's insertRegistration() sets
-- `auth_user_id: data.authUserId` on every submission). If either row
-- has a non-null auth_user_id, that's the same class of leftover-Auth-
-- account issue as sql/check-orphaned-auth-users.sql already
-- surfaced for the 12 deleted tenants - worth checking together since
-- it's the same email.

-- 1. Full row detail for both.
select id, business_name, company_name, contact_name, phone, email,
       business_type, business_type_key, status, notes, auth_user_id, created_at
from registrations
where id in ('f5d13226-64ee-40a4-8451-2af0d05695a5', 'd256b874-6ebd-45ca-b027-8e27c17f31ff');

-- 2. Does an Auth account for this email still exist? (Run in the SQL
--    editor, which has access to the auth schema.)
select id, email, created_at, last_sign_in_at
from auth.users
where email = 'olensie@gmail.com';

-- 3. Sanity re-check - confirms nothing else in the schema currently
--    references either registrations row (should return 0 rows; there's
--    no FK to registrations anywhere, so this is a name/email match
--    only, same informal link registrations always uses).
select 'tenants' as table_name, count(*) from tenants where email = 'olensie@gmail.com'
union all
select 'users', count(*) from users where email = 'olensie@gmail.com';
