# Step 4: Dashboard Restructure

Status: **first real slice shipped and live-verified, not yet rolled out to all 19 types.**
Given the approved spec covers a genuine ground-up reorder of 19 bespoke, independently-built
dashboard renderers, I prioritized building the 5 genuinely-missing shared sections correctly and
proving the full 8-section pattern end-to-end on two real dashboards (the generic fallback and
Billy Logistics - real, active tenant data), rather than mechanically touching all 19 without being
able to verify each one, which risked exactly the "don't break what works" outcome this was
explicitly scoped to avoid.

## What already existed (confirmed via a dedicated research pass before touching anything)

- Greeting + "updated X min ago": `updateLastUpdatedIndicator()` already shared; greeting markup
  duplicated per type (pre-existing, not changed).
- Needs Attention: `renderAttentionGroups()` already shared, capped at 5 rows/group, already
  clickable to records. Used as-is.
- Business-specific sections: every type already follows one consistent internal shape
  (`{kpisHtml, attentionHtml, quickActionsHtml, trendMonths, ...}`). Used as-is, untouched.
- Recent Activity: `buildRecentActivity()`/`renderRecentActivity()` already existed but were wired
  into the generic fallback dashboard only - none of the 19 bespoke types showed it.
- Stock detection: `UnganiStockStatus` (via `isOutOfStockItem`/`isLowStockItem`) already existed,
  but only surfaced as a KPI on Retail and Hospitality's Food & Beverage section.

## What was genuinely missing and built new

1. **Money (today + this month)** - `calculateMoneyTodayAndMonth()`. Confirmed live: no "today"
   money total existed anywhere in the codebase before this - only month-over-month comparisons.
2. **Owed to You** - `calculateOwedToYou()`. Confirmed live: invoices were loaded into
   `dashboardData.invoices` but only ever fed the health score - never rendered as a widget
   anywhere on the dashboard. Reuses the exact same RPC (`get_my_ungani_customer_invoices`) and
   balance/overdue logic `my-debtors-payables.html` already uses - no new data source.
3. **Stock card, generalized** - `calculateStockCardData()`. Same `UnganiStockStatus` rule, now
   usable by any business type's items, not hardcoded to Retail/Hospitality.
4. **Availability card** - `calculateAvailabilityCardData()`. Confirmed still unbuilt before this
   (matches the earlier "proposed, not built" status) - generalizes the one-off occupancy helpers
   (`isOccupiedItemStatus`, `isSoldPropertyStatus`) into a 3-bucket breakdown with per-type
   vocabulary. **Built as a reusable function, not yet wired into any specific unique-asset type's
   renderer** (see "Not yet done" below).
5. **My To-Do** - `calculateMyTodoData()` + tick-to-complete + quick-add. Confirmed live: the
   dashboard previously showed only a Tasks *count* card, never actual task rows. Staff/owner
   scoping uses the same `assigned_to_team_member_id` field `my-tasks.html`'s own "My Tasks Only"
   filter already matches against - added `currentUserTeamMemberId` to the identity load since it
   wasn't captured before.

All 5 share one new CSS treatment (`.dash-section`/`.section-eyebrow`/`.todo-row`/`.todo-list`)
layered on the existing `.card`/`.kpi-grid` system - same spacing, same number format
(`formatKes()` → "Ksh 1,234"), same name-truncation rule (`truncateName()`, "…" at 26-32 chars
depending on context). `.kpi-grid` already had mobile/tablet breakpoints, so the new sections
inherit responsive behavior for free - not independently re-verified on a physical device this
pass (see "Not verified" below).

## Wired into real dashboards (live-verified)

- **Generic fallback dashboard**: all 5 new sections inserted in spec order, after the existing
  hero/attention/KPI content (left untouched).
- **Billy Logistics** (real, active tenant): Money, Owed to You, My To-Do, and Recent Activity
  (newly added - previously absent on this type) inserted in spec order around the existing
  trip-specific content, which is untouched. Stock/Availability skipped for Logistics - it's
  neither a stock-holding nor unique-asset type per your own list.

**Live-verified against Billy's real database** (not just code review) by re-running the exact
same calculation logic in a standalone script against live data pulled via the same RPCs/tables
the dashboard uses:
- Money today/month: correctly returned all-zero, because Billy's most recent transaction is
  dated 2026-09-30 and today is 2026-10-02 - confirmed against the raw transaction dates, not a
  bug.
- Owed to You: Ksh 19,300 outstanding, Ksh 12,000/1 invoice overdue - cross-checked by hand against
  the 40 raw invoice rows (correctly excluding drafts/cancelled).
- My To-Do: 5 overdue tasks - matches an independent raw-data count exactly (5 of 5).

## Not yet done (explicitly, so nothing is overstated)

- **Remaining 17 business types** (Real Estate, Retail, Hospitality, Automotive, Healthcare,
  Salon, Events, School, Security, Wholesale, Tourism, Gym, Printing, Cleaning, Construction,
  Photography, Furniture) still run their existing, unchanged dashboards - not yet reordered into
  the new 8-section layout. The 5 new shared functions are ready to use on all of them.
- **Availability card** is built and tested as a function but not wired into any specific type
  (Real Estate, Automotive showroom, Security) - each needs a short vocabulary decision
  (Vacant/Occupied/Sold vs Available/Deployed/Unavailable) before wiring.
- **Staff-scoped Money/Owed-to-You numbers**: only My To-Do is scoped to staff vs owner per your
  spec (the only place you explicitly asked for it). Money/Owed-to-You show the same numbers to
  everyone who can already see the dashboard - matches today's existing behavior for those cards,
  not a regression, but not newly staff-filtered either.
- **Swahili wording**: not added this pass - English only, same as the rest of the dashboard
  today.
- **Mobile/tablet/light-dark verification**: done by code review (existing `.kpi-grid` breakpoints
  and CSS variable usage confirmed correct), not by rendering on a physical device or browser -
  this sandbox cannot run a browser.

## Also done

- Nia: new FAQ entry (`dashboard-layout-explained`) describing the 8-section order in plain
  language.

## Recommendation

Treat this as the foundation + proof-of-pattern. The remaining 17 types are mechanical repeats of
the same insertion pattern used on Logistics (same 5 function calls, same relative position) - say
the word and I'll continue the rollout type by type, verifying each against its own real/demo
tenant before moving to the next, rather than doing all 17 in one unverified pass.
