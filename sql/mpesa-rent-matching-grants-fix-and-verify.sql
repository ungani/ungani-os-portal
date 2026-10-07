-- Corrective grants sweep, missed in the first pass. Postgres grants
-- PUBLIC execute on every newly-created function by default unless
-- explicitly revoked - a plain `grant execute ... to X` with no revoke
-- leaves PUBLIC (and so anon/authenticated too) still able to call it
-- directly via PostgREST's RPC endpoint. This project has hit this
-- exact class of bug before (sql/fix-remaining-service-role-grants.sql,
-- sql/fix-ungani-packages-and-sweep-service-role-grants.sql) - missed
-- it again on these 6 new functions. Matches the established pattern
-- from sql/mpesa-bank-paybill-failure-status-fix.sql (service-role-only)
-- and sql/deposits-feature.sql (owner-facing).

-- Service-role only - callable solely from the Node endpoint
-- (supabaseAdmin.rpc), which the two owner wrappers below also route
-- through internally.
revoke all on function public.apply_ungani_mpesa_rent_payment(uuid, text, text, text, numeric, timestamptz, text, uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.apply_ungani_mpesa_rent_payment(uuid, text, text, text, numeric, timestamptz, text, uuid, uuid, uuid) to service_role;

revoke all on function public.service_accrue_ungani_monthly_rent() from public, anon, authenticated;
grant execute on function public.service_accrue_ungani_monthly_rent() to service_role;

-- Owner-facing - authenticated only, each function checks ownership of
-- its OWN resolved tenant_id internally (see the SQL bodies already
-- shipped: is_my_ungani_tenant_owner(get_my_ungani_tenant_id())).
revoke all on function public.owner_list_ungani_payments_to_match() from public, anon, authenticated;
grant execute on function public.owner_list_ungani_payments_to_match() to authenticated;

revoke all on function public.owner_get_ungani_payments_to_match_count() from public, anon, authenticated;
grant execute on function public.owner_get_ungani_payments_to_match_count() to authenticated;

revoke all on function public.owner_resolve_ungani_payment_to_match(uuid, uuid, uuid) from public, anon, authenticated;
grant execute on function public.owner_resolve_ungani_payment_to_match(uuid, uuid, uuid) to authenticated;

revoke all on function public.owner_bulk_import_ungani_mpesa_statement(jsonb) from public, anon, authenticated;
grant execute on function public.owner_bulk_import_ungani_mpesa_statement(jsonb) to authenticated;

-- ============================================================
-- COMBINED VERIFICATION - run this and paste back the full output.
-- ============================================================

-- 1) Overload count per function - must be exactly 1 each.
select proname, count(*) as overload_count
from pg_proc
where pronamespace = 'public'::regnamespace
  and proname in (
    'apply_ungani_mpesa_rent_payment',
    'owner_list_ungani_payments_to_match',
    'owner_get_ungani_payments_to_match_count',
    'owner_resolve_ungani_payment_to_match',
    'owner_bulk_import_ungani_mpesa_statement',
    'service_accrue_ungani_monthly_rent'
  )
group by proname
order by proname;

-- 2) Exact EXECUTE grants per function/role. Expected result:
--    apply_ungani_mpesa_rent_payment / service_accrue_ungani_monthly_rent
--      -> only service_role appears.
--    the 4 owner_* functions -> only authenticated appears.
--    public/anon should appear for NONE of the 6.
select
  p.proname,
  grantee.rolname as granted_to,
  acl.privilege_type
from pg_proc p
cross join lateral aclexplode(coalesce(p.proacl, acldefault('f', p.proowner))) as acl
join pg_roles grantee on grantee.oid = acl.grantee
where p.pronamespace = 'public'::regnamespace
  and p.proname in (
    'apply_ungani_mpesa_rent_payment',
    'owner_list_ungani_payments_to_match',
    'owner_get_ungani_payments_to_match_count',
    'owner_resolve_ungani_payment_to_match',
    'owner_bulk_import_ungani_mpesa_statement',
    'service_accrue_ungani_monthly_rent'
  )
  and acl.privilege_type = 'EXECUTE'
order by p.proname, grantee.rolname;

-- 3) RLS status + policies on ungani_payments_to_match.
select relrowsecurity, relforcerowsecurity
from pg_class
where oid = 'public.ungani_payments_to_match'::regclass;

select policyname, cmd, qual
from pg_policies
where schemaname = 'public' and tablename = 'ungani_payments_to_match';
