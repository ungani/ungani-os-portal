# Batch 1: Finish Billing

## 1. S12 partner_code fix — CONFIRMED (done in the prior turn)
Final test run: **19 PASS, 0 FAIL, 1 SKIPPED** (S11 confirmed architecturally unreachable by
schema). This was already reported in `reports/item-1.md`.

## 2. Front end (package page, payment screen, gold hover, banner links) — CONFIRMED SHIPPED
All four were built, committed, and deployed in the prior turn (commit `9d44141`). Deployment was
verified via curl (old form gone, new RPC wiring present) and a live API-level test against
production as Billy Logistics (real pending payment created with the correct amount). Full detail
in `reports/item-1.md`.

## 3. Payment Instructions panel — STOPPING per your rule
`PAYMENT_INSTRUCTIONS_READY` is `false` in the deployed `my-billing.html` - confirmed live that no
placeholder text (`REPLACE_MPESA_ACCOUNT_NUMBER` / `REPLACE_EQUITY_ACCOUNT_NUMBER`) is served. I
need:
- The real M-Pesa Paybill 247247 **account number** to use.
- The real **Equity Bank account number** (and confirm "UNGANI OS" is still the correct account
  name).

I will not flip the flag or deploy until I have both.

## 4. Launch page notification count — BUG CONFIRMED LIVE, fix needs one query
Pulled both numbers directly from production as admin:
- Launch page (`get_admin_ungani_launch_dashboard_snapshot_fast`) shows **`unread_notifications: 921`**.
- The real `ungani_notifications` table (the exact same table/column `admin-notifications.html`
  itself queries) currently has **874 unread** out of **959 total rows**.

921 doesn't match either number, so the Launch card is reading something stale or wrong - but I
can't safely rewrite a function I haven't seen (this is the same "never extend from a guessed
body" rule that's bitten this project twice before). One query to unblock it:

```sql
select pg_get_functiondef(oid) as definition
from pg_proc
where proname = 'get_admin_ungani_launch_dashboard_snapshot_fast'
  and pronamespace = 'public'::regnamespace;
```

I'll fix it the moment I have that back - this isn't a money change, so I won't wait on it to keep
moving through the rest of the plan; I'll just come back and patch it in a later batch once I have
the body.

## 5. Failed email report (read-only, pulled live)

**183 failed emails right now** (not 166 - that number has grown since you last checked; pulled
fresh via direct query as admin, not an estimate).

**The single most important finding: all 183 failures share the exact same error** -
`Message failed: 550 Message discarded as high-probability spam`. This is one root cause (your
outbound mail relay/sender reputation being flagged by recipient servers), not 183 separate
problems.

By type: `registration_received` (32), `registration_received_client` (26),
`registration_received_admin` (25), `trial_ended` (19), `trial_warning_week` (18),
`trial_warning` (16), `team_invitation` (16), `registration_approved_client` (10),
`registration_approved` (8), `task_assignment` (5), `trial_suspended` (3),
`registration_rejected_client` (2), `record_comment` / `payment_proof_review_client` /
`payment_proof_uploaded_admin` (1 each).

By recipient domain: `ungani-test.local` (62, test fixtures), `example.com` (51, test/diagnostic
addresses), `gmail.com` (41, **real**), `ungani.com` (27, your own admin notification address),
`ungani-branchtest.local` (1, test), `icloud.com` (1, **real**).

**Real (non-test) clients affected: 11 tenants** - Demo Dyar Properties, Utumishi Co, BATOZ MUSIC
ENT, Mr. Schalie, Claudia, DENWILL BUILDERS LIMITED, Manu enterprices, St Mary School, St Michael
Bookshop, RAKULA AGENCY LTD, Pwani Motors. Every one of the other 23 affected tenants is a labeled
test/demo record (`- DELETE ME` or clearly diagnostic names).

Failures span 2026-07-12 through 2026-10-02 (today) - this is ongoing, not a one-time blip; the
most recent failure was 40 minutes before this report.

**Recommendation** (not actioned - this was a read-only report): since every failure is the same
spam-rejection error, the fix is almost certainly on the sending side (SPF/DKIM/DMARC alignment,
sender reputation, or the relay's "From" address) rather than anything in this app's code - worth
raising with whoever manages the SMTP/email-sending service before any more client-facing emails
(registration confirmations, trial warnings, team invites) are silently lost. I can investigate the
sending configuration itself as a follow-up item if you want it added to the plan.

---

**Next**: moving into Batch 2 (Paybill/Till production readiness) investigation now. Per your rule,
I'll stop and give you the SQL for review before running anything - I won't execute money-touching
changes without that checkpoint.
