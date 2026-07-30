-- UNGANI OS: approval confirmation email (Part 2 of 2).
-- Run this once in the Supabase SQL editor.
--
-- This is CREATE OR REPLACE on the EXISTING approve_ungani_registration
-- function (the user pasted its real, current source - captured verbatim
-- below except for the additions marked with "-- NEW:"). Nothing about
-- the existing tenant/user/section-provisioning logic changes - only
-- two additions:
--
--   1. The approval_message text that was already being built inline in
--      the final `return` is now built once into v_approval_message and
--      reused - so the emailed text and the on-screen "Copy" text box
--      text can never drift apart.
--   2. Right before that return, it queues the same message into
--      ungani_email_queue (same table/pipeline as the registration
--      confirmation email and the trial-warning emails) so the client
--      gets it automatically, instead of relying solely on the admin
--      manually clicking "Copy" and pasting it somewhere themselves.
--
-- Design notes:
--   - Best-effort, non-blocking: the queue insert is wrapped in its own
--     BEGIN/EXCEPTION sub-block, which creates an implicit savepoint in
--     plpgsql. If the insert fails for any reason, it's caught locally
--     (RAISE WARNING, visible in Postgres logs) and swallowed - it can
--     NEVER cause the outer transaction (tenant creation, user linking,
--     section provisioning, registration status update) to roll back.
--     A real client account being approved must never fail because of
--     an email queue insert.
--   - Idempotent: guarded the same way as the registration confirmation
--     email - if a 'registration_approved' email is already queued for
--     this registration_id, does nothing. Matters here because this
--     function does not itself check registration status before running,
--     so a retried/duplicate RPC call is possible and must not queue two
--     approval emails to the same client.
--   - tenant_id is set to the real, now-known v_tenant_id (unlike the
--     registration confirmation email, which had none yet).
--   - The "Copy" button in admin.html is UNCHANGED and stays as a manual
--     backup - this only adds the automatic send on top of it.
--   - Delivery timing: unlike the registration confirmation email (next
--     cron run, up to 24h), admin.html is being separately updated to
--     POST to /api/send-email-queue immediately after a successful
--     approval, using the admin's own live session - so this email sends
--     within seconds in the normal case, with the cron as a fallback if
--     that immediate send fails for any reason.

