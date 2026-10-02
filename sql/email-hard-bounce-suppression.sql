-- =====================================================================
-- Email suppression: hard-bounce memory table.
--
-- Not money-touching, so per the standing working method this doesn't
-- need a review stop - included here mainly so it's on record alongside
-- the code change that uses it (api/send-email-queue.js).
--
-- Fake/test-address suppression itself (@example.com, .local, is_test
-- tenants) needs NO schema change - send-email-queue.js checks those
-- patterns inline against data it already has (recipient_email,
-- tenant_id) and reuses the existing 'cancelled' send_status (already a
-- real value in use - confirmed live, no CHECK-constraint risk from
-- inventing a new status string).
--
-- This table is the one genuinely new piece: a durable, go-forward
-- record of addresses that have hard-bounced (mailbox doesn't exist/is
-- unavailable - a PERMANENT delivery failure), so a later resend to the
-- same address is suppressed too. Checked live: every one of the 183
-- current failures is the IDENTICAL "550 high-probability spam" error -
-- a content/reputation rejection, not an invalid-recipient bounce - so
-- this table starts empty today. It exists to catch real bounces from
-- here forward once reputation recovers and genuine invalid-recipient
-- errors (if any ever occur) become visible again.
-- =====================================================================

create table if not exists public.ungani_email_hard_bounces (
  email text primary key,
  reason text,
  bounced_at timestamptz not null default now()
);

alter table public.ungani_email_hard_bounces enable row level security;
-- No policies: this table is only ever read/written by
-- api/send-email-queue.js using the service-role key, never by a
-- client-side session. service_role bypasses RLS, so "no policies"
-- correctly means "no client access at all," not "open to everyone."

revoke all on public.ungani_email_hard_bounces from public, anon, authenticated;

-- ---------------------------------------------------------------------
-- Verification.
-- ---------------------------------------------------------------------
select
  (select count(*) from information_schema.tables
   where table_schema = 'public' and table_name = 'ungani_email_hard_bounces') as table_exists,
  (select count(*) from pg_policies
   where schemaname = 'public' and tablename = 'ungani_email_hard_bounces') as policy_count,
  (select jsonb_agg(grantee || ':' || privilege_type) from information_schema.role_table_grants
   where table_schema = 'public' and table_name = 'ungani_email_hard_bounces'
     and grantee in ('anon', 'authenticated', 'public')) as client_grants;
