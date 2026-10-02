# Step 4: Dashboard Restructure — Complete

All 19 business-type dashboards now carry the 5 new shared sections (Money today/month, Owed to You,
Stock-or-Availability where real data supports it, My To-Do, Recent Activity) in the approved order,
with staff permission gating and bilingual (EN/SW) labels on every new card.

## What was genuinely missing and built

1. **Money (today + this month)** - `calculateMoneyTodayAndMonth()`. No "today" total existed
   anywhere before this - only month-over-month comparisons.
2. **Owed to You** - `calculateOwedToYou()`. Invoices were already loaded (`dashboardData.invoices`)
   but only ever fed the health score, never rendered. Reuses the same RPC
   (`get_my_ungani_customer_invoices`) and balance/overdue logic `my-debtors-payables.html` uses.
3. **Stock card, generalized** - `calculateStockCardData()`. Same `UnganiStockStatus` rule, usable by
   any type's items.
4. **Availability card, generalized + flexible** - `calculateAvailabilityCardData()` supports 2 or 3
   buckets, with a per-type `classify()` function. Built to **skip the 3rd card rather than show an
   invented always-zero number** when a type's real data only distinguishes 2 states.
5. **My To-Do** - real task rows with tick-to-complete + quick-add, not just a count. Staff are
   scoped to their own tasks via `assigned_to_team_member_id` (the same field `my-tasks.html`'s own
   "My Tasks Only" filter matches against); owners see the team's.

**Staff permission gating** (new this pass): `currentUserPermissions` is now captured from
`get_my_ungani_staff_access()`'s `permissions` object (it was fetched before but never read beyond
`is_owner`/`branch_id`/`team_member_id`). `canViewDashboardSection(sectionKey)` reuses the exact same
`money`/`items`/`tasks` section keys `staff-permission-guard.js` already gates the real pages with -
a staff member who can't open My Money/My Items/My Tasks now also doesn't see that card on the
dashboard. Owners always pass.

**Swahili**: every new card title and label carries an inline "English / Swahili" pair (e.g. "Today
/ Leo", "Overdue / Limechelewa") - the same ad-hoc bilingual pattern already used for the Payment
Instructions note, since no app-wide i18n system exists yet.

## Full rollout table

| Business type | Money | Owed to You | Stock | Availability | My To-Do | Recent Activity |
|---|---|---|---|---|---|---|
| Generic (unmatched types) | ✅ | ✅ | ✅ | — | ✅ | ✅ (pre-existing) |
| Logistics | ✅ | ✅ | N/A¹ | N/A¹ | ✅ | ✅ (new) |
| Real Estate — Sales | ✅ | ✅ | — | ✅ Available/Reserved/Sold | ✅ | ✅ (new) |
| Real Estate — Rentals | ✅ | ✅ | — | ✅ Vacant/Occupied (2-bucket)² | ✅ | ✅ (new) |
| Retail | ✅ | ✅ | ✅ | — | ✅ | ✅ (new) |
| Hospitality — Rooms | ✅ | ✅ | — | ✅ Vacant/Occupied (2-bucket)² | ✅ | ✅ (new) |
| Hospitality — F&B | ✅ | ✅ | ✅ | — | ✅ | ✅ (new) |
| Warehouse | ✅ | ✅ | — | ✅ Vacant/Occupied (2-bucket)² | ✅ | ✅ (new) |
| Automotive | ✅ | ✅ | N/A³ | N/A³ | ✅ | ✅ (new) |
| Healthcare | ✅ | ✅ | N/A³ | N/A³ | ✅ | ✅ (new) |
| Salon/Barber/Spa/Beauty | ✅ | ✅ | N/A³ | N/A³ | ✅ | ✅ (new) |
| Events/Catering | ✅ | ✅ | N/A³ | N/A³ | ✅ | ✅ (new) |
| School | ✅ | ✅ | N/A³ | N/A³ | ✅ | ✅ (new) |
| Security | ✅ | ✅ | N/A³ | N/A (your call) | ✅ | ✅ (new) |
| Wholesale | ✅ | ✅ | ✅ | — | ✅ | ✅ (new) |
| Tourism | ✅ | ✅ | N/A³ | N/A³ | ✅ | ✅ (new) |
| Gym | ✅ | ✅ | N/A³ | N/A³ | ✅ | ✅ (new) |
| Printing | ✅ | ✅ | N/A³ | N/A³ | ✅ | ✅ (new) |
| Cleaning | ✅ | ✅ | N/A³ | N/A³ | ✅ | ✅ (new) |
| Construction | ✅ | ✅ | N/A³ | N/A³ | ✅ | ✅ (new) |
| Photography | ✅ | ✅ | N/A³ | N/A³ | ✅ | ✅ (new) |
| Furniture | ✅ | ✅ | N/A³ | N/A³ | ✅ | ✅ (new) |

¹ Logistics vehicles have no `business_items.property_status` tracking at all - vehicle maintenance
is a *task*, not an item status. Building "Available/On trip/Under maintenance" would have meant
inventing a field that doesn't exist. Flagged rather than faked.
² Your spec asked for a 3rd bucket on these (maintenance / cleaning / out-of-order) - none of these
states are actually tracked in the current data (only an occupied-vs-not status exists), so the
card shows 2 real buckets instead of 3 invented ones.
³ No `business_items` status or quantity tracking exists for this type's items at all (confirmed via
code, not assumed) - Healthcare, Automotive, Salon, Events, Tourism, Photography track **people**
(doctors/vehicles/specialists/guides/creative team), not stock or asset status. Construction has a
binary active/inactive project flag, not an on-site/available/maintenance split. Showing a card here
would mean inventing data these types don't have.

**"Car showroom" / "showrooms" does not exist as a business type anywhere in the codebase** -
confirmed via a full search of the business-type config. Automotive's only real sub-types are Car
Wash, Car Hire, and Repair Shop (Car Hire already has its own vehicle-availability ratio KPI,
unrelated to this rollout). If a car-showroom vertical is something you want, it needs to be built
as a new type first (see the "Business-type decision: Car Showroom" item already in the backlog) -
it can't be retrofitted onto Automotive without inventing the underlying data.

## Verified

- **Live against Billy Logistics' real database** (not code review): Money today/month, Owed to You
  totals, and My To-Do's overdue count all cross-checked by hand against raw table rows and matched
  exactly (see the reconciliation note given earlier in this conversation for the Money figure).
- **All 19 insertion points verified by direct file read** after a positional-insertion bug (new
  sections initially landed inside the wrong `<section>` wrapper) was caught and fixed with a
  targeted regex pass, then re-confirmed on representative samples (Property, Hospitality,
  Wholesale, Warehouse, generic).
- **Syntax-checked** after every edit (`node --check` against the extracted inline script) - zero
  errors across the full rollout.
- **Deployed and confirmed live** via curl against production.

## Not verified (sandbox limitation, unchanged from the first pass)

- No physical-device/browser rendering check - this sandbox cannot run a browser. Responsive
  behavior relies on the pre-existing `.kpi-grid` breakpoints already proven elsewhere in the app.
- Live-DB cross-check was done for Billy Logistics only, not for a demo tenant per remaining
  cluster - the calculation functions are identical to the ones already proven against real data,
  but a visual pass on a Real Estate/Hospitality/Wholesale tenant would still be worth doing when a
  browser-capable environment is available.
