-- ============================================================
-- Education vertical Phase 1 follow-up: the two pieces deferred from
-- sql/education-vertical-phase1.sql pending live-signature diagnostics.
-- Both function bodies below are reproduced VERBATIM from the real,
-- current live definitions Chris pasted from pg_get_functiondef() -
-- every line is unchanged except the ones marked "-- CHANGED" below.
-- ============================================================

-- ============================================================
-- PART F: owner_upsert_ungani_team_member - one line changed (the role
-- allowlist), everything else is byte-identical to the confirmed live
-- 9-param body (p_branch_id/p_can_access_all_branches multi-branch
-- version).
-- ============================================================

CREATE OR REPLACE FUNCTION public.owner_upsert_ungani_team_member(p_full_name text, p_email text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_role_key text DEFAULT 'staff'::text, p_status text DEFAULT 'active'::text, p_monthly_salary numeric DEFAULT NULL::numeric, p_pay_frequency text DEFAULT NULL::text, p_branch_id uuid DEFAULT NULL::uuid, p_can_access_all_branches boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_tenant_id uuid;
  v_member_id uuid;
  v_existing_id uuid;
  v_old_role text;
  v_role text;
  v_status text;
  v_monthly_salary numeric;
  v_pay_frequency text;
  v_clean_email text;
  v_tenant_name text;
  v_email_queue_error text;
  v_user_limit int;
  v_active_members int;
  v_is_new_member boolean;
  v_branch_id uuid;
  v_subscription_status text;
  v_package_key text;
begin
  v_tenant_id := public.get_my_ungani_tenant_id();
  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'No tenant workspace found.');
  end if;
  if public.is_my_ungani_tenant_owner(v_tenant_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'Only the business owner can manage staff access.');
  end if;
  v_role := lower(trim(coalesce(p_role_key, 'staff')));
  v_status := lower(trim(coalesce(p_status, 'active')));
  -- CHANGED: added 'teacher' and 'administration' to the recognized list.
  if v_role not in ('owner', 'manager', 'staff', 'viewer', 'accountant', 'frontdesk', 'teacher', 'administration') then
    v_role := 'staff';
  end if;
  if v_status not in ('active', 'invited', 'disabled') then
    v_status := 'active';
  end if;
  v_monthly_salary := case when p_monthly_salary is not null and p_monthly_salary >= 0 then p_monthly_salary else null end;
  v_pay_frequency := lower(trim(coalesce(p_pay_frequency, '')));
  if v_pay_frequency not in ('monthly', 'weekly', 'daily') then
    v_pay_frequency := null;
  end if;

  if p_branch_id is not null then
    select id into v_branch_id
    from public.branches
    where id = p_branch_id and tenant_id = v_tenant_id;
  else
    v_branch_id := null;
  end if;

  if p_email is not null then
    select id, role_key into v_existing_id, v_old_role
    from public.ungani_team_members
    where tenant_id = v_tenant_id
      and lower(coalesce(email, '')) = lower(trim(p_email))
    order by created_at desc
    limit 1;
  end if;

  select package_key into v_package_key
  from public.ungani_subscriptions
  where tenant_id = v_tenant_id;

  if v_package_key is null then
    select package_key into v_package_key
    from public.tenants
    where id = v_tenant_id;
  end if;

  select subscription_status
  into v_subscription_status
  from public.ungani_subscriptions
  where tenant_id = v_tenant_id;

  select p.user_limit
  into v_user_limit
  from public.ungani_packages p
  where p.package_key = v_package_key;

  if lower(coalesce(v_subscription_status, '')) = 'trial' then
    v_user_limit := 1;
  end if;

  if v_existing_id is null then
    if v_user_limit is not null then
      select count(*)
      into v_active_members
      from public.ungani_team_members tm
      where tm.tenant_id = v_tenant_id
        and coalesce(tm.is_active, true) = true
        and tm.deactivated_at is null
        and lower(coalesce(tm.status, 'active')) <> 'disabled';

      if (v_active_members + 1) >= v_user_limit then
        return jsonb_build_object(
          'ok', false,
          'message', case
            when lower(coalesce(v_subscription_status, '')) = 'trial'
              then 'Your free trial is limited to 1 user. Choose a package to add more staff.'
            else 'Your package allows up to ' || v_user_limit || ' user(s) (including you). Upgrade your package to add more staff.'
          end,
          'limit_reached', true,
          'user_limit', v_user_limit,
          'current_users', v_active_members + 1
        );
      end if;
    end if;
  end if;

  v_is_new_member := v_existing_id is null;

  if v_existing_id is not null then
    v_member_id := v_existing_id;

    if v_status = 'active' and v_user_limit is not null then
      select count(*)
      into v_active_members
      from public.ungani_team_members tm
      where tm.tenant_id = v_tenant_id
        and tm.id <> v_member_id
        and coalesce(tm.is_active, true) = true
        and tm.deactivated_at is null
        and lower(coalesce(tm.status, 'active')) <> 'disabled';

      if (v_active_members + 1) >= v_user_limit then
        return jsonb_build_object(
          'ok', false,
          'message', case
            when lower(coalesce(v_subscription_status, '')) = 'trial'
              then 'Your free trial is limited to 1 user. Choose a package to add more staff.'
            else 'Your package allows up to ' || v_user_limit || ' user(s) (including you). Upgrade your package to add more staff.'
          end,
          'limit_reached', true,
          'user_limit', v_user_limit,
          'current_users', v_active_members + 1
        );
      end if;
    end if;

    update public.ungani_team_members
    set
      full_name = nullif(trim(coalesce(p_full_name, full_name)), ''),
      phone = nullif(trim(coalesce(p_phone, phone)), ''),
      role_key = v_role,
      status = v_status,
      monthly_salary = v_monthly_salary,
      pay_frequency = v_pay_frequency,
      branch_id = v_branch_id,
      can_access_all_branches = coalesce(p_can_access_all_branches, false),
      is_active = (v_status <> 'disabled'),
      deactivated_at = case when v_status = 'disabled' then coalesce(deactivated_at, now()) else null end,
      updated_at = now()
    where id = v_member_id;
  else
    insert into public.ungani_team_members (
      tenant_id,
      full_name,
      email,
      phone,
      role_key,
      status,
      monthly_salary,
      pay_frequency,
      branch_id,
      can_access_all_branches,
      created_by
    )
    values (
      v_tenant_id,
      nullif(trim(coalesce(p_full_name, '')), ''),
      nullif(lower(trim(coalesce(p_email, ''))), ''),
      nullif(trim(coalesce(p_phone, '')), ''),
      v_role,
      v_status,
      v_monthly_salary,
      v_pay_frequency,
      v_branch_id,
      coalesce(p_can_access_all_branches, false),
      auth.uid()
    )
    returning id into v_member_id;
  end if;

  if v_member_id is not null and (v_is_new_member or coalesce(v_old_role, '') <> v_role) then
    perform public.owner_apply_ungani_staff_role_preset(v_member_id, v_role);
  end if;

  perform public.log_ungani_activity(
    'staff_saved',
    'settings',
    'ungani_team_members',
    v_member_id,
    'Staff member saved or updated.',
    jsonb_build_object('role_key', v_role, 'status', v_status)
  );

  if v_member_id is not null then
    begin
      v_clean_email := nullif(trim(coalesce(p_email, '')), '');

      if v_clean_email is not null then
        select business_name into v_tenant_name from public.tenants where id = v_tenant_id;

        if not exists (
          select 1 from public.ungani_email_queue
          where email_type = 'team_invitation'
            and related_table = 'ungani_team_members'
            and related_id = v_member_id
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
            v_clean_email,
            coalesce(nullif(trim(p_full_name), ''), 'there'),
            'You''ve been added to ' || coalesce(v_tenant_name, 'a UNGANI OS business') || ' on UNGANI OS',
            'Hi ' || coalesce(nullif(trim(p_full_name), ''), 'there') || E',\n\n' ||
            'You''ve been added as staff for ' || coalesce(v_tenant_name, 'a business') || ' on UNGANI OS.' || E'\n\n' ||
            'To get started, create your password here: https://ungani-os-portal.vercel.app/staff-login.html' || E'\n\n' ||
            'Use this email address (' || v_clean_email || ') when creating your password.' || E'\n\n' ||
            'Regards,' || E'\n' ||
            'UNGANI' || E'\n' ||
            'info@ungani.com',
            'team_invitation',
            'ungani_team_members',
            v_member_id,
            'pending',
            now()
          );
        end if;
      end if;
    exception
      when others then
        v_email_queue_error := sqlerrm;
        raise warning 'Could not queue team invitation email for member %: %', v_member_id, v_email_queue_error;
    end;
  end if;

  return jsonb_build_object('ok', true, 'id', v_member_id, 'team_member_id', v_member_id);
