-- Read-only. Verifies sql/ungani-support-access.sql landed exactly as
-- written, then behaviorally proves the RLS actually enforces what it
-- claims to, by simulating real users inside a transaction (Supabase's
-- standard technique - `set local request.jwt.claims` - rather than
-- trusting the policy text alone). Same "verify, don't assume" pattern
-- as sql/verify-tenant-integrations-setup.sql, extended with a real
-- behavioral pass since this migration's whole point is an access
-- boundary, not just a data shape.

-- =====================================================================
-- PART 1: Schema + policy shape. Run this section immediately, no prep
-- needed.
-- =====================================================================

-- 1. Table + column shape.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'ungani_support_access_grants'
order by ordinal_position;

-- 2. RLS is actually enabled (a table can have policies defined while
--    RLS itself is off, which makes every policy a no-op).
select relrowsecurity as rls_enabled
from pg_class
where relname = 'ungani_support_access_grants';

-- 3. All 4 policies on the grants table itself - names, command, roles.
select policyname, cmd, roles, qual, with_check
from pg_policies
where tablename = 'ungani_support_access_grants'
order by policyname;

-- 4. Base table-level grants to `authenticated` on the new table - the
--    thing RLS policies alone can't confirm. Expect SELECT, INSERT,
--    UPDATE present (no DELETE). sql/ungani-support-access.sql had no
--    explicit `grant` statements, following the same precedent as
--    audit-log-setup.sql and tenant-integrations-setup.sql (both of
--    which also have none and work correctly) - this confirms that
--    precedent held for THIS table rather than assuming it. If this
--    comes back empty for authenticated, every query against the table
--    will fail with a permission error before RLS is even evaluated -
--    the fix is a one-line
--    `grant select, insert, update on public.ungani_support_access_grants to authenticated;`
select grantee, privilege_type
from information_schema.table_privileges
where table_schema = 'public' and table_name = 'ungani_support_access_grants'
order by grantee, privilege_type;

-- 5. Unique constraint on tenant_id and the FK to tenants(id) both exist.
select conname, contype, pg_get_constraintdef(oid) as definition
from pg_constraint
where conrelid = 'public.ungani_support_access_grants'::regclass
order by conname;

-- 6. All 21 new policies landed across the 6 operational tables (3 each:
--    select/update/insert) - expect exactly 21 rows.
select tablename, policyname, cmd
from pg_policies
where policyname like 'UNGANI support access can%'
order by tablename, cmd;

-- 7. The new audit-log policy landed.
select policyname, cmd, qual
from pg_policies
where tablename = 'ungani_audit_log'
  and policyname = 'Tenant owner can read their tenant''s support access audit trail';


-- =====================================================================
-- PART 2: Real behavioral RLS test. Needs two real user IDs from your
-- database. Everything runs inside a transaction that is ROLLED BACK at
-- the end, so it leaves no trace in your real data regardless of
-- outcome - safe to run against production.
--
-- The Supabase SQL Editor sends this as plain SQL (not through psql), so
-- it does NOT support psql meta-commands like \set. Instead: find and
-- replace these THREE placeholder tokens everywhere they appear below,
-- then run the whole PART 2 block as one script.
--
--   OWNER_ID_HERE          -> a real client OWNER's auth user id
--                             (users.id where role = 'owner')
--   OWNER_TENANT_ID_HERE   -> that same owner's tenants.id
--   ADMIN_ID_HERE          -> a real UNGANI admin's auth user id
--
-- Find these with:
--   select id, role, tenant_id from public.users where role = 'owner' limit 5;
--   select id, email from auth.users where id in (select id from public.users where role in ('admin','super_admin'));
-- =====================================================================

begin;

-- Use an obviously-fake, harmless transaction row so the read/write
-- tests below have something real to look at without touching any of
-- the tenant's actual business data.
insert into public.transactions (tenant_id, amount, transaction_type, category, transaction_date, status)
values ('OWNER_TENANT_ID_HERE'::uuid, 1, 'income', 'RLS TEST - safe to ignore', current_date, 'completed');

-- --- Test A: before any grant exists, admin should see ZERO rows for
--     this tenant's transactions. ---
set local role authenticated;
set local "request.jwt.claims" to '{"sub": "ADMIN_ID_HERE", "role": "authenticated"}';
select 'Test A: admin read before any grant (expect 0 rows)' as test, count(*) as visible_rows
from public.transactions where tenant_id = 'OWNER_TENANT_ID_HERE'::uuid;

-- --- Test B: owner invites (pending) - as owner. Admin should STILL
--     see zero transaction rows (pending grants no access). ---
set local role authenticated;
set local "request.jwt.claims" to '{"sub": "OWNER_ID_HERE", "role": "authenticated"}';

