-- The guided walkthrough's proactive "want a quick tour?" offer used a
-- browser-scoped localStorage flag (hasSeenNia()) to gate it, combined
-- with an "onboarding checklist mostly incomplete" heuristic
-- (get_my_ungani_onboarding_progress, doneCount <= 1) as a stand-in for
-- "does this look like a new business." Two real bugs from that:
--
-- 1. A genuinely new business sharing a browser with an already-seen
--    tenant (e.g. a reseller onboarding several client businesses from
--    one laptop, or Chris demoing multiple test accounts) never got
--    offered the tour at all - hasSeenNia() was already true from the
--    unrelated earlier tenant.
-- 2. An established business that simply never finished 2+ onboarding
--    checklist items (a real, common case - plenty of active, regular
--    users never bother ticking off a checklist) got RE-OFFERED the tour
--    every time they opened Nia from a new or cleared browser/device -
--    which reads as the tour "auto-repeating" even though nothing about
--    the business itself changed.
--
-- Fix: track eligibility with a real per-tenant flag instead of a
-- per-browser one or an indirect proxy. nia-assistant.js now checks
-- tenants.nia_walkthrough_offered_at directly (no extra RPC needed -
-- client-shared.js's loadTenant() already does `select("*")` on tenants)
-- and sets it via a direct .update() the moment the offer is shown,
-- matching the exact same direct-update pattern my-settings.html already
-- uses for other tenant-level toggle columns (debtors_payables_enabled,
-- stock_tracking_enabled) - not a new permission surface.
--
-- The backfill below is required, not optional: without it, EVERY
-- existing tenant (this column defaults to null for all of them) would
-- suddenly look "never offered" and get nagged with a brand-new tour
-- offer next time they open Nia, even businesses that have been live and
-- productive for months. Backfilling marks every tenant that exists at
-- migration time as already-offered, so only tenants created AFTER this
-- migration runs start out eligible.

alter table public.tenants
  add column if not exists nia_walkthrough_offered_at timestamptz default null;

update public.tenants
set nia_walkthrough_offered_at = now()
where nia_walkthrough_offered_at is null;
