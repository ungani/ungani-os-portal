-- Real bug found live while running the actual end-to-end reminder-
-- cadence test (not a unit test): /api/check-trial-warnings runs its
-- queries via a service_role Supabase client doing direct PostgREST
-- table access (not through a SECURITY DEFINER RPC), which requires
-- real base-table GRANTs independent of RLS. Same bug class as
-- documented in the earlier 28-table systemic sweep - RLS policies
-- define which ROWS a role can touch, not whether it has table access
-- at all.
--
-- Confirmed via information_schema.table_privileges (not guessed):
-- service_role had ZERO real data privileges (no SELECT/INSERT/UPDATE/
-- DELETE) on ungani_subscriptions, and was missing SELECT on tenants.
-- ungani_email_queue already had what it needed from the earlier sweep.
--
-- Scoped to exactly what this endpoint does against each table - it
-- SELECTs and UPDATEs ungani_subscriptions (the UPDATE is the auto-
-- suspend step; row creation goes through the SECURITY DEFINER function
-- set_ungani_subscription_period_from_payment, which doesn't need this
-- grant), and only ever SELECTs tenants (recipient email/business name
-- lookup, never writes it). No INSERT/DELETE granted on either - not
-- used by this endpoint.
--
-- Confirmed run and live 2026-08-12: a real trial_warning_week email
-- queued correctly for a test tenant after both grants were applied.

grant select, update on public.ungani_subscriptions to service_role;

grant select on public.tenants to service_role;