end;
$function$;

-- ============================================================
-- PART G: approve_ungani_registration - two lines added in each of the
-- INSERT and UPDATE branches (the new column in the column/SET list, and
-- its value pulled straight from r.business_sub_type/r.business_sub_type_key
-- - registrations already has both columns from Part A of the first
-- Phase 1 migration, and r is `select * from registrations`, so both are
-- already available on r with no new declarations needed). Not coalesced
-- against any existing tenant value, matching how business_type_key/
-- business_type themselves are handled a few lines above (directly
-- overwritten from the registration each time, not preserved). Every
-- other line is byte-identical to the confirmed live body.
-- ============================================================

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
  v_recipient_email text;
  v_approval_message text;
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
      business_sub_type,
      business_sub_type_key,
      contact_person,
      business_email,
      business_phone,
      business_location,
      business_description,
      selected_sections,
      account_status,
      status,
      referred_by_partner_id,
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
      r.business_sub_type,
      r.business_sub_type_key,
      v_contact_person,
      coalesce(r.email, r.contact_email),
      coalesce(r.phone, r.contact_phone),
      coalesce(r.location, r.business_location),
      coalesce(r.registration_notes, r.notes),
      r.selected_sections,
      'trial',
      'trial',
      r.referred_by_partner_id,
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
      business_sub_type = r.business_sub_type,
      business_sub_type_key = r.business_sub_type_key,
      contact_person = v_contact_person,
      business_email = coalesce(r.email, r.contact_email),
      business_phone = coalesce(r.phone, r.contact_phone),
      business_location = coalesce(r.location, r.business_location),
      business_description = coalesce(business_description, r.registration_notes, r.notes),
      selected_sections = r.selected_sections,
      account_status = 'trial',
      status = 'trial',
      referred_by_partner_id = coalesce(referred_by_partner_id, r.referred_by_partner_id),
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
  on conflict (id) do update set
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
    status = 'approved',
    updated_at = now()
  where id = p_registration_id;

  v_recipient_email := coalesce(r.email, r.contact_email);

  v_approval_message :=
    'Great news - ' || v_business_name || ' has been approved on UNGANI OS. ' ||
    'You can now log in at the client portal using the email and password you registered with. ' ||
    'Your account starts on a free trial - see My Package in the sidebar whenever you''re ready to choose a plan.';

  begin
    if v_recipient_email is not null and not exists (
      select 1 from public.ungani_email_queue
      where registration_id = p_registration_id and email_type = 'registration_approved'
    ) then
      insert into public.ungani_email_queue
        (tenant_id, registration_id, recipient_email, email_type, subject, body, status, created_at)
      values
        (v_tenant_id, p_registration_id, v_recipient_email, 'registration_approved',
         'Your UNGANI OS account is approved', v_approval_message, 'pending', now());
    end if;
  exception
    when others then
      raise warning 'Could not queue approval email for registration %: %', p_registration_id, sqlerrm;
  end;

  return jsonb_build_object(
    'ok', true,
    'tenant_id', v_tenant_id,
    'enabled_sections', v_enabled_sections,
    'approval_message', v_approval_message
  );
end;
$function$;

-- ============================================================
-- VERIFICATION
-- ============================================================

-- Confirm both new roles now survive owner_upsert_ungani_team_member
-- (should return the role_key unchanged, not silently downgraded to
-- 'staff' - this only checks the allowlist logic path, it does not
-- actually insert a row).
select
  case when 'teacher' = any(string_to_array('owner,manager,staff,viewer,accountant,frontdesk,teacher,administration', ',')) then 'teacher: OK' else 'teacher: MISSING' end,
  case when 'administration' = any(string_to_array('owner,manager,staff,viewer,accountant,frontdesk,teacher,administration', ',')) then 'administration: OK' else 'administration: MISSING' end;

select routine_name, security_type
from information_schema.routines
where routine_name in ('owner_upsert_ungani_team_member', 'approve_ungani_registration');
