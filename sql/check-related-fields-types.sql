-- Read-only. related_person/related_item are used as plain free-text
-- inputs on tasks, documents, business_records, and business_events -
-- the exact same shape as tasks.assigned_to before it turned out to be
-- uuid-typed with a hidden FK. Checking all of them (plus their outgoing
-- FK constraints, if any) in one pass rather than finding these one at a
-- time via more live crashes.
select table_name, column_name, data_type, udt_name, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name in ('tasks', 'documents', 'business_records', 'business_events')
  and column_name in ('related_person', 'related_item', 'assigned_to')
order by table_name, column_name;

-- Same check, but for any FK constraint any of these columns might carry
-- (the direction that caught us out on assigned_to - a column can look
-- like plain data and still have a constraint attached).
select
  tc.table_name as fk_table,
  kcu.column_name as fk_column,
  ccu.table_name as referenced_table,
  ccu.column_name as referenced_column
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu on tc.constraint_name = kcu.constraint_name
join information_schema.constraint_column_usage ccu on tc.constraint_name = ccu.constraint_name
where tc.constraint_type = 'FOREIGN KEY'
  and tc.table_name in ('tasks', 'documents', 'business_records', 'business_events')
  and kcu.column_name in ('related_person', 'related_item');
