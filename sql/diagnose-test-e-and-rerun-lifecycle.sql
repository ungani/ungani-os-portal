-- Two parts. Run both, in order, in one go.
--
-- PART 1: read-only, no impersonation. Lists EVERY policy currently on
-- public.transactions - not just the 21 support-access ones from
-- sql/ungani-support-access.sql. Test E returning 9 rows (far more than
-- the single test row inserted) is suspicious in a specific way: if
-- there's a PRE-EXISTING, unrelated permissive policy that already
-- grants admins broad read access to transactions (e.g. for cross-
-- tenant admin reporting/billing pages), Postgres combines multiple
-- permissive policies for the same command with OR - meaning that
-- other policy alone could explain admin visibility regardless of
-- whether the support-access grant is expired. Need to see this before
-- concluding the expiry check itself is broken.
--
-- PART 2: the same 6-test lifecycle, rewritten to write each result
-- into a temp table (auto-dropped on rollback/commit) instead of
-- separate SELECT statements, so exactly one final SELECT at the end
-- shows all 6 rows together - same fix pattern as the earlier sweep
-- query that only showed its last statement's output.

-- =====================================================================
-- PART 1
-- =====================================================================

select policyname, cmd, roles, qual, with_check
from pg_policies
where schemaname = 'public' and tablename = 'transactions'
order by cmd, policyname;

-- =====================================================================
-- PART 2 - real behavioral RLS test, Billy Logistics, all 6 results in
-- one final table.
-- =====================================================================

begin;

create temporary table support_access_test_results (
  step text,
  detail text
) on commit drop;

insert into public.transactions (tenant_id, amount, transaction_type, category, transaction_date, status)
values ('84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid, 1, 'income', 'RLS TEST - safe to ignore', current_date, 'completed');

-- Test A
set local role authenticated;
set local "request.jwt.claims" to '{"sub": "d5f64d1b-c307-4a39-8c97-cf5a7bc08b9d", "role": "authenticated"}';
insert into support_access_test_results
select 'A: admin read before any grant (expect 0)', count(*)::text
from public.transactions where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid;

-- Test B
set local role authenticated;
set local "request.jwt.claims" to '{"sub": "28626384-0594-43b0-add0-0f8a99ba8923", "role": "authenticated"}';
insert into public.ungani_support_access_grants (tenant_id, status, access_level, invited_at, invited_by)
values ('84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid, 'pending', 'view_only', now(), '28626384-0594-43b0-add0-0f8a99ba8923'::uuid)
on conflict (tenant_id) do update set status = 'pending', access_level = 'view_only', invited_at = now(), invited_by = '28626384-0594-43b0-add0-0f8a99ba8923'::uuid, revoked_at = null;

set local role authenticated;
set local "request.jwt.claims" to '{"sub": "d5f64d1b-c307-4a39-8c97-cf5a7bc08b9d", "role": "authenticated"}';
insert into support_access_test_results
select 'B: admin read while pending (expect 0)', count(*)::text
from public.transactions where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid;

-- Test C
set local role authenticated;
set local "request.jwt.claims" to '{"sub": "28626384-0594-43b0-add0-0f8a99ba8923", "role": "authenticated"}';
update public.ungani_support_access_grants
set status = 'active', access_level = 'full_access', granted_at = now(), granted_by = '28626384-0594-43b0-add0-0f8a99ba8923'::uuid,
    expires_at = now() + interval '1 hour', revoked_at = null, revoked_by = null
where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid;

set local role authenticated;
set local "request.jwt.claims" to '{"sub": "d5f64d1b-c307-4a39-8c97-cf5a7bc08b9d", "role": "authenticated"}';
insert into support_access_test_results
select 'C1: admin read while active/full_access (expect 1+)', count(*)::text
from public.transactions where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid;

update public.transactions
set description = 'RLS TEST - admin edit under full_access'
where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid and category = 'RLS TEST - safe to ignore';
insert into support_access_test_results values ('C2: admin update while active/full_access', 'ran without error = pass');

-- Test D
set local role authenticated;
set local "request.jwt.claims" to '{"sub": "28626384-0594-43b0-add0-0f8a99ba8923", "role": "authenticated"}';
update public.ungani_support_access_grants
set status = 'revoked', revoked_at = now(), revoked_by = '28626384-0594-43b0-add0-0f8a99ba8923'::uuid
where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid;

set local role authenticated;
set local "request.jwt.claims" to '{"sub": "d5f64d1b-c307-4a39-8c97-cf5a7bc08b9d", "role": "authenticated"}';
insert into support_access_test_results
select 'D: admin read immediately after revoke (expect 0)', count(*)::text
from public.transactions where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid;

-- Test E
set local role authenticated;
set local "request.jwt.claims" to '{"sub": "28626384-0594-43b0-add0-0f8a99ba8923", "role": "authenticated"}';
update public.ungani_support_access_grants
set status = 'active', access_level = 'full_access', granted_at = now() - interval '2 hours',
    expires_at = now() - interval '1 hour', revoked_at = null, revoked_by = null
where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid;

set local role authenticated;
set local "request.jwt.claims" to '{"sub": "d5f64d1b-c307-4a39-8c97-cf5a7bc08b9d", "role": "authenticated"}';
insert into support_access_test_results
select 'E: admin read with status=active but expires_at in the past (expect 0)', count(*)::text
from public.transactions where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid;

-- One final result set showing everything at once, in order.
reset role;
select step, detail from support_access_test_results order by step;

rollback;
