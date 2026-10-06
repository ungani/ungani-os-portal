# Partner Referral System — End-to-End Check

**Date:** 2026-10-06
**Method:** Live `pg_get_functiondef`/`pg_policies`/`pg_indexes` pulls (no guessing from file source), repo-wide grep for frontend callers and for any refund mechanism, then one combined rolled-back SQL test (`begin; ... rollback;`, zero rows persisted) exercising the real RPCs end to end: `admin_create_ungani_partner`, `resolve_ungani_partner_code`, `get_my_ungani_partner_access`, `set_ungani_subscription_period_from_payment`, `admin_preview_ungani_partner_payouts`, `admin_process_ungani_partner_payouts`, `get_my_ungani_partner_dashboard`, `admin_get_ungani_partners_overview`. No fixes applied — check and test only, per instruction. No real emails sent.

## Scope covered

Partner invite email, partner signup/login, partner-facing page, referral link + tenant-tie mechanism, commission creation on full/partial payment and on a disabled partner, payout recording, partner-side numbers, admin-side numbers, partner RLS isolation, `is_test` exclusion, upgrade/downgrade/refund handling.

## WORKS (live-tested, all PASS)

1. **Partner creation + code generation** (`admin_create_ungani_partner`) — unique, collision-safe codes generated correctly.
2. **Referral code resolution** (`resolve_ungani_partner_code`) — active code resolves to the right partner; a `disabled` partner's code correctly resolves to `NULL` (cannot be used for new signups).
3. **Partner signup/login auto-link** (`get_my_ungani_partner_access`) — on first login, a partner row with a matching email and no `auth_user_id` is automatically linked to the logging-in user.
4. **Referral → tenant tie** — `tenants.referred_by_partner_id` persists correctly; separately confirmed via its live body that `approve_ungani_registration()` coalesces this field from `registrations` into `tenants` on both the insert and update branches.
5. **Commission creation on payment** — first full payment creates exactly one `onboarding` commission (30% of period price); a second full payment creates a `monthly` commission (2% of period price) without duplicating the onboarding row; a partial payment correctly creates **no** commission and leaves the subscription in `partial` state. All amounts matched the exact expected formula.
6. **Disabled-partner gating** — a referral tied to a `disabled` partner never earns a commission, even on a full payment.
7. **Admin payout preview + process** (`admin_preview_ungani_partner_payouts`, `admin_process_ungani_partner_payouts`) — preview shows the correct owed total and breakdown; process creates a `partner_payouts` row with the correct total, flips both commissions to `paid`, leaves zero `owed` remaining. This is also the second time this money-mutating function has ever run (the first was last session's fix-verification test) — still correct.
8. **Partner dashboard** (`get_my_ungani_partner_dashboard`) — returns the partner's own tenant, commissions, and payout with matching totals.
9. **RLS isolation** — querying `partner_commissions` as Partner A returns 0 rows for Partner B and the correct own rows for A.
10. **Admin overview** (`admin_get_ungani_partners_overview`) — includes the partner with correct aggregate totals.
11. **Commission infra integrity** — the two partial unique indexes the commission code's `ON CONFLICT` clauses depend on (`uq_partner_commissions_onboarding`, `uq_partner_commissions_monthly_payment`) do exist live, so the "silent failure via missing index" risk flagged during code recon does not apply.

## BROKEN

1. **`is_test` tenants are NOT excluded from commissions.** A test tenant with `is_test = true` and a real referral still generated a real, payable commission in this test. Root cause: `is_test` doesn't exist as a column on `partners` or `partner_commissions` at all, and the commission-creation block inside `set_ungani_subscription_period_from_payment()` never checks `tenants.is_test` either. Any demo/test tenant referred by a partner will pay that partner for real.
2. **No partner invite email.** `admin_create_ungani_partner()` has no `ungani_email_queue` insert anywhere in its body — confirmed via the live function definition. The admin must manually copy the referral link from a toast and send it themselves.

## MISSING

1. **No partner-facing login or dashboard page exists anywhere in the app.** Confirmed via repo-wide grep: zero `.html`/`.js` files call `get_my_ungani_partner_access()` or `get_my_ungani_partner_dashboard()`; `login.html` has no partner tab; there is no `partner.html`/`partner-dashboard.html` file. A partner cannot log in and see their own numbers even though the backend fully supports it (points 3, 8, 9 above all work in isolation).
2. **No refund/clawback mechanism.** Confirmed via repo-wide grep: no function with "refund" in its name exists anywhere in `sql/`. There is no way for UNGANI to reverse or claw back a commission after a client refund — once paid, a commission tied to a refunded payment stays payable/paid forever.
3. **Upgrade/downgrade mid-period commission math not independently re-tested this pass** — confirmed via code read only: the `v_package_changed_mid_period` branch recomputes the period price at the new package before commissioning, reusing the exact formula already live-tested above (not price-specific), so no separate bug is expected, but it was not separately exercised live in this round.

## Not re-tested (already verified in the prior session)

The underlying column-mismatch bug in these three functions (`commission_amount`→`amount`, missing `paid_at`) was already fixed and live-verified last session — this check exercised the *fixed* versions and found them correct (see WORKS #7–9 above).
