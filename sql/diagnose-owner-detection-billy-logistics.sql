-- Read-only diagnostic for why get_my_ungani_staff_access() is not
-- returning is_owner = true for Billy Logistics' owner
-- (28626384-0594-43b0-add0-0f8a99ba8923, tenant 84dd9bbc-329d-4bb6-9f27-
-- b2fdfc5fff11), even after the RLS policy fix. The function's owner
-- branch depends entirely on a matching row in public.registrations -
-- this checks that underlying data directly, plus the function's own
-- output under real impersonation, so we can see exactly which
-- condition is failing instead of guessing.

-- =====================================================================
-- PART 1: raw underlying data, queried as your normal (superuser)
-- session - no role-switching, so this bypasses RLS entirely and shows
-- everything that actually exists, unfiltered.
-- =====================================================================

-- 1. Every registrations row that could plausibly match this owner -
--    by tenant_id OR by auth_user_id. This is what
--    get_my_ungani_staff_access()'s owner branch queries internally.
select
  id, tenant_id, auth_user_id, contact_email, email,
  status, registration_status,
  coalesce(registration_status, status, 'pending') as effective_status,
  lower(coalesce(registration_status, status, 'pending')) as effective_status_lower,
  created_at
from public.registrations
where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid
   or auth_user_id = '28626384-0594-43b0-add0-0f8a99ba8923'::uuid
order by created_at desc;

-- 2. The real auth.users.email for this owner - what v_email resolves
--    to inside the function.
select id, email
from auth.users
where id = '28626384-0594-43b0-add0-0f8a99ba8923'::uuid;

-- 3. Just in case: is this user ALSO present in ungani_team_members
--    (would only matter if the registrations match fails and it falls
--    through to the staff branch instead).
select id, tenant_id, auth_user_id, email, is_owner, is_active, status, deactivated_at, role_key, access_level
from public.ungani_team_members
where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid
   or auth_user_id = '28626384-0594-43b0-add0-0f8a99ba8923'::uuid;

-- =====================================================================
-- PART 2: the function's actual output under real impersonation -
-- same request.jwt.claims technique as the Part 2 lifecycle test.
-- =====================================================================

begin;

set local role authenticated;
set local "request.jwt.claims" to '{"sub": "28626384-0594-43b0-add0-0f8a99ba8923", "role": "authenticated"}';

select public.get_my_ungani_staff_access() as staff_access_result;

reset role;
rollback;
