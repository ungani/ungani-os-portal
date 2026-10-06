# Car Showroom — Progress Snapshot (paused for Property priority)

Work paused here per explicit instruction to prioritize the Friday property client meeting. Everything below is either live-verified via SQL test or written-but-not-yet-browser-tested. Nothing in this feature is live on Vercel — all frontend changes are uncommitted-until-now local edits; this commit is the first time any of it reaches git, and a deploy only happens if/when it's pushed.

## DONE and live-tested (SQL layer — 100% verified via rolled-back tests)

- **Migration** (`sql/car-showroom-foundation.sql`): 7 real columns on `business_items` (vin_number, condition_type, ownership_type, sourcing_type, logbook_status, minimum_price, consignment_owner_person_id), 2 trade-in audit columns on `ungani_customer_invoices`, new `ungani_inquiries` table + RLS + soft-delete integration. 6/6 live verification checks pass.
- **Stock-status exclusion**: one guard in `ungani-stock-status.js`'s `getItemStockStatus()` (`if business_type_key === 'car_showroom' return null`) covers all 9 shared places (8 frontend call sites + the SQL mirror, which is only ever invoked via `adjust_ungani_stock()` — a path showroom vehicles never touch). Proven via code-level deduction (the guard is unconditionally false for every other type) plus a live Playwright smoke-test on Billy Logistics (Logistics type) confirming "out of stock"/"low stock" still render correctly post-change.
- **Single stock-movement path**: `owner_set_ungani_vehicle_status()` is the only path that marks a car Sold/Reserved/Available/In-transit/In-repair. 8/8 rolled-back test scenarios pass, including proof that `sync_ungani_invoice_stock` is a structural no-op for showroom tenants (they never enable `stock_tracking_enabled`) even when an invoice line references a car's `item_id`.
- **Money wiring**: `owner_create_ungani_vehicle_sale()` nets trade-in value through the existing, unmodified `owner_upsert_ungani_customer_invoice()`'s `discount_amount` parameter; vehicle costs ride on the existing `transactions.related_item_id` column (zero new tables). 9/9 rolled-back scenarios pass: trade-in netting, cash-only "received", vehicle costs via Money, instalment "Owed to you", and reject-guards (already-sold, bad trade-in value).
- **Inquiries read RPC** (`get_my_ungani_inquiries()`): live-verified grant.

## DONE but NOT yet browser-tested (frontend layer)

- `car_showroom` business-type vocabulary entry in `ungani-business-config.js` (hidden from signup via `hidden_from_signup: true` until the feature is finished — confirmed `index.html`'s `populateBusinessTypeOptions()` now filters it out).
- Dashboard detection/routing (`detectCarShowroom`, `isCarShowroom`) + `renderCarShowroomDashboard()` in `client.html`: 4 KPI tiles (Available/Reserved/Sold this month/Owed to you), Longest-in-Yard card, attention groups (overdue tasks, inquiry follow-ups, test drives today), quick actions, revenue trend chart. Syntax-sanity-checked (balanced braces/backticks, every helper function call verified against an existing working call site in the School dashboard it was modeled on) but never opened in a browser end-to-end as a real car_showroom tenant.
- `dashboardData.inquiries` wired into the load/cache pipeline (`safeInquiries()`, cache save/restore paths).

## NOT started

- `my-inquiries.html` page (list + modal, mirroring `my-commitments.html`).
- Car-specific fields in `my-items.html`'s item form (VIN, condition, ownership, sourcing, logbook, minimum price, consignment owner) and a "Record Sale" action wired to `owner_create_ungani_vehicle_sale()`.
- Quick Add FAB config entry for car_showroom.
- `reports.html` additions: profit per car, sales per staff, stock value, days in yard, balances owed, consignment owner payouts.
- Nia vocabulary wiring for car_showroom.
- The 11-item parity checklist (`reports/showroom-parity.md`).
- Full regression re-run specifically scoped to showroom changes (done once already as part of the general 5-suite re-run below, but the showroom-specific pieces like my-inquiries.html, Quick Add, reports, Nia still need their own test pass once built).

## Close-out verification performed before pausing

1. Car Showroom hidden from signup/business-type choices (`hidden_from_signup` flag + index.html filter) — confirmed.
2. No untested frontend code is live on Vercel — confirmed via `git status`: `client.html`, `index.html`, `ungani-business-config.js`, `ungani-stock-status.js` were all uncommitted working-tree changes until this commit; nothing has been pushed yet.
3. Stock-status guard proven side-effect-free for other business types: deductive code proof (guard is one boolean check, always false for non-car_showroom tenants) + live Playwright smoke-test on Billy Logistics confirming correct stock-status rendering post-change.
4. All 5 existing regression suites re-run: 45/47 scenarios PASS (2 pre-existing test-script staleness failures unrelated to showroom work, flagged for the final regression pass), partner-payout verification 6/6 PASS.
5. This file + all showroom SQL/JS/HTML changes committed.

## Resuming next week

Pick up at `my-inquiries.html` (task queue item: build UI + dashboard + reports + Nia), then the parity checklist, then the full regression + final 10-line report.
