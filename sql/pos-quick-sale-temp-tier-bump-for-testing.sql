-- TEMPORARY, for live-testing the POS eligible path only. Revert this
-- back to 'starter' once testing is done (I'll remind you / do the
-- revert query at the end of the test pass).

update public.ungani_subscriptions
set package_key = 'business'
where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11';

-- ============================================================
-- VERIFICATION - run this and confirm it shows 'business'.
-- ============================================================
select tenant_id, package_key from public.ungani_subscriptions
where tenant_id = '84dd9bbc-329d-4bb6-9f27-b2fdfc5fff11';
