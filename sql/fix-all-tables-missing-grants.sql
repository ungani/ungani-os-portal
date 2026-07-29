-- Comprehensive follow-up to the missing-base-grant bug class that hit
-- tenant_integrations, ungani_email_queue (service_role side), and
-- ungani_support_access_grants individually this session. Generated
-- from a full sweep (sql/check-all-tables-missing-grants.sql) run
-- against the live database and reviewed row by row against each
-- policy's actual qual/with_check text before being turned into a grant
-- below - nothing here was granted mechanically.
--
-- EXPLICITLY EXCLUDED (left untouched, on purpose): the 6 tables with a
-- genuine `qual = false` deny-all DELETE policy named "ungani block
-- direct delete <table>" - business_items, business_records,
-- client_people, support_issues, tasks, transactions. Those are
-- intentional, permanent deny-alls (the app's soft-delete convention),
-- not missing grants. Granting DELETE on those would silently re-open
-- something deliberately locked down.
--
-- A NOTE ON QUERY RELIABILITY: the sweep query had a real bug - it put
-- two unnest() calls (over `roles` and the derived privilege array) in
-- the same SELECT list. When two set-returning functions share a target
-- list, Postgres zips them positionally instead of cross-joining, and
-- NULL-pads whichever array is shorter. This silently turned some rows'
-- `missing_privilege` into NULL instead of the real value. Affected
-- rows below (business_sections, business_types, categories, packages,
-- registrations' insert policy, system_notices, testing_feedback) have
-- their real required privilege re-derived from the policy's name and
-- qual/with_check shape (all unambiguous: a `public_read_active_*`
-- policy with qual and no with_check is SELECT-only; a `*_insert_*` /
-- `*_can_submit_*` policy with with_check=true and no qual is
-- INSERT-only) - marked inline below wherever this applies.
--
-- Two results worth reading before running, not just mechanical fixes:
--   - ungani_email_queue is missing SELECT for `authenticated` - a
--     SEPARATE, additional gap from the earlier fix (sql/fix-email-
--     queue-missing-grants.sql), which only granted `service_role` for
--     the cron sender. This grant is additive to that one, not a
--     replacement.
--   - ungani_user_preferences is missing SELECT for `authenticated` -
--     this is the table the Account Settings consolidation's Theme/
--     Language read path depends on. If this gap is real in your
--     database, that read may currently be silently failing for real
--     users right now.
--
-- Every grant below only adds the specific privilege(s) the sweep (or
-- my re-derivation) actually found missing - never a blanket ALL, and
-- never DELETE unless a real (non-false) delete policy justified it.

-- --- Reference / lookup tables (public_read_active_* pattern) ---
-- All SELECT-only, re-derived per the note above (roles/privilege zip
-- bug produced NULL for these specific rows).
grant select on public.business_sections to authenticated;
grant select on public.business_types to authenticated;
grant select on public.categories to authenticated;
grant select on public.packages to authenticated;
grant select on public.system_notices to authenticated;

-- --- branches ---
-- "UNGANI admin can manage branches" (is_ungani_admin()) and "UNGANI
-- clients can view own branches" (tenant_id match) both need SELECT.
grant select on public.branches to authenticated;

-- --- registrations ---
-- registrations_insert_public (with_check=true, re-derived - the public
-- self-registration insert) needs INSERT.
-- registrations_delete_admin_only (qual=is_ungani_admin(), a REAL
-- admin-gated delete, not a false-block) needs DELETE - RLS still
-- restricts actual deletion to rows where is_ungani_admin() is true.
grant insert, delete on public.registrations to authenticated;

-- --- testing_feedback ---
-- public_can_submit_testing_feedback (with_check=true, re-derived)
-- needs INSERT.
grant insert on public.testing_feedback to authenticated;

-- --- ungani_activity_logs ---
-- Insert (own tenant) + 2 read policies (admin, own tenant).
grant select, insert on public.ungani_activity_logs to authenticated;

-- --- ungani_admin_support_access_sessions ---
grant select on public.ungani_admin_support_access_sessions to authenticated;

-- --- ungani_admins ---
grant select on public.ungani_admins to authenticated;

-- --- ungani_audit_log ---
-- 4 SELECT policies (admin, own actor, own tenant business-record
-- trail, support-access trail). No INSERT policy shown as missing -
-- consistent with writes going through the server-side
-- log-audit-event endpoint, not a direct client insert.
grant select on public.ungani_audit_log to authenticated;

-- --- ungani_billing_records ---
-- Admin insert/update (is_ungani_admin() gated) + 2 read policies
-- (admin, own tenant). RLS still restricts insert/update to admins.
grant select, insert, update on public.ungani_billing_records to authenticated;

-- --- ungani_category_suggestions ---
grant select, insert, update on public.ungani_category_suggestions to authenticated;

-- --- ungani_email_queue ---
-- Additive to the existing service_role grant (sql/fix-email-queue-
-- missing-grants.sql) - this is `authenticated`, a separate gap, for
-- real logged-in users (admin viewing the queue, clients viewing their
-- own queued emails).
grant select on public.ungani_email_queue to authenticated;

-- --- ungani_onboarding_progress ---
grant select on public.ungani_onboarding_progress to authenticated;

-- --- ungani_package_catalog ---
grant select on public.ungani_package_catalog to authenticated;

-- --- ungani_packages ---
grant select on public.ungani_packages to authenticated;

-- --- ungani_recently_deleted ---
grant select on public.ungani_recently_deleted to authenticated;

-- --- ungani_recurring_transactions ---
-- This one legitimately needs DELETE: "ungani recurring delete own
-- tenant" has qual = tenant match AND can_write_ungani_client_data() -
-- a real, scoped delete policy (recurring-transaction TEMPLATES, not
-- the immutable transaction records themselves) - not a false-block.
grant select, insert, update, delete on public.ungani_recurring_transactions to authenticated;

-- --- ungani_setup_options ---
grant select on public.ungani_setup_options to authenticated;

-- --- ungani_smart_action_logs ---
grant select, insert on public.ungani_smart_action_logs to authenticated;

-- --- ungani_staff_section_permissions ---
grant select on public.ungani_staff_section_permissions to authenticated;

-- --- ungani_subscriptions ---
grant select on public.ungani_subscriptions to authenticated;

-- --- ungani_team_members ---
grant select on public.ungani_team_members to authenticated;

-- --- ungani_tenant_safety_settings ---
grant select on public.ungani_tenant_safety_settings to authenticated;

-- --- ungani_user_branch_access ---
grant select on public.ungani_user_branch_access to authenticated;

-- --- ungani_user_preferences ---
-- Backs the Account Settings consolidation's Theme/Language read path -
-- see header note above.
grant select on public.ungani_user_preferences to authenticated;


-- =====================================================================
-- VERIFICATION - run after the grants above.
-- =====================================================================

-- 1. Re-run the full sweep. Expect ONLY the 6 intentional-block DELETE
--    rows left (likely_intentional_block = true) - everything else
--    should be gone.
-- (paste sql/check-all-tables-missing-grants.sql here, or run it as a
--  separate query and check likely_intentional_block = false returns 0
--  rows)

-- 2. Spot-check the two flagged tables directly.
select grantee, privilege_type
from information_schema.table_privileges
where table_schema = 'public' and table_name = 'ungani_email_queue'
order by grantee, privilege_type;

select grantee, privilege_type
from information_schema.table_privileges
where table_schema = 'public' and table_name = 'ungani_user_preferences'
order by grantee, privilege_type;
