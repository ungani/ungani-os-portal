-- UNGANI OS: registration confirmation email.
-- Run this once in the Supabase SQL editor.
--
-- Design notes:
--   - The ONLY anon-callable RPC being added tonight - registration
--     happens before any login, so this must be reachable by an
--     unauthenticated visitor. To keep that safe, the client only ever
--     passes back the UUID of the registration row IT JUST INSERTED
--     (via the existing, unchanged public registrations INSERT in
--     index.html) - it can never supply arbitrary recipient/subject/body
--     content. Every field in the queued email is built server-side from
--     the real registrations row, matched by that id.
--   - tenant_id is stored as null - confirmed nullable via
--     information_schema. A pending registration has no tenant yet; the
--     client/tenant account is only created on approval.
--   - Idempotent: if a confirmation email has already been queued for
--     this registration_id, does nothing and returns ok:true rather than
--     queuing a duplicate - guards against a retried/duplicate RPC call
--     (e.g. a flaky network) double-sending, independent of index.html's
--     existing pre-insert duplicate-registration check (which guards a
--     different failure mode: a full resubmission of the form).
--   - Best-effort by design: index.html calls this AFTER the real
--     registration insert already succeeded, and does not block the
--     "Registration submitted successfully" message on this call's
--     result - a failure here should never make a successful
--     registration look like it failed.
--   - Delivery timing: this queues the email; actual sending happens on
--     the existing api/send-email-queue.js cron (currently once daily -
--     Vercel Hobby plan constraint, confirmed acceptable for this
--     specific email by the user, unlike the approval email which sends
--     instantly via the admin's live session).

create or replace function public.queue_ungani_registration_confirmation_email(p_registration_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  r public.registrations;
  v_recipient_email text;
  v_recipient_name text;
  v_business_name text;
  v_subject text;
  v_body text;
begin
  select * into r from public.registrations where id = p_registration_id;

  if r.id is null then
    return jsonb_build_object('ok', false, 'message', 'Registration not found.');
  end if;

  if exists (
    select 1 from public.ungani_email_queue
    where email_type = 'registration_received'
      and related_table = 'registrations'
      and related_id = p_registration_id
  ) then
    return jsonb_build_object('ok', true, 'message', 'Confirmation email already queued.');
  end if;

  v_recipient_email := nullif(trim(r.email), '');

  if v_recipient_email is null then
    return jsonb_build_object('ok', false, 'message', 'Registration has no email on file.');
  end if;

  v_recipient_name := coalesce(nullif(trim(r.contact_name), ''), nullif(trim(r.business_name), ''), 'there');
  v_business_name := coalesce(nullif(trim(r.business_name), ''), 'your business');

  v_subject := 'We''ve received your UNGANI OS registration';
  v_body :=
    'Hi ' || v_recipient_name || E',\n\n' ||
    'Thanks for registering ' || v_business_name || ' with UNGANI OS. Your registration has been received and is now waiting for review by our team.' || E'\n\n' ||
    'We''ll email you again as soon as it''s approved, with your login link.' || E'\n\n' ||
    'Regards,' || E'\n' ||
    'UNGANI' || E'\n' ||
    'info@ungani.com';

  insert into public.ungani_email_queue (
    tenant_id,
    recipient_email,
    recipient_name,
    email_subject,
    email_body,
    email_type,
    related_table,
    related_id,
    send_status,
    created_at
  ) values (
    null,
    v_recipient_email,
    v_recipient_name,
    v_subject,
    v_body,
    'registration_received',
    'registrations',
    p_registration_id,
    'pending',
    now()
  );

  return jsonb_build_object('ok', true);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

grant execute on function public.queue_ungani_registration_confirmation_email(uuid) to anon;
grant execute on function public.queue_ungani_registration_confirmation_email(uuid) to authenticated;
