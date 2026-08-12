-- Corrected query - permissions live in public.ungani_staff_section_permissions
-- (team_member_id, tenant_id, section_key, can_view, can_create, can_edit,
-- can_delete), not a column on ungani_team_members. Confirmed via
-- sql/staff-role-permission-presets.sql's own sourced comments.
--
-- That same file's role presets already show ALL THREE default roles
-- (manager/staff/viewer) explicitly exclude "settings" - it's owner-only
-- in every preset, by design. This confirms whether Chris's real row
-- matches that default (never touched) or was manually granted access.
--
-- OUTCOME (2026-08-12): section_key came back NULL - no permission row
-- exists at all for "settings" for Chris. Confirmed root cause: he had
-- zero access to my-settings.html, the only page with a manual "Enable
-- Notifications" fallback at the time. Fixed by relocating that panel to
-- client-notifications.html, which get_my_ungani_staff_access() force-
-- grants view access to for every staff member regardless of what's
-- stored (sql/fix-staff-access-status-coalesce-order.sql, lines 143-145)
-- - see the "Browser Notifications" panel now on client-notifications.html.

select tm.id as team_member_id, tm.full_name, tm.role_key,
       sp.section_key, sp.can_view, sp.can_create, sp.can_edit, sp.can_delete
from public.ungani_team_members tm
left join public.ungani_staff_section_permissions sp
  on sp.team_member_id = tm.id and sp.section_key = 'settings'
where tm.auth_user_id = 'a358312c-4670-486f-a106-555d8ca067ee';
