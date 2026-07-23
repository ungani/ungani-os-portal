-- Read-only. Schema-grounded type-mismatch audit, continuing
-- sql/check-related-fields-types.sql - covers every column any INSERT/UPDATE
-- payload writes to `transactions` and `client_people` across the app
-- (client.html Quick Add, my-money.html, client-shared.js's global Quick
-- Add, my-people.html, admin-people.html). Two columns are of particular
-- interest: transactions.related_person_id and client_people.linked_item_id
-- are meant to be REAL foreign keys (populated from actual <select>
-- dropdowns bound to client_people.id / business_items.id respectively,
-- added this session per the tenant-unit-lease linking work) - unlike the
-- free-text related_person/related_item fields checked earlier. Confirming
-- these exist with a real uuid type (and, ideally, a working FK) matters
-- more here than for the free-text fields.

select table_name, column_name, data_type, udt_name, is_nullable
from information_schema.columns
where table_schema = 'public'
  and table_name in ('transactions', 'client_people')
  and column_name in (
    -- transactions
    'tenant_id', 'type', 'transaction_type', 'category', 'category_name',
    'amount', 'transaction_date', 'payment_method', 'status', 'description',
    'section_label', 'related_person_id', 'related_person', 'property_name',
    'business_type_key', 'section_key', 'created_at', 'updated_at',
    -- client_people
    'full_name', 'person_type', 'phone', 'email', 'company', 'role_title',
    'department', 'relationship_status', 'location', 'last_follow_up_date',
    'assigned_work', 'notes', 'linked_item_id', 'lease_start_date',
    'lease_end_date', 'created_by'
  )
order by table_name, column_name;

-- FK check for the two real-relationship columns - confirms they actually
-- point where the app assumes (client_people.id / business_items.id), not
-- just that they're uuid-typed.
select
  tc.table_name as fk_table,
  kcu.column_name as fk_column,
  ccu.table_name as referenced_table,
  ccu.column_name as referenced_column
from information_schema.table_constraints tc
join information_schema.key_column_usage kcu on tc.constraint_name = kcu.constraint_name
join information_schema.constraint_column_usage ccu on tc.constraint_name = ccu.constraint_name
where tc.constraint_type = 'FOREIGN KEY'
  and (
    (tc.table_name = 'transactions' and kcu.column_name = 'related_person_id')
    or (tc.table_name = 'client_people' and kcu.column_name = 'linked_item_id')
  );
