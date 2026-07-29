-- Two parts, run in order.
--
-- PART 1: read-only. Lists every policy on ALL 6 operational tables the
-- support-access feature touches (business_items, transactions, tasks,
-- business_records, documents, client_people) - not just transactions.
-- transactions turned out to have a pre-existing, unrelated
-- "ungani_admin_manage_transactions" policy giving is_ungani_admin()
-- blanket access, independent of the support-access grant - checking
-- all 6 up front instead of assuming only one is affected, per this
-- project's standing rule about verifying across every instance of a
-- pattern rather than the one that happened to be tested.
--
-- PART 2: same 6-test lifecycle, targeting public.documents (swap the
-- table name below if PART 1 shows documents ALSO has a pre-existing
-- admin-blanket policy - re-check PART 1's output before trusting this
-- table choice). Also fixes the temp-table permission error: granting
-- the impersonated `authenticated` role access to the temp table right
-- after creating it, before any role-switching happens.

-- =====================================================================
-- PART 1
-- =====================================================================

select tablename, policyname, cmd, roles, qual
from pg_policies
where schemaname = 'public'
  and tablename in ('business_items', 'transactions', 'tasks', 'business_records', 'documents', 'client_people')
  and qual ilike '%is_ungani_admin%'
order by tablename, cmd, policyname;

-- =====================================================================
-- PART 2 - targeting public.documents. If PART 1 shows documents has
-- its own is_ungani_admin() blanket policy, replace every
-- "public.documents" below with a table PART 1 shows as clean instead.
-- =====================================================================

begin;

create temporary table support_access_test_results (
  step text,
  detail text
) on commit drop;

-- Fix for the earlier permission error: grant the impersonated role
-- access to this temp table BEFORE any role-switching happens (temp
-- tables are owned by the session's original role by default).
grant select, insert on support_access_test_results to authenticated;

insert into public.documents (tenant_id, document_title, document_type, status)
values ('84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid, 'RLS TEST - safe to ignore', 'RLS TEST', 'active');

-- Test A
set local role authenticated;
set local "request.jwt.claims" to '{"sub": "d5f64d1b-c307-4a39-8c97-cf5a7bc08b9d", "role": "authenticated"}';
insert into support_access_test_results
select 'A: admin read before any grant (expect 0)', count(*)::text
from public.documents where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid and document_type = 'RLS TEST';

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
from public.documents where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid and document_type = 'RLS TEST';

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
from public.documents where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid and document_type = 'RLS TEST';

update public.documents
set document_title = 'RLS TEST - admin edit under full_access'
where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid and document_type = 'RLS TEST';
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
from public.documents where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid and document_type = 'RLS TEST';

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
from public.documents where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11'::uuid and document_type = 'RLS TEST';

-- One final result set showing everything at once, in order.
reset role;
select step, detail from support_access_test_results order by step;

rollback;
