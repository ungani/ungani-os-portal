-- Read-only schema introspection - returns the real column name, data
-- type, and nullability for every column on every table the app writes
-- to. Requested to make the type-compatibility audit (uuid vs text vs
-- integer etc.) verified against ground truth instead of inferred from
-- app code, which is how the assigned_to bug (tasks.assigned_to typed
-- uuid, but the app has only ever treated it as free text) slipped past
-- the earlier column-existence sweep - that sweep could confirm a column
-- name is real, but had no way to know its actual Postgres type.
select table_name, column_name, data_type, udt_name, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name in (
    'transactions','tasks','documents','client_people','business_records',
    'business_items','business_events','admin_client_messages','client_notices',
    'support_issues','system_notices','team_chat_messages','tenant_sections',
    'ungani_audit_log','ungani_notifications','ungani_upgrade_requests',
    'upgrade_requests','payments','client_settings','ungani_billing_reminder_logs',
    'users','user_preferences','registrations','tenants','packages'
  )
order by table_name, ordinal_position;
