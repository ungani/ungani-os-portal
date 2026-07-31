-- UNGANI OS: real task assignment linking + "My Tasks" filter + assignment
-- notifications.
-- Run this whole file in order in the Supabase SQL editor.
--
-- Built from literal, user-confirmed current source for every function
-- touched below (get_my_ungani_notifications, owner_get_ungani_team_members,
-- create_ungani_notification, and information_schema for
-- ungani_notifications / ungani_team_members) - nothing here is guessed.
--
-- ============================================================================
-- STEP 1: tasks - real assignee columns, alongside (not replacing) the
-- existing free-text assigned_to column.
-- ============================================================================
--
-- assigned_to stays as-is and is kept auto-populated by the app as a
-- denormalized display cache (the assignee's real name, or "Owner") - so
-- search (buildSearchOrFilter includes "assigned_to"), CSV export, and every
-- pre-existing free-text row keep working completely unchanged. All new
-- linking/filtering/notification logic keys off the two columns below
-- instead. Old free-text assignments (e.g. "Mary") are NOT retroactively
-- matched to a real ungani_team_members row - that would require guessing at
-- fuzzy name matches, which is worse than just leaving them as legacy text.

alter table public.tasks
  add column if not exists assigned_to_team_member_id uuid references public.ungani_team_members(id),
  add column if not exists assigned_to_is_owner boolean not null default false;

-- The owner isn't a ungani_team_members row, so these two are mutually
-- exclusive - a task is assigned to a specific team member, to the owner, or
-- to no one, never more than one of those at once.
alter table public.tasks
  drop constraint if exists tasks_assignee_not_both_check;

alter table public.tasks
  add constraint tasks_assignee_not_both_check
  check (not (assigned_to_is_owner = true and assigned_to_team_member_id is not null));

create index if not exists idx_tasks_assigned_to_team_member_id
  on public.tasks(assigned_to_team_member_id);

create index if not exists idx_tasks_assigned_to_is_owner
  on public.tasks(assigned_to_is_owner)
  where assigned_to_is_owner = true;

-- ============================================================================
-- STEP 2: a permissive "list my tenant's team members" RPC.
-- ============================================================================
--
-- owner_get_ungani_team_members() (confirmed via its real source) is
-- owner-only (is_my_ungani_tenant_owner() gate) - a staff member assigning a
-- task to a teammate can't call it. This is a separate, deliberately
-- narrower RPC: no permissions grid, just enough to populate an assignee
-- picker, callable by owner OR any active staff member of the tenant.

create or replace function public.get_my_ungani_team_members_for_assignment()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_access jsonb;
  v_tenant_id uuid;
begin
  v_access := public.get_my_ungani_staff_access();

  if coalesce((v_access->>'can_access')::boolean, false) is not true then
    return jsonb_build_object('ok', false, 'members', '[]'::jsonb, 'message', 'No active account found for this login.');
  end if;

  v_tenant_id := nullif(v_access->>'tenant_id', '')::uuid;

  if v_tenant_id is null then
    return jsonb_build_object('ok', false, 'members', '[]'::jsonb, 'message', 'No tenant found for this login.');
  end if;

  return jsonb_build_object(
    'ok', true,
    'members',
    coalesce(
      (
        select jsonb_agg(
          jsonb_build_object(
            'id', tm.id,
            'full_name', tm.full_name,
            'role_key', tm.role_key
          )
          order by tm.full_name
        )
        from public.ungani_team_members tm
        where tm.tenant_id = v_tenant_id
          and coalesce(tm.is_active, true) = true
          and tm.deactivated_at is null
          and lower(coalesce(tm.status, 'active')) in ('active', 'accepted')
      ),
      '[]'::jsonb
    )
  );
end;
$function$;

grant execute on function public.get_my_ungani_team_members_for_assignment() to authenticated;

-- ============================================================================
-- STEP 3: extend create_ungani_notification with an optional p_user_id, as a
-- NEW OVERLOAD (appended as the LAST parameter with a default).
-- ============================================================================
--
-- Adding a parameter changes the function's argument-type signature, so
-- Postgres treats this as a new, separate overload rather than replacing the
-- original 10-arg function in place - the original stays exactly as-is
-- (still revoked from public/authenticated per the earlier security fix,
-- still called unmodified by whatever internal triggers already use it
-- positionally). This new 11-arg overload is the one notify_ungani_task_
-- assignment() below calls explicitly. Locked down the same way the
-- original was - direct client access was never intended for either.

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
    return jsonb_build_object(
      'ok', false,
      'message', 'Tenant ID is required.'
    );
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
    tenant_id,
    user_id,
    notification_title,
    notification_message,
    notification_type,
    source_table,
    source_record_id,
    link_url,
    priority,
    status,
    is_read,
    email_enabled,
    email_queued,
    metadata,
    created_at,
    updated_at
  )
  values (
    p_tenant_id,
    p_user_id,
    v_title,
    v_message,
    v_type,
    p_source_table,
    p_source_record_id,
    p_link_url,
    v_priority,
    'unread',
    false,
    coalesce(p_email_enabled, false),
    false,
    coalesce(p_metadata, '{}'::jsonb),
    now(),
    now()
  )
  returning id into v_notification_id;

  return jsonb_build_object(
    'ok', true,
    'message', 'Notification created.',
    'notification_id', v_notification_id
  );
