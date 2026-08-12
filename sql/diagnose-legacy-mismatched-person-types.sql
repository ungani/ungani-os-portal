-- Read-only. The my-people.html tile-matching fix (case/whitespace-
-- tolerant comparison) is already live and self-healing for formatting
-- drift - this query is for the OTHER class of issue it can't fix: a
-- record genuinely saved with a generic value (e.g. "customer") from
-- before admin-people.html became business-type-aware, which the
-- tile-matching correctly buckets under "Other" or a generic fallback
-- tile because it never really was tagged with a real business-specific
-- type. No script can safely guess what those SHOULD have been - this
-- just lists every distinct person_type value actually in use per
-- business type, so you can eyeball which look like real preset values
-- vs. leftover generic ones worth reviewing/re-editing via my-people.html
-- or admin-people.html.

select t.business_type_key, cp.person_type, count(*) as record_count
from public.client_people cp
join public.tenants t on t.id = cp.tenant_id
where cp.person_type is not null and cp.person_type <> ''
group by t.business_type_key, cp.person_type
order by t.business_type_key, record_count desc;
