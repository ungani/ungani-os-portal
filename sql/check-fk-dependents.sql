-- Read-only. Confirms whether any OTHER table has a foreign key pointing
-- AT tasks.assigned_to (which would block/complicate the type change).
-- Should return zero rows - no app code anywhere treats this column as a
-- real reference, so this is a final confirmation, not an expected find.
select
  tc.table_name as referencing_table,
  kcu.column_name as referencing_column,
  ccu.table_name as referenced_table,
  ccu.column_name as referenced_column
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu on tc.constraint_name = kcu.constraint_name
join information_schema.constraint_column_usage ccu on tc.constraint_name = ccu.constraint_name
where tc.constraint_type = 'FOREIGN KEY'
  and ccu.table_name = 'tasks'
  and ccu.column_name = 'assigned_to';
