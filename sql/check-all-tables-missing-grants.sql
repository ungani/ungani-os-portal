-- Read-only, systematic sweep for the "missing base table GRANT" bug
-- class that has now hit THREE tables this session (tenant_integrations,
-- ungani_email_queue, ungani_support_access_grants), each discovered
-- separately, one at a time, only after a real user hit a permission
-- error. This query exists so further occurrences are caught here
-- instead of in production.
--
-- Root cause, confirmed 3x: RLS policies define WHICH ROWS a role can
-- see/touch. They do NOT grant baseline table-level access - that is a
-- separate, independent privilege system (information_schema.table_
-- privileges / GRANT). A table can have perfect RLS policies and still
-- be 100% unusable because nobody ever ran a `grant select, insert,
-- update on ... to authenticated;` for it.
--
-- v2: also surfaces each implicated policy's qual/with_check text, and
-- a best-effort "looks like a deliberate block" flag. A DELETE policy
-- whose qual is literally `false` (or similar) is NOT a missing grant -
-- it's a documented, intentional deny-all, matching this app's
-- soft-delete convention. Granting DELETE on a table like that would be
-- wrong even though the sweep technically finds "a DELETE policy with
-- no matching grant." Always read likely_intentional_block and the
-- qual/with_check columns before turning any row below into a GRANT
-- statement - do not mechanically grant every row this query returns.
--
-- Safe to run any time - pure SELECT, no writes, no locks beyond a
-- normal read.

with policy_requirements as (
  select
    p.schemaname,
    p.tablename,
    p.policyname,
    p.qual,
    p.with_check,
    unnest(p.roles) as role_name,
    unnest(
      case p.cmd
        when 'ALL' then array['SELECT', 'INSERT', 'UPDATE', 'DELETE']
        else array[p.cmd]
      end
    ) as required_privilege
  from pg_policies p
  where p.schemaname = 'public'
),
normalized as (
  select
    schemaname, tablename, policyname, qual, with_check,
    case when role_name = 'public' then 'authenticated' else role_name end as effective_role,
    required_privilege
  from policy_requirements
  where role_name in ('public', 'authenticated', 'anon', 'service_role')
)
select distinct
  n.schemaname,
  n.tablename,
  n.effective_role as role_needing_grant,
  n.required_privilege as missing_privilege,
  n.policyname as implied_by_policy,
  n.qual as policy_qual,
  n.with_check as policy_with_check,
  case
    when n.required_privilege = 'DELETE'
      and (
        lower(coalesce(n.qual, '')) in ('false', '(false)')
        or n.policyname ilike '%block%delete%'
        or n.policyname ilike '%no delete%'
        or n.policyname ilike '%cannot delete%'
        or n.policyname ilike '%deny delete%'
      )
    then true
    else false
  end as likely_intentional_block
from normalized n
left join information_schema.table_privileges tp
  on tp.table_schema = n.schemaname
  and tp.table_name = n.tablename
  and tp.grantee = n.effective_role
  and tp.privilege_type = n.required_privilege
where tp.grantee is null
order by n.tablename, n.effective_role, n.required_privilege;

-- Interpreting the results:
--   Zero rows = every policy's implied role/privilege has a matching
--     base grant.
--   A row with likely_intentional_block = true = almost certainly NOT a
--     bug - leave it alone, do not generate a grant for it. Confirm by
--     reading policy_qual yourself (should read `false` or equivalent).
--   A row with likely_intentional_block = false = a genuine candidate
--     for the missing-grant bug - but still read policy_qual/
--     policy_with_check before granting, the heuristic above is a name/
--     literal-text match, not a guarantee.
