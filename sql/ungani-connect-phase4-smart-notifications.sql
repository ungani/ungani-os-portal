-- Ungani Connect - Phase 4: wire Mentions into real notification
-- delivery (in-app + push + email) and add Smart Notifications for
-- comment/status-change/document-attachment events, using the exact
-- established handler pattern (notify_ungani_task_assignment): a
-- SECURITY DEFINER RPC that re-derives everything server-side from the
-- real row (never trusts client-supplied content), creates an in-app
-- notification via create_ungani_notification(), then best-effort
-- queues a fully-rendered email - all inside `exception when others`
-- so a queueing failure never breaks the caller's real action.
--
-- Real sources pulled before writing this, not guessed:
--   - notify_ungani_task_assignment()'s exact real source (from
--     sql/notifications-phase1-emails.sql - the latest, currently-live
--     version) - the template this migration's 3 new RPCs mirror.
--   - create_ungani_notification()'s exact real signature/column list -
--     unchanged here except for the STILL-PENDING target_type fix
--     bundled below (Part A), carried over verbatim from
--     sql/diagnose-and-fix-badge-and-push-round2.sql. Phase 4 is the
--     first NEW caller of this function since that fix was written, so
--     every notification this migration creates would otherwise inherit
--     the exact same "invisible to the Dashboard bell" bug - worth
--     fixing now rather than building more on top of it.
--   - Real schema for tasks (assigned_to_team_member_id/
--     assigned_to_is_owner), transactions (related_team_member_id),
--     documents (linked_task_id/linked_transaction_id from Phase 2/3),
--     registrations (auth_user_id/contact_person/email), public.users
--     (id = auth.uid(), full_name, email) - all already confirmed real
--     this session, reused here rather than re-verified from scratch.
--   - ungani_email_queue's real column list, from the same source.
--
-- Design decisions (per the user's Phase 4 instructions):
--   - "Mentions" storage: mentioned_user_ids stores real auth.users.id
--     values directly (not team_member ids) - uniform for both staff
--     and the owner (who has no ungani_team_members row), and directly
--     usable for push/notification targeting with no extra resolution
--     step. The mention picker built in the client changes this phase
--     populates this column for the first time - Phase 0 only ever
--     stored it, nothing wrote to it until now.
--   - "Relevant party" (who gets comment/status-change/attachment
--     notifications, beyond explicit @mentions): only Tasks
--     (assigned_to_*) and Transactions/Payments (related_team_member_id,
--     the same real column payroll tagging already uses) have a genuine
--     assignee-style concept in this schema. Documents/People/Employees
--     have none - for those 3 types, Phase 4 notifications are
--     mentions-only. Not an oversight - confirmed via the same schema
--     read used for Phase 3's Attachments scoping.
--   - "Approval": no dedicated approval workflow exists for these record
--     types (unlike registration/payment-proof approval elsewhere in
--     this app) - scoped as a status_changed transition, not a new
--     workflow. No separate "approval" event type exists in this
--     migration; a status change TO an approved/completed value already
--     fires notify_ungani_record_status_change.
--   - No content-based email dedup on the 3 new RPCs (unlike task
--     assignment's per-assignee dedup) - each is called exactly once
--     per real client-side action (one comment post, one status change,
--     one document link), same "trusted, called once" pattern
--     log_ungani_record_activity() has used since Phase 2 with no
--     issues.

-- ============================================================
-- PART A: the previously-flagged, still-pending create_ungani_notification
-- target_type fix - bundled here since Phase 4 is the first NEW caller
-- of this function since the fix was written. Verbatim from
-- sql/diagnose-and-fix-badge-and-push-round2.sql.
-- ============================================================

create or replace function public.create_ungani_notification(
  p_tenant_id uuid,
  p_title text,
  p_message text,
  p_notification_type text default 'system'::text,
  p_source_table text default null::text,
  p_source_record_id uuid default null::uuid,
  p_link_url text default null::text,
  p_priority text default 'normal'::text,
  p_metadata jsonb default '{}'::jsonb,
  p_email_enabled boolean default false,
  p_user_id uuid default null::uuid
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_notification_id uuid;
  v_title text;
  v_message text;
  v_type text;
  v_priority text;
begin
  if p_tenant_id is null then
    return jsonb_build_object('ok', false, 'message', 'Tenant ID is required.');
  end if;

  v_title := nullif(trim(coalesce(p_title, '')), '');
  v_message := nullif(trim(coalesce(p_message, '')), '');
  v_type := lower(coalesce(nullif(trim(p_notification_type), ''), 'system'));
  v_priority := lower(coalesce(nullif(trim(p_priority), ''), 'normal'));

  if v_title is null then
    v_title := 'UNGANI Notification';
  end if;

  if v_message is null then
    v_message := v_title;
  end if;

  insert into public.ungani_notifications (
    tenant_id, user_id, notification_title, notification_message, notification_type,
    source_table, source_record_id, link_url, priority, status, is_read,
    email_enabled, email_queued, metadata, target_type, created_at, updated_at
  )
  values (
    p_tenant_id, p_user_id, v_title, v_message, v_type,
    p_source_table, p_source_record_id, p_link_url, v_priority, 'unread', false,
    coalesce(p_email_enabled, false), false, coalesce(p_metadata, '{}'::jsonb), 'client', now(), now()
  )
  returning id into v_notification_id;

  return jsonb_build_object('ok', true, 'message', 'Notification created.', 'notification_id', v_notification_id);
exception
  when others then
    return jsonb_build_object('ok', false, 'message', sqlerrm);
end;
$function$;

-- ============================================================
-- PART B: internal helpers - NOT granted to authenticated (matches
-- create_ungani_notification's own narrow-wrapper-only pattern).
-- resolve_ungani_record_relevant_party does not itself verify the
-- caller's tenant - it must only ever be called from another SECURITY
-- DEFINER function that has already done that check, never exposed
-- directly (a direct grant would let any authenticated user fish for
-- another tenant's assignee auth_user_id).
-- ============================================================

create or replace function public.resolve_ungani_record_relevant_party(p_record_table text, p_record_id uuid)
returns uuid
language plpgsql
security definer
set search_path to 'public'
stable
as $function$
declare
  v_tenant_id uuid;
  v_is_owner boolean := false;
  v_team_member_id uuid;
  v_result uuid;
begin
  if p_record_table = 'tasks' then
    select tenant_id, assigned_to_is_owner, assigned_to_team_member_id
    into v_tenant_id, v_is_owner, v_team_member_id
    from public.tasks where id = p_record_id;
  elsif p_record_table = 'transactions' then
    select tenant_id, false, related_team_member_id
    into v_tenant_id, v_is_owner, v_team_member_id
    from public.transactions where id = p_record_id;
  else
    return null;
  end if;

  if v_tenant_id is null then
    return null;
  end if;

  if coalesce(v_is_owner, false) then
    select r.auth_user_id into v_result
    from public.registrations r
    where r.tenant_id = v_tenant_id
      and lower(coalesce(r.status, r.registration_status, 'pending')) in ('approved', 'active', 'trial')
    order by r.created_at desc
    limit 1;
    return v_result;
  elsif v_team_member_id is not null then
    select auth_user_id into v_result
    from public.ungani_team_members
    where id = v_team_member_id and tenant_id = v_tenant_id;
    return v_result;
  end if;

  return null;
end;
$function$;

revoke execute on function public.resolve_ungani_record_relevant_party(text, uuid) from public, authenticated;

create or replace function public.resolve_ungani_user_contact(p_tenant_id uuid, p_auth_user_id uuid)
returns table(email text, full_name text)
language plpgsql
security definer
set search_path to 'public'
stable
as $function$
begin
  return query
  select tm.email, coalesce(tm.full_name, 'there')
  from public.ungani_team_members tm
  where tm.tenant_id = p_tenant_id and tm.auth_user_id = p_auth_user_id
  limit 1;

  if not found then
    return query
    select coalesce(r.email, r.contact_email), coalesce(r.contact_person, r.contact_name, r.full_name, 'there')
    from public.registrations r
    where r.tenant_id = p_tenant_id and r.auth_user_id = p_auth_user_id
    order by r.created_at desc
    limit 1;
  end if;
end;
$function$;

revoke execute on function public.resolve_ungani_user_contact(uuid, uuid) from public, authenticated;

-- ============================================================
-- PART C: the 3 client-facing notify RPCs.
-- ============================================================

-- Called after add_ungani_record_comment() succeeds. Re-derives
-- everything from the real comment row (never trusts client text).
-- Recipients = every @mentioned user + (for Tasks/Transactions only)
-- the record's relevant party - deduped, author always excluded.
create or replace function public.notify_ungani_record_comment(p_comment_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_comment record;
  v_relevant_party uuid;
  v_recipients uuid[];
  v_recipient uuid;
  v_is_mention boolean;
  v_record_label text;
  v_recipient_email text;
  v_recipient_name text;
  v_tenant_name text;
  v_notified_count int := 0;
begin
  select id, tenant_id, record_table, record_id, author_user_id, author_name, body, mentioned_user_ids
  into v_comment
  from public.ungani_record_comments
  where id = p_comment_id;

  if v_comment.id is null then
    return jsonb_build_object('ok', false, 'message', 'Comment not found.');
  end if;

  v_relevant_party := public.resolve_ungani_record_relevant_party(v_comment.record_table, v_comment.record_id);

  v_recipients := coalesce(v_comment.mentioned_user_ids, '{}'::uuid[]);
  if v_relevant_party is not null then
    v_recipients := array_append(v_recipients, v_relevant_party);
  end if;

  select array_agg(distinct x) into v_recipients
  from unnest(v_recipients) as x
  where x is not null and x != v_comment.author_user_id;

  if v_recipients is null then
    return jsonb_build_object('ok', true, 'notified', 0);
  end if;

  v_record_label := initcap(replace(v_comment.record_table, '_', ' '));
  select business_name into v_tenant_name from public.tenants where id = v_comment.tenant_id;

  foreach v_recipient in array v_recipients loop
    v_is_mention := v_recipient = any(coalesce(v_comment.mentioned_user_ids, '{}'::uuid[]));

    perform public.create_ungani_notification(
      v_comment.tenant_id,
      case when v_is_mention then 'You were mentioned' else 'New comment' end,
      coalesce(v_comment.author_name, 'Someone') ||
        (case when v_is_mention then ' mentioned you in a comment' else ' commented' end) ||
        ' on a ' || v_record_label || ': ' || left(v_comment.body, 140),
      'record_comment',
      v_comment.record_table,
      v_comment.record_id,
      null,
      'normal',
      jsonb_build_object('comment_id', v_comment.id, 'record_table', v_comment.record_table, 'record_id', v_comment.record_id, 'is_mention', v_is_mention),
      false,
      v_recipient
    );

    v_notified_count := v_notified_count + 1;

    begin
      select rc.email, rc.full_name into v_recipient_email, v_recipient_name
      from public.resolve_ungani_user_contact(v_comment.tenant_id, v_recipient) rc;

      v_recipient_email := nullif(trim(coalesce(v_recipient_email, '')), '');

      if v_recipient_email is not null then
        insert into public.ungani_email_queue (
          tenant_id, recipient_email, recipient_name, email_subject, email_body,
          email_type, related_table, related_id, send_status, created_at
        ) values (
          v_comment.tenant_id, v_recipient_email, coalesce(v_recipient_name, 'there'),
          (case when v_is_mention then 'You were mentioned' else 'New comment' end) || ' on a ' || v_record_label,
          'Hi ' || coalesce(v_recipient_name, 'there') || E',\n\n' ||
          coalesce(v_comment.author_name, 'Someone') ||
          (case when v_is_mention then ' mentioned you in a comment' else ' commented' end) ||
          (case when v_tenant_name is not null then ' at ' || v_tenant_name else '' end) ||
          ' on a ' || v_record_label || ':' || E'\n\n' ||
          '"' || left(v_comment.body, 400) || '"' || E'\n\n' ||
          'Regards,' || E'\n' || 'UNGANI' || E'\n' || 'info@ungani.com',
          'record_comment', v_comment.record_table, v_comment.record_id, 'pending', now()
        );
      end if;
    exception
      when others then
        raise warning 'Could not queue comment-notification email for comment %: %', v_comment.id, sqlerrm;
    end;
  end loop;

  return jsonb_build_object('ok', true, 'notified', v_notified_count);
end;
$function$;

grant execute on function public.notify_ungani_record_comment(uuid) to authenticated;

-- Called after a status change is saved (my-tasks.html/my-money.html
-- and any future caller). Only Tasks/Transactions resolve a relevant
-- party today - other record types return notified:0, no-op.
create or replace function public.notify_ungani_record_status_change(
  p_record_table text,
  p_record_id uuid,
  p_old_status text,
  p_new_status text
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_access jsonb;
  v_caller_user_id uuid := auth.uid();
  v_relevant_party uuid;
  v_tenant_id uuid;
  v_actor_name text;
  v_recipient_email text;
  v_recipient_name text;
  v_tenant_name text;
  v_record_label text;
begin
  if public.can_access_ungani_record(p_record_table, p_record_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'You do not have access to this record.');
  end if;

  v_access := public.get_my_ungani_staff_access();
  v_tenant_id := nullif(v_access->>'tenant_id', '')::uuid;

  v_relevant_party := public.resolve_ungani_record_relevant_party(p_record_table, p_record_id);

  if v_relevant_party is null or v_relevant_party = v_caller_user_id then
    return jsonb_build_object('ok', true, 'notified', 0);
  end if;

  select coalesce(nullif(trim(full_name), ''), split_part(email, '@', 1)) into v_actor_name
  from public.users where id = v_caller_user_id;

  v_record_label := initcap(replace(p_record_table, '_', ' '));

  perform public.create_ungani_notification(
    v_tenant_id,
    'Status updated',
    coalesce(v_actor_name, 'Someone') || ' changed a ' || v_record_label || ' status from ' ||
      coalesce(initcap(p_old_status), 'Unknown') || ' to ' || coalesce(initcap(p_new_status), 'Unknown') || '.',
    'record_status_changed',
    p_record_table,
    p_record_id,
    null,
    'normal',
    jsonb_build_object('record_table', p_record_table, 'record_id', p_record_id, 'old_status', p_old_status, 'new_status', p_new_status),
    false,
    v_relevant_party
  );

  begin
    select rc.email, rc.full_name into v_recipient_email, v_recipient_name
    from public.resolve_ungani_user_contact(v_tenant_id, v_relevant_party) rc;

    v_recipient_email := nullif(trim(coalesce(v_recipient_email, '')), '');

    if v_recipient_email is not null then
      select business_name into v_tenant_name from public.tenants where id = v_tenant_id;

      insert into public.ungani_email_queue (
        tenant_id, recipient_email, recipient_name, email_subject, email_body,
        email_type, related_table, related_id, send_status, created_at
      ) values (
        v_tenant_id, v_recipient_email, coalesce(v_recipient_name, 'there'),
        'Status updated: ' || v_record_label,
        'Hi ' || coalesce(v_recipient_name, 'there') || E',\n\n' ||
        coalesce(v_actor_name, 'Someone') || ' changed a ' || v_record_label || ' status' ||
        (case when v_tenant_name is not null then ' at ' || v_tenant_name else '' end) ||
        ' from ' || coalesce(initcap(p_old_status), 'Unknown') || ' to ' || coalesce(initcap(p_new_status), 'Unknown') || '.' || E'\n\n' ||
        'Regards,' || E'\n' || 'UNGANI' || E'\n' || 'info@ungani.com',
        'record_status_changed', p_record_table, p_record_id, 'pending', now()
      );
    end if;
  exception
    when others then
      raise warning 'Could not queue status-change email for % %: %', p_record_table, p_record_id, sqlerrm;
  end;

  return jsonb_build_object('ok', true, 'notified', 1);
end;
$function$;

grant execute on function public.notify_ungani_record_status_change(text, uuid, text, text) to authenticated;

-- Called after a document is linked to a task/transaction (via the
-- Attachments tab or Documents' own "Link to Task/Payment" dropdowns).
-- Only fires when the document is linked to a record type with a
-- relevant party - linking to a person/staff member/generic document
-- has no natural recipient, no-op.
create or replace function public.notify_ungani_record_attachment(p_document_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_doc record;
  v_record_table text;
  v_record_id uuid;
  v_relevant_party uuid;
  v_caller_user_id uuid := auth.uid();
  v_actor_name text;
  v_recipient_email text;
  v_recipient_name text;
  v_tenant_name text;
begin
  select id, tenant_id, document_title, linked_task_id, linked_transaction_id
  into v_doc
  from public.documents
  where id = p_document_id;

  if v_doc.id is null then
    return jsonb_build_object('ok', false, 'message', 'Document not found.');
  end if;

  if v_doc.linked_task_id is not null then
    v_record_table := 'tasks';
    v_record_id := v_doc.linked_task_id;
  elsif v_doc.linked_transaction_id is not null then
    v_record_table := 'transactions';
    v_record_id := v_doc.linked_transaction_id;
  else
    return jsonb_build_object('ok', true, 'notified', 0, 'message', 'Document not linked to a record with a relevant party.');
  end if;

  v_relevant_party := public.resolve_ungani_record_relevant_party(v_record_table, v_record_id);

  if v_relevant_party is null or v_relevant_party = v_caller_user_id then
    return jsonb_build_object('ok', true, 'notified', 0);
  end if;

  select coalesce(nullif(trim(full_name), ''), split_part(email, '@', 1)) into v_actor_name
  from public.users where id = v_caller_user_id;

  perform public.create_ungani_notification(
    v_doc.tenant_id,
    'New document attached',
    coalesce(v_actor_name, 'Someone') || ' attached "' || coalesce(v_doc.document_title, 'a document') ||
      '" to your ' || initcap(replace(v_record_table, '_', ' ')) || '.',
    'record_attachment',
    v_record_table,
    v_record_id,
    null,
    'normal',
    jsonb_build_object('document_id', v_doc.id, 'record_table', v_record_table, 'record_id', v_record_id),
    false,
    v_relevant_party
  );

  begin
    select rc.email, rc.full_name into v_recipient_email, v_recipient_name
    from public.resolve_ungani_user_contact(v_doc.tenant_id, v_relevant_party) rc;

    v_recipient_email := nullif(trim(coalesce(v_recipient_email, '')), '');

    if v_recipient_email is not null then
      select business_name into v_tenant_name from public.tenants where id = v_doc.tenant_id;

      insert into public.ungani_email_queue (
        tenant_id, recipient_email, recipient_name, email_subject, email_body,
        email_type, related_table, related_id, send_status, created_at
      ) values (
        v_doc.tenant_id, v_recipient_email, coalesce(v_recipient_name, 'there'),
        'New document attached: ' || coalesce(v_doc.document_title, 'a document'),
        'Hi ' || coalesce(v_recipient_name, 'there') || E',\n\n' ||
        coalesce(v_actor_name, 'Someone') || ' attached a document' ||
        (case when v_tenant_name is not null then ' at ' || v_tenant_name else '' end) || ':' || E'\n\n' ||
        coalesce(v_doc.document_title, 'Document') || E'\n\n' ||
        'Regards,' || E'\n' || 'UNGANI' || E'\n' || 'info@ungani.com',
        'record_attachment', v_record_table, v_record_id, 'pending', now()
      );
    end if;
  exception
    when others then
      raise warning 'Could not queue attachment-notification email for document %: %', p_document_id, sqlerrm;
  end;

  return jsonb_build_object('ok', true, 'notified', 1);
end;
$function$;

grant execute on function public.notify_ungani_record_attachment(uuid) to authenticated;

-- ============================================================
-- PART D: log_ungani_record_activity now returns the new row's id.
-- Purely additive (existing callers that ignore the extra field are
-- unaffected) - the push endpoint needs a real, persisted row id to
-- look up and re-derive from server-side for status-change pushes,
-- same security discipline as record_comment/record_attachment looking
-- up their own real rows rather than trusting client-supplied content.
-- ============================================================

create or replace function public.log_ungani_record_activity(
  p_record_table text,
  p_record_id uuid,
  p_event_type text,
  p_description text,
  p_metadata jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_access jsonb;
  v_tenant_id uuid;
  v_author_name text;
  v_activity_id uuid;
begin
  if public.can_access_ungani_record(p_record_table, p_record_id) is not true then
    return jsonb_build_object('ok', false, 'message', 'You do not have access to this record.');
  end if;

  v_access := public.get_my_ungani_staff_access();
  v_tenant_id := nullif(v_access->>'tenant_id', '')::uuid;

  select coalesce(nullif(trim(full_name), ''), split_part(email, '@', 1))
  into v_author_name
  from public.users
  where id = auth.uid();

  insert into public.ungani_record_activity (
    tenant_id, record_table, record_id, actor_user_id, actor_name, event_type, description, metadata
  ) values (
    v_tenant_id, p_record_table, p_record_id, auth.uid(), coalesce(v_author_name, 'Someone'),
    coalesce(nullif(trim(p_event_type), ''), 'activity'),
    coalesce(nullif(trim(p_description), ''), 'Activity recorded.'),
    coalesce(p_metadata, '{}'::jsonb)
  )
  returning id into v_activity_id;

  return jsonb_build_object('ok', true, 'activity_id', v_activity_id);
end;
$function$;

-- ============================================================
-- VERIFICATION - run this and paste back the output.
-- ============================================================

-- 1. create_ungani_notification now carries target_type.
select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'create_ungani_notification'
  and pg_get_function_identity_arguments(p.oid) ilike '%p_user_id%';

-- 2. All 5 new/changed functions exist.
select p.proname, pg_get_function_identity_arguments(p.oid) as arguments
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and p.proname in (
    'resolve_ungani_record_relevant_party',
    'resolve_ungani_user_contact',
    'notify_ungani_record_comment',
    'notify_ungani_record_status_change',
    'notify_ungani_record_attachment'
  )
order by p.proname;

-- 3. Grants: authenticated has EXECUTE on the 3 client-facing RPCs
-- only, NOT the 2 internal helpers.
select routine_name, privilege_type
from information_schema.role_routine_grants
where routine_schema = 'public'
  and routine_name in (
    'resolve_ungani_record_relevant_party',
    'resolve_ungani_user_contact',
    'notify_ungani_record_comment',
    'notify_ungani_record_status_change',
    'notify_ungani_record_attachment'
  )
  and grantee = 'authenticated'
order by routine_name;

-- 4. log_ungani_record_activity's real return type now includes
-- activity_id (spot-check via a real call once you're logged in as an
-- owner - optional, safe to skip if you'd rather just trust the
-- function-definition check below).
select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'log_ungani_record_activity';
