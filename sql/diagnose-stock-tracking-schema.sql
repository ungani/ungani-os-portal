-- Confirms the real current schema before proposing a stock-tracking data
-- model: (1) business_items' actual columns (confirm no orphaned
-- quantity/stock column already exists outside custom_fields), (2) the
-- existing boolean-toggle columns on tenants for naming-convention
-- consistency, (3) confirms no stock_movements-style table already exists
-- under a name the earlier code search wouldn't have caught.

select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'business_items'
order by column_name;

select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'tenants'
  and (column_name ilike '%enabled%' or column_name ilike '%toggle%' or data_type = 'boolean')
order by column_name;

select table_name
from information_schema.tables
where table_schema = 'public'
  and (table_name ilike '%stock%' or table_name ilike '%inventory%' or table_name ilike '%movement%');
