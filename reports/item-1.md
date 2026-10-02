# Item 1: Subscription Billing Overhaul + Payment Instructions Panel

Status: **SHIPPED + DEPLOYED**. Backend fully live-tested (19/19 automated scenarios + 1
architecturally-unreachable case confirmed by code review). Front end deployed and spot-verified
live against production; full interactive browser testing was not possible in this environment
(see "Not verified" below) and should get one manual pass.

## What changed

### Database (`sql/item1-subscription-billing-fix-v2.sql`, run by Chris; follow-up constraint
fix run separately to add `'refunded'` to `ungani_payments.payment_status`)

- **Pricing**: `calculate_ungani_subscription_amount(tenant_id, package_key_override)` is now the
  single source of truth for price (package price for the billing cycle + branch add-on, rounded
  to whole KES). A payment's "period due" is always priced for *that payment's own package*, never
  the tenant's current package - this was the original bug (an upgrade payment used to be priced
  like a renewal of the old package).
- **Mid-period package switch**: new `ungani_subscriptions.period_package_key` column tracks which
  package the in-progress tracked period belongs to, separate from the subscription's active
  `package_key` - these can differ while an upgrade is still being paid off in installments. A
  payment for a different package moves whatever was paid toward the old period into
  `credit_balance_ksh` and starts the new period fresh.
- **Fully paid**: extends `floor(available/due)` periods (capped 24) from the later of now/paid_at
  and the existing end date. Package changes immediately, `user_limit` is synced from the new
  package, leftover becomes credit.
- **Partial**: no extension, `payment_status='partial'`, **package_key is never touched** - only a
  fully paid period changes it. Access stays unchanged.
- **Price unavailable**: logged to `ungani_payment_processing_failures`, payment left unapplied
  (`applied_to_subscription_at` stays null, retryable), never silently treated as paid. Confirmed
  architecturally unreachable today (package_key is CHECK-constrained to real priced packages,
  `monthly_price_ksh` is NOT NULL, `yearly_price_ksh` is a generated column) - verified by code
  review, not live execution.
- **Idempotency + concurrency**: `applied_to_subscription_at` guard, `FOR UPDATE` locks on both the
  payment and subscription rows.
- **Duplicates**: only flags against a twin that's already applied (fixes a deadlock where two
  simultaneous duplicates could both flag each other and neither apply).
  `admin_resolve_ungani_payment_duplicate`'s "apply as extra period" now verifies the apply
  actually succeeded and rolls the flag back to `pending_review` with the real error if not -
  never reports success for something that silently failed. "Mark for refund" flips the payment's
  own `payment_status` to `'refunded'`.
- **Downgrade**: scheduled on `pending_downgrade_package_key`, no payment now, no refund for the
  current period. `calculate_ungani_subscription_amount`'s own resolution prefers a pending
  downgrade over the stored package when no override is given - every caller that prices a plain
  renewal (webhook, the monthly billing-automation function, future STK renewal) inherits this for
  free, with a minimal patch applied to the live `run_ungani_create_monthly_billing_records` body.
- **New RPC `client_request_ungani_package_payment(package_key)`**: replaces the "why do you want
  to upgrade" form + admin-approval flow entirely. Decides upgrade/same-package (creates/reuses a
  pending payment with `source='package_selection'`, real price attached) vs. downgrade (schedules
  it, no payment) in one call. Auto-cancels only its own earlier no-proof pending payments -
  billing-automation or admin-created invoices are never touched.
- **Commission**: onboarding = rate × first fully-paid period's due, once. Monthly = rate × due ×
  additional periods covered by that payment, one combined row. Real `partner_commissions` columns
  (`source_payment_id`, `amount`), real `commission_type` values.
- **Grants**: `set_ungani_subscription_period_from_payment` is `service_role`-only; every
  client-facing function is `authenticated`-only; nothing is granted to `anon`/`public`.

**Test suite** (`sql/item1-subscription-billing-test.sql`): 14 named scenarios (some split into
sub-checks) run inside `BEGIN...ROLLBACK` against the real Billy Logistics tenant and real package
prices - nothing persisted. Final result: **19 PASS, 0 FAIL, 1 SKIPPED** (S11, price-unavailable,
confirmed unreachable by schema as above). Two schema facts were discovered live during this
process and are now documented here for future reference: `ungani_packages.yearly_price_ksh` is a
GENERATED column (derived from `monthly_price_ksh`), and `partners` requires `full_name` + `email`
+ `partner_code`.

### Front end

- **`my-package.html`**: the "Request a Package Change" form, "My Upgrade Requests" list, and all
  related JS (`submitUpgradeRequest`, `loadMyUpgradeRequests`, `setRequestedPackageOptions`,
  `getRequestStatusClass`) are gone. `selectTierCard(packageKey)` now calls
  `client_request_ungani_package_payment` directly and routes on the response: scheduled downgrade
  shows a toast + a persistent "Plan change scheduled" notice; upgrade/renewal redirects to
  `my-billing.html?pay=<payment_id>`. A new `loadPendingDowngradeNotice()` shows/hides that notice
  based on `get_my_ungani_billing_status`.
