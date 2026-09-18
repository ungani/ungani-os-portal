-- ============================================================
-- UNGANI OS: missing service_role grants for the new M-Pesa C2B
-- confirmation handler (handleC2BConfirmation in api/mpesa-stk-push.js)
--
-- That handler does direct table access via the service-role Supabase
-- client (not through a security-definer RPC) - it needs to INSERT
-- into transactions (to record the captured payment) and SELECT from
-- client_people (to match the payer's phone). Neither grant existed:
-- transactions only had SELECT granted to service_role (from an
-- earlier, unrelated fix), and client_people had no service_role grant
-- at all. Same "RLS enabled but service_role never granted for a new
-- code path" bug class already found and fixed repeatedly this
-- session - caught here before deploy rather than after a real
-- payment silently failed to record.
-- ============================================================

grant insert on public.transactions to service_role;
grant select on public.client_people to service_role;

-- ============================================================
-- VERIFICATION
-- ============================================================
select table_name, privilege_type
from information_schema.role_table_grants
where grantee = 'service_role'
  and table_name in ('transactions', 'client_people')
order by table_name, privilege_type;
