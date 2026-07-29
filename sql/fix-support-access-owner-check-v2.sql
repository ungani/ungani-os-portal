-- Follow-up to sql/fix-support-access-owner-check.sql. That fix
-- replaced the broken `lower(u.role) = 'owner'` check with
-- `is_owner IS TRUE` from get_my_ungani_staff_access() - correct as far
-- as it went, but incomplete: every OTHER real consumer of this RPC
-- (client.html, staff-permission-guard.js, staff-visibility-filter.js)
-- doesn't check is_owner alone. They also treat "no confirmed staff
-- record" (role_key empty or 'guest') as owner by default, because a
-- real owner who never went through Team Access has no team_members
-- row at all - an RPC result of "no match found" must not be read as
-- "definitely not owner." This policy was the one place that missed
-- that fallback, which is what made it (and only it) actually break
-- when the registrations.status/registration_status coalesce bug
-- pushed a real owner into the RPC's no-match branch - see
-- sql/fix-staff-access-status-coalesce-order.sql for that root-cause
-- fix, which should be run either before or after this one.
--
-- This makes the policy match the app's real, established owner-
-- detection semantics exactly, so it's resilient to the same class of
-- RPC-quirk on its own, not just reliant on the RPC always being
-- perfectly accurate.

drop policy if exists "Tenant owner can create their own support access grant" on public.ungani_support_access_grants;
create policy "Tenant owner can create their own support access grant"
  on public.ungani_support_access_grants
  for insert
  to authenticated
  with check (
    tenant_id = public.get_my_ungani_tenant_id()
    and exists (
      select 1
      from (select public.get_my_ungani_staff_access() as access) s
      where (s.access->>'is_owner')::boolean is true
         or coalesce(lower(s.access->>'role_key'), '') in ('', 'guest')
    )
  );

drop policy if exists "Tenant owner can update their own support access grant" on public.ungani_support_access_grants;
create policy "Tenant owner can update their own support access grant"
  on public.ungani_support_access_grants
  for update
  to authenticated
  using (tenant_id = public.get_my_ungani_tenant_id())
  with check (
    tenant_id = public.get_my_ungani_tenant_id()
    and exists (
      select 1
      from (select public.get_my_ungani_staff_access() as access) s
      where (s.access->>'is_owner')::boolean is true
         or coalesce(lower(s.access->>'role_key'), '') in ('', 'guest')
    )
  );

-- Verification - run after the above.
select policyname, cmd, qual, with_check
from pg_policies
where tablename = 'ungani_support_access_grants'
order by policyname;
