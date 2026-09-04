-- ============================================================
-- Unifies notification unread-count logic across 4 previously
-- disconnected implementations (client.html dashboard bell,
-- client-shared.js bell engine, admin-shared.js sidebar badge,
-- api/send-event-push.js's push badgeCount) into one canonical
-- source of truth.
--
-- Canonical semantics (confirmed via two independently-converged
-- real implementations - client.html's own isNotificationUnread()
-- and client-shared.js's isNotificationActive(), which separately
-- arrived at the identical rule):
--   - notification_type in ('task_overdue', 'support_issue_open')
--     stays unread until resolved_at is set, regardless of status.
--   - every other type: unread iff status is not exactly 'read'.
--
-- get_ungani_unread_notification_count_for() is the shared counting
-- core - explicit params, no auth.uid() dependency, safe to call
-- from a service-role context (the push script) for an arbitrary
-- target_type/tenant.
--
-- get_my_ungani_unread_notification_count() is the public RPC every
-- browser-side caller (client + admin) uses - no params, resolves
-- admin vs client automatically via is_ungani_admin() and
-- get_my_ungani_current_tenant_id_v16() (both confirmed real,
-- already used elsewhere in this app), then delegates to the core.
--
-- Also fixes the confirmed root cause of the admin sidebar badge
-- being meaningless: it previously counted every unread row
-- platform-wide with zero target_type/tenant scoping at all. Now
-- properly scoped to target_type='admin' - which currently has zero
-- rows (no existing admin-facing event creates one yet), so the
-- admin bell will correctly show 0 everywhere immediately after this
-- runs. That's the correct, consistent state, not a new bug -
-- populating real admin-targeted rows is separate future work.
-- ============================================================

create or replace function public.get_ungani_unread_notification_count_for(
  p_target_type text,
  p_tenant_id uuid default null
)
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_count integer := 0;
begin
  select count(*)
  into v_count
  from public.ungani_notifications n
  where n.target_type = p_target_type
    and (p_tenant_id is null or n.tenant_id = p_tenant_id)
    and (
      (
        n.notification_type in ('task_overdue', 'support_issue_open')
        and n.resolved_at is null
      )
      or
      (
        n.notification_type not in ('task_overdue', 'support_issue_open')
        and lower(coalesce(n.status, '')) <> 'read'
      )
    );

  return coalesce(v_count, 0);
exception
  when others then
    return 0;
end;
$function$;

create or replace function public.get_my_ungani_unread_notification_count()
returns integer
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_is_admin boolean := false;
  v_tenant_id uuid;
begin
  begin
    v_is_admin := coalesce(public.is_ungani_admin(), false);
  exception
    when others then
      v_is_admin := false;
  end;

  if v_is_admin then
    return public.get_ungani_unread_notification_count_for('admin', null);
  end if;

  v_tenant_id := public.get_my_ungani_current_tenant_id_v16();

  if v_tenant_id is null then
    return 0;
  end if;

  return public.get_ungani_unread_notification_count_for('client', v_tenant_id);
exception
  when others then
    return 0;
end;
$function$;

grant execute on function public.get_ungani_unread_notification_count_for(text, uuid) to service_role;
grant execute on function public.get_my_ungani_unread_notification_count() to authenticated;

-- ============================================================
-- VERIFICATION - run and paste back the output.
-- ============================================================

select routine_name
from information_schema.routines
where routine_schema = 'public'
  and routine_name in (
    'get_ungani_unread_notification_count_for',
    'get_my_ungani_unread_notification_count'
  )
order by routine_name;