exception
  when others then
    return jsonb_build_object(
      'ok', false,
      'message', sqlerrm
    );
end;
$function$;

revoke execute on function public.create_ungani_notification(
  uuid, text, text, text, text, uuid, text, text, jsonb, boolean, uuid
) from public, authenticated;

-- ============================================================================
-- STEP 4: notify_ungani_task_assignment - the narrow, safe wrapper a client
-- calls when a task's assignee is set/changed.
-- ============================================================================
--
-- Same cross-tenant-injection defense as create_my_ungani_notification: the
-- caller never supplies a tenant_id directly - it's derived from the task
-- row itself and cross-checked against the CALLER's own tenant (via
-- get_my_ungani_staff_access(), the app's single source of truth), so a
-- caller can only ever trigger a notification for a task that's actually
-- theirs.
--
-- The assignee's real auth_user_id may not exist yet (a team member who's
-- never logged in has ungani_team_members.auth_user_id = null). Rather than
-- silently skip notifying, the notification is still created tenant-wide
-- (user_id left null) - degrades to the same visibility every notification
-- had before this migration, instead of vanishing.

create or replace function public.notify_ungani_task_assignment(
  p_task_id uuid,
  p_assignee_team_member_id uuid default null,
  p_assignee_is_owner boolean default false
)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_access jsonb;
  v_caller_tenant_id uuid;
  v_task record;
  v_assignee_user_id uuid;
