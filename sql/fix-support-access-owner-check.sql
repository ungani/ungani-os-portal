-- Fixes a confirmed showstopper bug in sql/ungani-support-access.sql:
-- the INSERT/UPDATE "owner can..." policies on ungani_support_access_
-- grants checked `lower(u.role) = 'owner'`. Confirmed against a REAL
-- production row (BILLY LOGISTICS, tenant 84dd9bbc-329d-4bb6-9f27-
-- b2fdfc5fff11) that this literal value is never assigned to a tenant's
-- business owner - the actual owner account had role = 'client'.
-- 'owner' is only ever used on this same column for UNGANI's own
-- internal admin accounts (a completely different account population,
-- gated separately in admin-shared.js/users.html).
--
-- Confirmed via the real source of public.get_my_ungani_staff_access()
-- (SECURITY DEFINER, returns jsonb) - the app's actual, single-source-
-- of-truth owner-detection mechanism, already used everywhere else that
-- gates owner-only behavior (client.html, staff-permission-guard.js,
-- staff-visibility-filter.js, my-security.html's 2FA gate): a user is
-- the tenant owner if they have an approved/active/trial row in
-- public.registrations matching their auth_user_id or email - nothing
-- to do with users.role. That function returns 'is_owner': true/false
-- in its jsonb result.
--
-- This migration is safe to run any time - only redefines the same 2
-- policies by name, no data or other policies touched. The existing
-- `tenant_id = public.get_my_ungani_tenant_id()` clause on both
-- policies was already correct and is left exactly as-is; only the
-- broken ownership sub-check is replaced.

drop policy if exists "Tenant owner can create their own support access grant" on public.ungani_support_access_grants;
create policy "Tenant owner can create their own support access grant"
  on public.ungani_support_access_grants
  for insert
  to authenticated
  with check (
    tenant_id = public.get_my_ungani_tenant_id()
    and (select (public.get_my_ungani_staff_access()->>'is_owner')::boolean) is true
  );

drop policy if exists "Tenant owner can update their own support access grant" on public.ungani_support_access_grants;
create policy "Tenant owner can update their own support access grant"
  on public.ungani_support_access_grants
  for update
  to authenticated
  using (tenant_id = public.get_my_ungani_tenant_id())
  with check (
    tenant_id = public.get_my_ungani_tenant_id()
    and (select (public.get_my_ungani_staff_access()->>'is_owner')::boolean) is true
  );

-- Verification - run after the above. Expect both policies' qual/
-- with_check text to now reference get_my_ungani_staff_access() instead
-- of users.role.
select policyname, cmd, qual, with_check
from pg_policies
where tablename = 'ungani_support_access_grants'
order by policyname;
