-- Read-only. The opposite direction of sql/check-fk-dependents.sql (which
-- checked what points AT tasks.assigned_to) - this checks what
-- tasks.assigned_to itself points TO, which is what the failed migration
-- revealed exists (constraint name "tasks_assigned_to_fkey" from the
-- error) but didn't identify.
select
  tc.constraint_name,
  tc.table_name as fk_table,
  kcu.column_name as fk_column,
  ccu.table_name as referenced_table,
  ccu.column_name as referenced_column
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu on tc.constraint_name = kcu.constraint_name
join information_schema.constraint_column_usage ccu on tc.constraint_name = ccu.constraint_name
where tc.constraint_type = 'FOREIGN KEY'
  and tc.table_name = 'tasks'
  and kcu.column_name = 'assigned_to';
