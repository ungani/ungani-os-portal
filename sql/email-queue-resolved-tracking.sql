-- Adds a non-destructive "closed" marker for old failed email_queue rows
-- so they stop permanently inflating admin-email-queue.html's Failed
-- count, without deleting or altering send_status/last_error (full
-- audit trail preserved). Marks the 166 pre-Resend-switch failures
-- resolved now; anything failing after the switch (there have been
-- none so far) stays unresolved until reviewed.

begin;

alter table public.ungani_email_queue
  add column if not exists resolved_at timestamptz,
  add column if not exists resolution_note text;

update public.ungani_email_queue
set resolved_at = now(),
    resolution_note = 'Pre-Resend-switch batch failure (SMTP reputation rejection) - reviewed 2026-10-07.'
where send_status = 'failed'
  and created_at < '2026-10-02 08:20:30+00'
  and resolved_at is null;

select count(*) as rows_marked_resolved
from public.ungani_email_queue
where resolved_at is not null;

commit;
