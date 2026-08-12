-- 5th recurrence of the missing-grant bug class (see memory:
-- missing_grant_bug_class_systemic_sweep) - RLS policies were correctly
-- defined, but the explicit base-table GRANT to service_role was never
-- added, so PostgREST rejects supabaseAdmin's queries with "permission
-- denied for table X" even though service_role should be able to bypass
-- RLS entirely once it can reach the table at all.
--
-- Confirmed live: api/send-event-push.js's handleTaskAssignment() hit
-- exactly this on the "tasks" table (real task 19dd1060-b93e-4e42-9438-
-- 3522829a6171, confirmed to exist via direct SQL, still returned
-- "permission denied for table tasks" through the API).
--
-- Rather than fix tasks alone and hit the same wall on the next handler
-- we test, this covers every table api/send-event-push.js's
-- supabaseAdmin touches directly (grep-verified against the file),
-- matched to the exact privilege each handler actually uses - no more,
-- no less.
--
-- tasks and transactions are 2 of the project's 6 intentional
-- "block direct delete" tables (qual = false delete policy) - DELETE is
-- deliberately NOT granted below for either.

-- Query 1: diagnostic - what service_role currently has on these tables,
-- run this first to see the real starting state before the grants below
-- change anything.
select table_name, privilege_type
from information_schema.table_privileges
where grantee = 'service_role'
  and table_schema = 'public'
  and table_name in (
    'tasks', 'registrations', 'ungani_push_subscriptions', 'ungani_push_sent_log',
    'support_issues', 'team_chat_messages', 'ungani_team_members', 'admin_client_messages',
    'tenants', 'ungani_record_comments', 'ungani_record_activity', 'documents', 'transactions'
  )
order by table_name, privilege_type;

-- Query 2: the actual fix. GRANT is idempotent - safe to run even if a
-- privilege is already present.

-- Read-only lookups (handleTaskAssignment, resolveRelevantParty).
grant select on public.tasks to service_role;
grant select on public.transactions to service_role;

-- Read-only lookups (handleNewRegistration, resolveTenantOwnerAuthUserId
-- reads registrations too, but that path is via a SECURITY DEFINER RPC
-- so doesn't need a direct grant - this covers handleNewRegistration's
-- direct .from("registrations") call).
grant select on public.registrations to service_role;

-- sendToSubscriptions/pushToUser read every subscription row it sends
-- to, and prune (DELETE) a subscription on a 404/410 from the push
-- service (dead endpoint cleanup) - this table genuinely needs DELETE,
-- unlike tasks/transactions above.
grant select, delete on public.ungani_push_subscriptions to service_role;

-- alreadySent() reads, markSent() inserts - the dedup table.
grant select, insert on public.ungani_push_sent_log to service_role;

-- handleSupportResponse.
grant select on public.support_issues to service_role;

-- handleTeamChatMessage.
grant select on public.team_chat_messages to service_role;

-- Owner/team-member auth_user_id lookups across multiple handlers.
grant select on public.ungani_team_members to service_role;

-- handleAdminClientMessage / handleClientAdminMessage (same table, both
-- directions of the admin<->client chat).
grant select on public.admin_client_messages to service_role;

-- handleClientAdminMessage's business_name lookup for the push body text.
grant select on public.tenants to service_role;

-- Ungani Connect push handlers.
grant select on public.ungani_record_comments to service_role;
grant select on public.ungani_record_activity to service_role;
grant select on public.documents to service_role;

-- Query 3: re-check - confirm every grant above actually landed.
select table_name, privilege_type
from information_schema.table_privileges
where grantee = 'service_role'
  and table_schema = 'public'
  and table_name in (
    'tasks', 'registrations', 'ungani_push_subscriptions', 'ungani_push_sent_log',
    'support_issues', 'team_chat_messages', 'ungani_team_members', 'admin_client_messages',
    'tenants', 'ungani_record_comments', 'ungani_record_activity', 'documents', 'transactions'
  )
order by table_name, privilege_type;
