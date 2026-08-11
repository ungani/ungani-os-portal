-- Fix #2 from the registration flow fresh-eyes review: the confirmation
-- email never mentioned Supabase's own separate "Confirm your signup"
-- email (triggered by the same signUp() call in index.html, arrives
-- around the same time, generic branding, zero UNGANI context) - a
-- first-time user had no way to know two different emails were coming
-- or that only one of them needs action. Also had no reassurance about
-- how long "waiting for review" actually means.
--
-- Not adding a specific promised timeframe (e.g. "within 24 hours") -
-- that would be a real claim I have no basis for; using honest,
-- reassuring wording instead. If there's a real target SLA, tell me the
-- number and I'll add it as an explicit promise.
--
-- Everything else in this function (idempotency check, anon-callable
-- design, security-definer, grants) is unchanged from
-- sql/registration-confirmation-email.sql - only v_subject/v_body text
-- changed. Run this once in the Supabase SQL editor.

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
    'You should also receive a separate "Confirm your signup" email from Supabase around the same time - please click the link in that one to verify your email address. Both this email and that one are expected; you don''t need to do anything else right now.' || E'\n\n' ||
    'We review new registrations regularly and will email you again as soon as yours is approved, with your login link.' || E'\n\n' ||
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