- **Gold hover bug** (from the earlier round): `.tier-compare-card.is-recommended`'s permanent gold
  border and the select button's `isRecommended`-only class are fixed - every card now gets the
  gold border on hover (scoped to `(hover: hover) and (pointer: fine)` so touch devices don't get
  stuck hover) and on selection.
- **`my-billing.html`**: new `?pay=<payment_id>` handling. On load, fetches that specific pending
  payment and checks `MPESA_ENV` via a `GET` on `/api/mpesa-stk-push` (no new serverless function -
  the repo is already at Vercel Hobby's 12-function cap, confirmed via the live deploy succeeding).
  Renders a summary (package/amount/period), the STK button **only** when `MPESA_ENV=production`
  (currently false - confirmed live, button correctly absent), and an "Upload Proof for This
  Payment" button wired to the existing proof-upload modal. The STK POST body now includes
  `pendingPaymentId` when present. **The actual Paybill/bank account-number panel is unchanged and
  still held back** (`PAYMENT_INSTRUCTIONS_READY = false`) pending Chris's real account numbers -
  confirmed live that no `REPLACE_*` placeholder text is served.
- **`api/mpesa-stk-push.js`**: accepts `pendingPaymentId` on initiate (trusts the pending payment's
  own package/amount instead of recalculating from the tenant's current package - this is what
  makes an STK upgrade charge the new package's price). The callback updates that same pending row
  to paid instead of inserting an orphaned second row. Added a `GET` branch for the MPESA_ENV
  check, on the same file (not a new function).
- **`admin-upgrade-requests.html`**: relabeled "(Historical)" - confirmed only 3 rows exist, all
  `rejected`, zero pending, and the update RPC never had any side effect on a tenant's real
  package, so nothing is lost by stopping new submissions here.
- **`admin-home.html` / `admin-billing.html`**: both had the same latent bug -
  `status === 'paid' || !!paid_date` counted any row with a paid_date regardless of status, so a
  refunded duplicate would never actually disappear from revenue. Fixed to exact-match
  `status === 'paid'` in both places (found while tracing "exclude refunds from revenue").
- **`nia-assistant.js`**: the "how do I pay" FAQ answer rewritten to match the new flow (was
  describing the removed request/approval steps).

## What was verified, and how

- **Database**: all 19 scenarios above, executed live against the real Billy Logistics tenant
  inside rolled-back transactions, output pasted back and reviewed round by round.
- **Deployment**: confirmed via direct `curl` against the production URL - pages return 200, the
  old upgrade-request form HTML is completely absent from the served `my-package.html`, the new
  RPC call and `pendingDowngradeNotice` element are present, and `GET /api/mpesa-stk-push` returns
  `{"ok":true,"production":false}`.
- **Live API-level test** (no browser - see below): logged in as Billy Logistics via Supabase Auth
  REST (same mechanism `login.html` uses), then called the real production RPCs with that session
  token: `get_my_ungani_billing_status` and `get_my_ungani_subscription` both work post-migration;
  `client_request_ungani_package_payment` for Billy's real current package (`business`) returned
  `action: "payment_required"` with a real `payment_id` and the correct amount (KES 17,000 = 14,000
  Business + 3,000 branch add-on for Billy's 1 billable branch, matching his real data).
  Re-calling it a second time correctly produced a NEW pending payment with the FIRST one
  cancelled - this is the by-design "cancel old, create new" behavior (net pending count stays at
  1, exactly what S14 checks), not a bug; my first draft of this ad-hoc check wrongly expected the
  *same* id to be reused and I'm flagging that it was my assertion that was wrong, not the code.

## What was NOT verified

- **Interactive browser/UI testing** (gold hover visually, the actual click → redirect →
  `my-billing.html?pay=` flow end-to-end in a browser, the rendered payment-summary panel, the
  proof-upload modal opening): **blocked** - this sandbox's Chromium build is not supported on its
  macOS version (`playwright install` fails outright: "Playwright does not support chromium on
  mac13"). Static HTML inspection and live API calls stand in for this, but a human click-through
  (or a Playwright-capable environment) is recommended before relying on this for real client
  traffic.
- Bilingual (English/Swahili) copy on the payment screen was **not built** - scope was trimmed to
  ship the core flow; can be added as a follow-up using the existing `ungani_client_lang`
  localStorage convention.
- Real Paybill/bank account numbers are still outstanding from Chris - the panel is deliberately
  inert until provided.

## Open questions / next steps

1. Please do one manual click-through of My Package → payment screen on a real device/browser to
   confirm the visual gold-hover and modal behavior match the code.
2. Give the real M-Pesa Paybill account number and Equity Bank account number whenever ready - I'll
   flip `PAYMENT_INSTRUCTIONS_READY` to `true` and deploy that one change.
3. Bilingual payment-screen copy - say the word if you want it now or later.
4. Proceeding to item 2 (Paybill/Till production readiness) per the standing order, unless you want
   to redirect.
