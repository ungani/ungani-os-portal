-- Ways to test the Reply-To/HTML/softer-copy deliverability fix
-- (commit 2a48984) now that the queue is empty.
--
-- Recommended primary test: STEP 2 below, a single fresh email
-- addressed to your own inbox. This directly exercises the new code
-- path with zero risk - no stale content, no real client involved, and
-- you can immediately check whether it landed in Inbox vs Spam.
--
-- The 10 failed rows (STEP 1) are a secondary option, but worth
-- reviewing before retrying rather than bulk-retrying blindly: several
-- days have passed since they were queued, and if any are
-- trial_warning type, the same staleness problem from the original
-- cleanup (sql/email-queue-stale-cleanup.sql) applies again - the "ends
-- in X days" count baked into the message is now even more likely
-- wrong than it was then. STEP 1 shows exactly what they are so you can
-- decide per-row.

-- STEP 1 (read-only) - review the 10 failed rows before deciding
-- whether to retry any of them.
select id, recipient_email, email_type, created_at, now() - created_at as age,
       send_attempts, last_error
from ungani_email_queue
where send_status = 'failed'
order by created_at asc;

-- STEP 2 (recommended) - insert one fresh test email addressed to your
-- own inbox. Includes a "Label: https://..." trailing line so you can
-- visually confirm the new HTML button-rendering, not just plain text.
-- Safe to run as-is - replace the recipient_email if you'd rather use a
-- different inbox to check.
insert into ungani_email_queue (
  recipient_email, recipient_name, email_subject, email_body, email_type,
  send_status, created_at
) values (
  'billychris617@gmail.com',
  'UNGANI Deliverability Test',
  'UNGANI OS - deliverability test email',
  'Hi there,' || chr(10) || chr(10) ||
  'This is a one-off test confirming the Reply-To header, HTML formatting, and softer copy fixes are working.' || chr(10) || chr(10) ||
  'If this arrived in your inbox (not spam) with proper UNGANI branding instead of plain text, the fix worked.' || chr(10) || chr(10) ||
  'View your dashboard: https://ungani-os-portal.vercel.app/client.html' || chr(10) || chr(10) ||
  '- UNGANI OS Team',
  'deliverability_test',
  'pending',
  now()
);

-- STEP 3 (optional, your choice) - retry specific failed rows, AFTER
-- reviewing Step 1's output. Fill in only the IDs you actually want to
-- retry - deliberately not a blanket "retry all 10", since some may now
-- be stale (see note above).
--
-- update ungani_email_queue
-- set send_status = 'pending', send_attempts = 0, last_error = null
-- where id in ('<id-from-step-1>', '<another-id>');