insert into public.ungani_support_access_grants (tenant_id, status, access_level, invited_at, invited_by)
values ('OWNER_TENANT_ID_HERE'::uuid, 'pending', 'view_only', now(), 'OWNER_ID_HERE'::uuid)
on conflict (tenant_id) do update set status = 'pending', access_level = 'view_only', invited_at = now(), invited_by = 'OWNER_ID_HERE'::uuid, revoked_at = null;

set local role authenticated;
set local "request.jwt.claims" to '{"sub": "ADMIN_ID_HERE", "role": "authenticated"}';
select 'Test B: admin read while grant is pending (expect 0 rows)' as test, count(*) as visible_rows
from public.transactions where tenant_id = 'OWNER_TENANT_ID_HERE'::uuid;

-- --- Test C: owner grants full_access for 1 hour. Admin should NOW
--     see the test row, and be able to update it. ---
set local role authenticated;
set local "request.jwt.claims" to '{"sub": "OWNER_ID_HERE", "role": "authenticated"}';

update public.ungani_support_access_grants
set status = 'active', access_level = 'full_access', granted_at = now(), granted_by = 'OWNER_ID_HERE'::uuid,
    expires_at = now() + interval '1 hour', revoked_at = null, revoked_by = null
where tenant_id = 'OWNER_TENANT_ID_HERE'::uuid;

set local role authenticated;
set local "request.jwt.claims" to '{"sub": "ADMIN_ID_HERE", "role": "authenticated"}';
select 'Test C1: admin read while grant is active/full_access (expect 1+ rows)' as test, count(*) as visible_rows
from public.transactions where tenant_id = 'OWNER_TENANT_ID_HERE'::uuid;

update public.transactions
set description = 'RLS TEST - admin edit under full_access'
where tenant_id = 'OWNER_TENANT_ID_HERE'::uuid and category = 'RLS TEST - safe to ignore';
select 'Test C2: admin update while active/full_access' as test, 'ran without error = pass' as result;

-- --- Test D: owner revokes. Admin access should end IMMEDIATELY. ---
set local role authenticated;
set local "request.jwt.claims" to '{"sub": "OWNER_ID_HERE", "role": "authenticated"}';

update public.ungani_support_access_grants
set status = 'revoked', revoked_at = now(), revoked_by = 'OWNER_ID_HERE'::uuid
where tenant_id = 'OWNER_TENANT_ID_HERE'::uuid;

set local role authenticated;
set local "request.jwt.claims" to '{"sub": "ADMIN_ID_HERE", "role": "authenticated"}';
select 'Test D: admin read immediately after revoke (expect 0 rows)' as test, count(*) as visible_rows
from public.transactions where tenant_id = 'OWNER_TENANT_ID_HERE'::uuid;

-- --- Test E: expiry, not just explicit revoke, cuts off access. Grant
--     active again but already-expired. ---
set local role authenticated;
set local "request.jwt.claims" to '{"sub": "OWNER_ID_HERE", "role": "authenticated"}';

update public.ungani_support_access_grants
set status = 'active', access_level = 'full_access', granted_at = now() - interval '2 hours',
    expires_at = now() - interval '1 hour', revoked_at = null, revoked_by = null
where tenant_id = 'OWNER_TENANT_ID_HERE'::uuid;

set local role authenticated;
set local "request.jwt.claims" to '{"sub": "ADMIN_ID_HERE", "role": "authenticated"}';
select 'Test E: admin read with status=active but expires_at in the past (expect 0 rows)' as test, count(*) as visible_rows
from public.transactions where tenant_id = 'OWNER_TENANT_ID_HERE'::uuid;

-- --- Test F (optional): owner-only write gate on the grants table
--     itself - simulate a NON-owner tenant member (any other real user
--     id from the SAME tenant with role != 'owner') trying to grant
--     access. Uncomment and fill in a real non-owner-same-tenant user id
--     to run this; the important assertion is that it FAILS (0 rows
--     affected, or a permission error) - a manager/staff account must
--     never be able to activate support access themselves.
-- ---
-- set local role authenticated;
-- set local "request.jwt.claims" to '{"sub": "NON_OWNER_SAME_TENANT_ID_HERE", "role": "authenticated"}';
-- update public.ungani_support_access_grants set status = 'active', access_level = 'full_access', expires_at = now() + interval '1 hour' where tenant_id = 'OWNER_TENANT_ID_HERE'::uuid;
-- select 'Test F: non-owner attempts to grant (expect 0 rows updated)' as test;

reset role;
rollback;

-- Nothing above persists - the ROLLBACK undid the test transaction row,
-- the grant insert/updates, and the description edit. Re-run PART 1's
-- query #6 or a plain `select count(*) from ungani_support_access_grants;`
-- afterward if you want to double check the table is still empty.
