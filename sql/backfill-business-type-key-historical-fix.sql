-- BACKFILL (not a code fix - the live registration code already produces
-- correct business_type_key for every type, confirmed via 2 fresh live
-- test registrations). These 5 tenants were created under an older,
-- since-replaced version of index.html's registration flow that fell
-- back to the literal string 'general_business' for any type name it
-- didn't recognize - see memory: team_members_role_check_constraint_bug
-- pattern-sibling, business_type_key_historical_mismatch.
--
-- Scope: only the 5 tenants confirmed to be real (non-test) signups -
-- real contact names, real business names, some with genuine
-- transaction/people activity. Confirmed with the user before writing
-- this; explicitly excludes TEST 2, E2E Sections Test Hotel, BUZ TEST,
-- Test Hotel & Bar & Restaurant (obvious throwaway/test accounts).
--
-- Corrected key values computed by running the actual live
-- makeBusinessKey() function (from index.html) against each tenant's
-- real business_type text - not hand-derived, not guessed.

update public.tenants
set business_type_key = 'wholesale_and_distribution'
where id = '1918b377-c22e-420b-bee1-2bb9d76fa7f1'
  and business_name = 'RAKULA AGENCY LTD';

update public.tenants
set business_type_key = 'retail'
where id = '941e78d6-fc6f-45e9-9f7b-225b5b72283a'
  and business_name = 'Manu enterprices';

update public.tenants
set business_type_key = 'photography_videography'
where id = 'a5c8809c-865d-410c-9dcd-3e2c7bd52dbf'
  and business_name = 'BATOZ MUSIC ENT';

update public.tenants
set business_type_key = 'photography_videography'
where id = '78017e2e-6519-4e7e-9fdc-c7991b6b6dcc'
  and business_name = 'Mr. Schalie';

update public.tenants
set business_type_key = 'printing_branding_company'
where id = '8fb8cf7c-2159-4d35-b365-d61a625b566d'
  and business_name = 'Claudia';

-- ============================================================
-- VERIFICATION - run this and confirm all 5 rows show the corrected key.
-- ============================================================

select id, business_name, business_type, business_type_key
from public.tenants
where id in (
  '1918b377-c22e-420b-bee1-2bb9d76fa7f1',
  '941e78d6-fc6f-45e9-9f7b-225b5b72283a',
  'a5c8809c-865d-410c-9dcd-3e2c7bd52dbf',
  '78017e2e-6519-4e7e-9fdc-c7991b6b6dcc',
  '8fb8cf7c-2159-4d35-b365-d61a625b566d'
)
order by business_name;
