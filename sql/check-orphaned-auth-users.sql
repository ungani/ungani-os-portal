-- Read-only. Checks whether Supabase Auth still has accounts for the 12
-- test/demo tenants removed via sql/tenant-cleanup-delete.sql.
--
-- That deletion script only ever touched public-schema tables (tenants,
-- users, registrations, and tenant-scoped data) - it never called the
-- Supabase Auth Admin API and never touched the protected `auth` schema.
-- Nothing in this app's codebase does (confirmed via grep: no
-- supabase.auth.admin.* call anywhere, client or server). So those Auth
-- accounts (testclient1@ungani.com, restaurantdemo@ungani.com,
-- test@ungani.com, and whichever others the 12 tenants used) almost
-- certainly still exist - deleting the tenant/public.users row does not
-- delete the auth.users row, they are separate tables with no cascade
-- between them in either direction.
--
-- Run both queries below in the Supabase SQL Editor (it has access to
-- the auth schema; the app's own client-side/server-side Supabase
-- clients do not).

-- 1. The specific emails you named.
select id, email, created_at, last_sign_in_at
from auth.users
where email in (
  'testclient1@ungani.com',
  'restaurantdemo@ungani.com',
  'test@ungani.com'
  -- add any other emails from the 12 deleted tenants you remember here
);

-- 2. Broader net - any auth.users row with no matching public.users row
--    at all. This should catch ALL 12 leftover test accounts (and
--    reveal any others), even the ones you don't remember the exact
--    email for, without needing to know each address up front.
select au.id, au.email, au.created_at, au.last_sign_in_at
from auth.users au
where not exists (
  select 1 from public.users pu
  where pu.id = au.id or pu.email = au.email
)
order by au.created_at desc;
