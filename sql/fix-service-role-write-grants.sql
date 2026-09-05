-- Fixes a genuinely serious, long-standing bug: audit logging has NEVER
-- successfully written a row since it was built (count=0, max/min
-- created_at=null, confirmed live). app_error_log has the identical gap,
-- caught before it ever went live thanks to this same investigation.
--
-- Root cause: both tables were created without the table-level GRANT that
-- PostgREST/Supabase's service_role needs to write, even though the
-- service-role key bypasses RLS entirely - RLS and base GRANTs are two
-- separate Postgres mechanisms, and this project's default-privilege
-- inheritance apparently doesn't apply to every newly created table.
--
-- Both API endpoints only ever call .insert() via the service-role
-- client - no select/update/delete from that role - so granting exactly
-- that, not a blanket ALL, matching this app's least-privilege pattern.

grant insert on public.ungani_audit_log to service_role;
grant insert on public.app_error_log to service_role;

-- Verification - run and paste back the output.
select table_name, grantee, privilege_type
from information_schema.role_table_grants
where table_schema = 'public'
  and table_name in ('app_error_log', 'ungani_audit_log')
  and grantee = 'service_role'
order by table_name, privilege_type;