begin
  v_access := public.get_my_ungani_staff_access();

  if coalesce((v_access->>'can_access')::boolean, false) is not true then
    return jsonb_build_object('ok', false, 'message', 'No active account found for this login.');
  end if;

  v_caller_tenant_id := nullif(v_access->>'tenant_id', '')::uuid;

  select id, tenant_id, task_title
  into v_task
  from public.tasks
  where id = p_task_id;

  if v_task.id is null then
    return jsonb_build_object('ok', false, 'message', 'Task not found.');
  end if;

  if v_caller_tenant_id is null or v_caller_tenant_id != v_task.tenant_id then
    return jsonb_build_object('ok', false, 'message', 'Task does not belong to your account.');
  end if;

  if coalesce(p_assignee_is_owner, false) then
    -- Same owner-resolution pattern get_my_ungani_staff_access() itself
    -- uses - the tenant's approved/active/trial registration row is the
    -- canonical source of the owner's auth_user_id.
    select r.auth_user_id
    into v_assignee_user_id
    from public.registrations r
    where r.tenant_id = v_task.tenant_id
      and lower(coalesce(r.status, r.registration_status, 'pending')) in ('approved', 'active', 'trial')
    order by r.created_at desc
    limit 1;

  elsif p_assignee_team_member_id is not null then
    select tm.auth_user_id
    into v_assignee_user_id
    from public.ungani_team_members tm
    where tm.id = p_assignee_team_member_id
      and tm.tenant_id = v_task.tenant_id;

    if not found then
      return jsonb_build_object('ok', false, 'message', 'Assignee not found for this account.');
    end if;

  else
    return jsonb_build_object('ok', true, 'message', 'No assignee - nothing to notify.');
  end if;

  return public.create_ungani_notification(
    v_task.tenant_id,
    'New task assigned',
    'You''ve been assigned: ' || coalesce(v_task.task_title, 'a task'),
    'task_assignment',
    'tasks',
    v_task.id,
    '/my-tasks.html?highlight=' || v_task.id::text,
    'normal',
    jsonb_build_object(
      'task_id', v_task.id,
      'assignee_team_member_id', p_assignee_team_member_id,
      'assignee_is_owner', coalesce(p_assignee_is_owner, false)
    ),
    false,
    v_assignee_user_id
  );
end;
$function$;

grant execute on function public.notify_ungani_task_assignment(uuid, uuid, boolean) to authenticated;

-- ============================================================================
-- STEP 5: get_my_ungani_notifications - prefer a real recipient match,
-- fall back to tenant-wide for untargeted rows.
-- ============================================================================
--
-- Same signature as before (CREATE OR REPLACE genuinely replaces this one in
-- place, no overload) - only the WHERE clause changes. Every existing row
-- has user_id = null (nothing wrote to that column before this migration),
-- so this is a no-op for all current data: everyone keeps seeing every
-- existing notification exactly as before. Only NEW notifications created
-- with a specific p_user_id (like task-assignment ones) become visible only
-- to that person - notably, this means the owner will NOT see other staff's
-- assignment notifications in their own bell going forward, since those are
-- correctly targeted at the assignee, not tenant-wide. Flagging this as a
-- real, deliberate behavior change, not an oversight.

create or replace function public.get_my_ungani_notifications(p_limit integer default 30)
returns table(
  id uuid,
  notification_title text,
  notification_message text,
  notification_type text,
  source_table text,
  source_record_id uuid,
  link_url text,
  priority text,
  status text,
  is_read boolean,
  created_at timestamp with time zone,
  metadata jsonb
)
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_tenant_id uuid;
  v_user_id uuid := auth.uid();
begin
  begin
    v_user_tenant_id := public.get_my_ungani_current_tenant_id_v16();
  exception
    when others then
      begin
        v_user_tenant_id := public.get_my_ungani_tenant_id();
      exception
        when others then
          v_user_tenant_id := null;
      end;
  end;

  if v_user_tenant_id is null then
    return;
  end if;

  return query
  select
    n.id,
    n.notification_title,
    n.notification_message,
    n.notification_type,
    n.source_table,
    n.source_record_id,
    n.link_url,
    n.priority,
    n.status,
    n.is_read,
    n.created_at,
    n.metadata
  from public.ungani_notifications n
  where n.tenant_id = v_user_tenant_id
    and (n.user_id is null or n.user_id = v_user_id)
  order by n.created_at desc
  limit greatest(1, least(coalesce(p_limit, 30), 100));
end;
$function$;

-- Verification - confirm everything landed.
select proname, pronargs
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public'
  and proname in (
    'get_my_ungani_team_members_for_assignment',
    'create_ungani_notification',
    'notify_ungani_task_assignment',
    'get_my_ungani_notifications'
  )
order by proname, pronargs;

select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'tasks'
  and column_name in ('assigned_to_team_member_id', 'assigned_to_is_owner');
