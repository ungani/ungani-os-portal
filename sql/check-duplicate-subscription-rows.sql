-- Read-only sanity check, run alongside the trigger query. A UNIQUE
-- constraint (unlike CHECK/FK) can't be added NOT VALID in Postgres - it's
-- always fully validated against existing data at creation time - so this
-- should return zero rows. Included only to rule it out definitively
-- rather than assume.
select tenant_id, count(*)
from public.ungani_subscriptions
where tenant_id = 'a29af055-e4f0-48cf-af97-f99081a9106b'
group by tenant_id
having count(*) > 1;
