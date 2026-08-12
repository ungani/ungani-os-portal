-- Pure add, no existing function touched. Extracts the owner-resolution
-- logic notify_ungani_task_assignment() already has correct (real,
-- pulled source: sql/fix-task-assignment-owner-auth-user-id-staleness.sql)
-- into its own callable function, so api/send-event-push.js can share
-- it instead of re-implementing (and, as just found, mis-implementing)
-- its own copy.
--
-- Root cause of the real Chris test failure: api/send-event-push.js had
-- THREE independent copies of "find the tenant's owner auth_user_id"
-- (handleTaskAssignment, handleTeamChatMessage, resolveRelevantParty),
-- all with the pre-fix logic - plain `status` column only, no
-- registration_status fallback, no auth.users staleness check, no email
-- fallback. For an owner-assigned task, this returned zero registrations
-- rows (or a stale auth_user_id), so assigneeUserId stayed null and the
-- function hit the "no resolvable assignee" early return - which is the
-- ONE exit path that never calls markSent(), matching the confirmed
-- empty ungani_push_sent_log. The RPC (which builds the in-app
-- notification) uses the coalesce/staleness-checked logic already, which
-- is why the notification always worked while the push silently never
-- did, for owner-assigned tasks specifically.

create or replace function public.resolve_ungani_tenant_owner_auth_user_id(p_tenant_id uuid)
returns uuid
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  v_user_id uuid;
  v_email text;
begin
  if p_tenant_id is null then
    return null;
  end if;

  select r.auth_user_id, coalesce(r.email, r.contact_email)
  into v_user_id, v_email
  from public.registrations r
  where r.tenant_id = p_tenant_id
    and lower(coalesce(r.status, r.registration_status, 'pending')) in ('approved', 'active', 'trial')
  order by r.created_at desc
  limit 1;

  -- registrations.auth_user_id can go stale (the auth account gets
  -- reset/recreated after this row was written) - verify it still
  -- points to a real auth.users row before trusting it.
  if v_user_id is not null and not exists (select 1 from auth.users where id = v_user_id) then
    v_user_id := null;
  end if;

  -- Fall back to an email match, same pattern get_my_ungani_staff_access()
  -- and notify_ungani_task_assignment() already use.
  if v_user_id is null and v_email is not null then
    select id into v_user_id from auth.users where lower(email) = lower(v_email) limit 1;
  end if;

  return v_user_id;
end;
$function$;

-- Verify it landed and sanity-check it against a real tenant (replace
-- with a real tenant_id from your own data if you want to hand-check
-- the result before the JS side starts calling it).
select pg_get_functiondef(p.oid) as function_definition
from pg_proc p
join pg_namespace n on n.oid = p.pronamespace
where n.nspname = 'public' and p.proname = 'resolve_ungani_tenant_owner_auth_user_id';
