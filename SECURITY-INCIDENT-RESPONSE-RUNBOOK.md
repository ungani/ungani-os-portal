# UNGANI OS - Security Incident Response Runbook

Internal operational procedure - not client-facing. `privacy.html` Section 7 ("Data Breach Notification") is the short, public-facing commitment this runbook exists to fulfil. This document is the actual step-by-step process; keep the two in sync if either changes.

## 1. What counts as an incident

Any event that exposes, corrupts, or makes unavailable data that shouldn't be, including:
- A confirmed cross-tenant data leak (a bug that let one business see another's data)
- Unauthorized access to a client or admin account
- A leaked credential (Supabase service-role key, VAPID private key, SMTP credentials, M-Pesa Daraja secret)
- A sub-processor (Supabase, Vercel, Google, Safaricom, the SMTP provider) reporting a breach that plausibly affects UNGANI data
- Accidental permanent data loss affecting more than one tenant

A bug that is caught and fixed before any real data was exposed (e.g. found via code review, or a security-hardening pass like this session's permission-enforcement work) is **not** an incident requiring notification - it's a fix. The line is whether real data was actually accessed or exposed, not whether a vulnerability existed.

## 2. How an incident is likely to be detected

- The passive error monitoring system (`app_error_log`, `admin-error-log.html`) surfacing an anomalous pattern
- `ungani_audit_log` showing access that doesn't match any legitimate session (e.g. a login from an unrecognized pattern, a permission change nobody made)
- A client or admin report via `my-support.html` / `admin.html`'s chat panel / info@ungani.com
- A Supabase, Vercel, Google, or Safaricom security notification
- Manual discovery during a security review (as happened multiple times this session - the staff-permission-enforcement gap, the tenant-owner `user_metadata` trust bug, the cross-tenant notification leak)

## 3. Immediate response (first 24 hours)

1. **Contain.** If the cause is a live bug, ship the fix immediately (this session's own pattern: find, fix same-day, verify live). If the cause is a leaked credential, rotate it immediately in the Vercel environment variables and Supabase dashboard.
2. **Assess scope.** Query `ungani_audit_log` and the affected table(s) directly to determine: which tenant(s), which records, what data fields, over what time window. Do not guess - pull the real rows.
3. **Preserve evidence.** Do not delete or modify the affected rows before the scope assessment is complete. If the fix requires changing the data, snapshot it first (e.g. `select * into` a temp table, or export via CSV).
4. **Classify severity:**
   - **Low** - a single tenant, non-sensitive fields (e.g. a display bug that showed a stale value), no evidence of external access.
   - **Medium** - a single tenant, sensitive fields (financial records, personal data), or multiple tenants with non-sensitive exposure.
   - **High** - multiple tenants with sensitive data exposed, or any confirmed unauthorized access (not just a theoretical vulnerability).
   - **Critical** - platform-wide exposure, or a leaked credential with confirmed misuse.

## 4. Notification timeline

- **Office of the Data Protection Commissioner (ODPC):** within **72 hours** of becoming aware, for any incident classified Medium or above. Kenya's Data Protection Act, 2019 sets this as a hard deadline from the moment of awareness, not from the moment of full investigation - if the full scope isn't known within 72 hours, notify with what's known and follow up.
- **Affected Clients:** without undue delay, for any incident classified High or Critical, or where the affected Client's own customers/employees are impacted (since the Client is the data controller for that data and has their own notification duty to their customers - UNGANI's job is to give them what they need to meet it, per privacy.html Section 7).
- **Internal:** whoever is running point on the fix should note the incident in this session's memory system (or successor) the same way every other bug this session was documented - what happened, root cause, what was fixed, so the next person (human or AI) doesn't have to rediscover it.

## 5. Notification content (minimum)

- What happened, in plain language
- What data was affected (categories, not necessarily a full row dump)
- Which tenant(s)/individuals are affected, where known
- What's been done to contain it and prevent recurrence
- What the recipient should do, if anything (e.g. "no action needed" vs "consider rotating your password")

## 6. Sub-processor incidents

If Supabase, Vercel, Google, Safaricom, or the SMTP provider notifies UNGANI of an incident on their end, treat it exactly as if discovered internally - same severity classification, same clock starts from when UNGANI became aware (not from when the sub-processor's own incident began).

## 7. Post-incident

- Fix the root cause, not just the symptom (this session's established discipline - e.g. the missing-grant bug class was traced to a systemic pattern, not patched table-by-table each time it recurred).
- Update this runbook if the incident revealed a gap in the process itself.
- If the incident is the kind that should change how future features are built (e.g. the server-side permission-enforcement gap found during Approvals testing), record that as a standing lesson, not just a one-off fix.