CREATE OR REPLACE FUNCTION public.approve_ungani_registration(p_registration_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'auth'
AS $function$
declare
  r record;
  v_tenant_id uuid;
  v_admin_id uuid;
  v_business_type_id uuid;
  v_business_type_key text;
  v_business_type_name text;
  v_business_name text;
  v_contact_person text;
  v_slug text;
  v_enabled_sections integer := 0;
  v_recipient_email text; -- NEW
  v_approval_message text; -- NEW
begin
  v_admin_id := auth.uid();

  if v_admin_id is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'You must be logged in as admin to approve registrations.'
    );
  end if;

  if not public.is_ungani_admin() then
    return jsonb_build_object(
      'ok', false,
      'message', 'Only UNGANI admin can approve registrations.'
    );
  end if;

  select *
  into r
  from public.registrations
  where id = p_registration_id
  for update;

  if not found then
    return jsonb_build_object(
      'ok', false,
      'message', 'Registration was not found.'
    );
  end if;

  if r.auth_user_id is null then
    return jsonb_build_object(
      'ok', false,
      'message', 'This registration has no login user/password. Ask the client to register again using the updated registration form.'
    );
  end if;

  v_business_name := coalesce(r.business_name, r.company_name, 'Client Business');
  v_contact_person := coalesce(r.contact_person, r.contact_name, r.full_name, 'Client Contact');
  v_business_type_id := r.business_type_id;
  v_business_type_key := coalesce(r.business_type_key, 'general_business');
  v_business_type_name := coalesce(r.business_type, 'General Business');

  if v_business_type_id is null and v_business_type_key is not null then
    select id, coalesce(business_type_key, slug), coalesce(business_type_name, type_name, name)
    into v_business_type_id, v_business_type_key, v_business_type_name
    from public.business_types
    where lower(coalesce(business_type_key, '')) = lower(v_business_type_key)
       or lower(replace(coalesce(slug, ''), '-', '_')) = lower(v_business_type_key)
    limit 1;
  end if;

  if v_business_type_id is null and r.business_type is not null then
    select id, coalesce(business_type_key, slug), coalesce(business_type_name, type_name, name)
    into v_business_type_id, v_business_type_key, v_business_type_name
    from public.business_types
    where lower(coalesce(business_type_name, type_name, name, '')) = lower(r.business_type)
    limit 1;
  end if;

  v_business_type_key := coalesce(v_business_type_key, 'general_business');
  v_business_type_name := coalesce(v_business_type_name, r.business_type, 'General Business');

  v_slug :=
    lower(regexp_replace(v_business_name, '[^a-zA-Z0-9]+', '-', 'g'))
    || '-'
    || left(p_registration_id::text, 8);

  v_tenant_id := r.tenant_id;

  if v_tenant_id is null then
    insert into public.tenants
    (
      business_name,
      company_name,
      name,
      slug,
      business_type_id,
      business_type_key,
      business_type,
      contact_person,
      business_email,
      business_phone,
      business_location,
      business_description,
      selected_sections,
      account_status,
      status,
      created_at,
      updated_at
    )
    values
    (
      v_business_name,
      v_business_name,
      v_business_name,
      v_slug,
      v_business_type_id,
      v_business_type_key,
      v_business_type_name,
      v_contact_person,
      coalesce(r.email, r.contact_email),
      coalesce(r.phone, r.contact_phone),
      coalesce(r.location, r.business_location),
      coalesce(r.registration_notes, r.notes),
      r.selected_sections,
      'trial',
      'trial',
      now(),
      now()
    )
    returning id into v_tenant_id;
  else
    update public.tenants
    set
      business_name = v_business_name,
      company_name = v_business_name,
      name = v_business_name,
      slug = coalesce(slug, v_slug),
      business_type_id = v_business_type_id,
      business_type_key = v_business_type_key,
      business_type = v_business_type_name,
      contact_person = v_contact_person,
      business_email = coalesce(r.email, r.contact_email),
      business_phone = coalesce(r.phone, r.contact_phone),
      business_location = coalesce(r.location, r.business_location),
      business_description = coalesce(business_description, r.registration_notes, r.notes),
      selected_sections = r.selected_sections,
      account_status = 'trial',
      status = 'trial',
      updated_at = now()
    where id = v_tenant_id;
  end if;

  insert into public.users
  (
    id,
    email,
    full_name,
    tenant_id,
    role,
    status,
    preferred_theme,
    preferred_language,
    created_at,
    updated_at
  )
  values
  (
    r.auth_user_id,
    coalesce(r.email, r.contact_email),
    v_contact_person,
    v_tenant_id,
    'client',
    'active',
    'light',
    'en',
    now(),
    now()
  )
  on conflict (id) do update
  set
    email = excluded.email,
    full_name = excluded.full_name,
    tenant_id = excluded.tenant_id,
    role = 'client',
    status = 'active',
    updated_at = now();

  insert into public.tenant_sections
  (
    tenant_id,
    business_section_id,
    section_id,
    is_enabled,
    enabled,
    created_at,
    updated_at
  )
  select
    v_tenant_id,
    bs.id,
    bs.id,
    true,
    true,
    now(),
    now()
  from public.business_sections bs
  where
    (
      (
        v_business_type_id is not null
        and bs.business_type_id = v_business_type_id
      )
      or
      (
        v_business_type_id is null
        and lower(coalesce(bs.section_key, '')) in (
          'money',
          'records',
          'documents',
          'tasks',
          'items_assets_stock',
          'people',
          'calendar',
          'support',
          'reports'
        )
      )
    )
    and not exists (
      select 1
      from public.tenant_sections ts
      where ts.tenant_id = v_tenant_id
        and (
          ts.section_id = bs.id
          or ts.business_section_id = bs.id
        )
    );

  get diagnostics v_enabled_sections = row_count;

  update public.registrations
  set
    tenant_id = v_tenant_id,
    business_type_id = v_business_type_id,
    business_type_key = v_business_type_key,
    business_type = v_business_type_name,
    business_name = v_business_name,
    company_name = v_business_name,
    contact_person = v_contact_person,
    contact_name = v_contact_person,
    full_name = v_contact_person,
    email = coalesce(email, contact_email),
    contact_email = coalesce(contact_email, email),
    phone = coalesce(phone, contact_phone),
    contact_phone = coalesce(contact_phone, phone),
    location = coalesce(location, business_location),
    business_location = coalesce(business_location, location),
    status = 'approved',
    approved_at = now(),
    approved_by = v_admin_id,
    updated_at = now()
  where id = p_registration_id;

  -- NEW: build the approval message once, reused for both the queued
  -- email and the returned/"Copy" text, so they can never drift apart.
  v_recipient_email := coalesce(r.email, r.contact_email);
  v_approval_message :=
    'Hi ' || v_contact_person || E',\n\n' ||
    'Your UNGANI OS demo account for ' || v_business_name || E' has been approved.\n\n' ||
    'You can now log in here:\n' ||
    'https://ungani-os-portal.vercel.app/client.html' || E'\n\n' ||
    'Please use the same email and password you created during registration.' || E'\n\n' ||
    'Regards,' || E'\n' ||
    'UNGANI' || E'\n' ||
    'info@ungani.com';

  -- NEW: queue the approval email. Wrapped so any failure here (bad
  -- email address, table hiccup, etc.) can never roll back a real,
  -- already-completed approval.
  if v_recipient_email is not null then
    begin
      if not exists (
        select 1 from public.ungani_email_queue
        where email_type = 'registration_approved'
          and related_table = 'registrations'
          and related_id = p_registration_id
      ) then
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
          v_tenant_id,
          v_recipient_email,
          v_contact_person,
          'Your UNGANI OS account has been approved',
          v_approval_message,
          'registration_approved',
          'registrations',
          p_registration_id,
          'pending',
          now()
        );
      end if;
    exception
      when others then
        raise warning 'Could not queue approval email for registration %: %', p_registration_id, sqlerrm;
    end;
  end if;

  return jsonb_build_object(
    'ok', true,
    'message', 'Registration approved successfully. The client can now log in using the email and password created during registration.',
    'tenant_id', v_tenant_id,
    'auth_user_id', r.auth_user_id,
    'business_name', v_business_name,
    'email', coalesce(r.email, r.contact_email),
    'login_url', 'https://ungani-os-portal.vercel.app/client.html',
    'enabled_sections_added', v_enabled_sections,
    'approval_message', v_approval_message
  );
end;
$function$;
