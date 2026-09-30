-- Perf step 1, remaining two quick wins:
--
-- 1. Mark both RLS helper functions STABLE. Both bodies only SELECT from
--    other tables using auth.uid()/auth.jwt() - no writes, nothing that
--    changes mid-query - so STABLE is safe. Pairs with
--    sql/rls-wrap-admin-tenant-functions.sql (wrapping calls in a scalar
--    subquery only helps the planner cache the result if the function
--    itself is at least STABLE).
alter function public.is_ungani_admin() stable;
alter function public.get_my_ungani_tenant_id() stable;

-- 2. tasks is the one table missing the (tenant_id, deleted_at) composite
--    index that business_events/business_items/business_records/
--    client_people/documents already have (as ungani_*_active_idx).
create index if not exists tasks_active_idx
  on public.tasks (tenant_id, deleted_at);

-- NOT YET RUN against the live database.
