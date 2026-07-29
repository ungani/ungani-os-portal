-- Read-only. Scopes how widespread the status/registration_status
-- mismatch is across all real registrations rows, and whether
-- registration_status is DB-defaulted (which would mean every row is
-- affected by construction) or genuinely just stale on some rows.

-- 1. Column definition - is registration_status DB-defaulted / when was
--    it added relative to status?
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'registrations'
  and column_name in ('status', 'registration_status')
order by column_name;

-- 2. Overall breakdown: how many rows have registration_status NULL
--    (unaffected, coalesce falls through to status correctly) vs
--    non-null and matching status (harmless) vs non-null and
--    DISAGREEING with status (the real bug, same as Billy Logistics).
select
  case
    when registration_status is null then 'null (unaffected)'
    when lower(registration_status) = lower(status) then 'matches status (harmless)'
    else 'MISMATCH (same bug as Billy Logistics)'
  end as category,
  count(*) as row_count
from public.registrations
group by 1
order by 1;

-- 3. The actual mismatched rows, so we can see the pattern (all one
--    stale value? correlated with an age cutoff? specific to certain
--    tenants?).
select
  id, tenant_id, business_name, auth_user_id,
  status, registration_status, created_at
from public.registrations
where registration_status is not null
  and lower(registration_status) <> lower(status)
order by created_at desc;

-- 4. Of the mismatched rows, how many have status = 'approved' (i.e.
--    real, currently-active tenant owners who this bug would actually
--    misclassify, not just noise on old/rejected/pending signups).
select count(*) as approved_but_mismatched
from public.registrations
where registration_status is not null
  and lower(registration_status) <> lower(status)
  and lower(status) = 'approved';
