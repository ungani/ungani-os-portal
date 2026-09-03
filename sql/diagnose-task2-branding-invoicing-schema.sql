-- Task 2 (branding + customer invoicing) schema investigation. Read-only.
-- Paste back the full output of all 6 queries.

-- 1. Full current tenants table schema - need to see every column that
-- already exists (confirmed so far via code: company_name, business_type,
-- business_type_key, selected_sections, vat_registered, default_vat_rate,
-- default_vat_pricing_mode, multi_currency_enabled) before deciding what
-- branding columns are genuinely new vs. already present under a
-- different name.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'tenants'
order by ordinal_position;

-- 2. Full current registrations table schema - confirmed via SQL source
-- reads that business_name, contact_name, contact_person, contact_email,
-- phone already exist here. Need the complete list, and specifically
-- whether any address/kra_pin/owner_name-equivalent column already
-- exists under a different name.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'registrations'
order by ordinal_position;

-- 3. Full current client_people table schema - the closest existing
-- "customer" concept (used across all 19 business types per
-- my-people.html/client.html). Need to see if it's a viable source for
-- the new invoice feature's customer picker, or if a dedicated
-- customers/invoice-recipient concept makes more sense.
select column_name, data_type, is_nullable, column_default
from information_schema.columns
where table_schema = 'public' and table_name = 'client_people'
order by ordinal_position;

-- 4. Existing Supabase Storage buckets - need to know if any bucket
-- already exists (e.g. for documents) that the new logo upload could
-- reuse, or if a dedicated bucket needs to be created from scratch.
select id, name, public, created_at
from storage.buckets
order by created_at;

-- 5. Any existing per-tenant sequential-numbering pattern anywhere in
-- the schema (a real precedent to follow, rather than inventing a new
-- pattern). Checking for sequence objects and any column with an
-- obviously counter-like default.
select sequence_name
from information_schema.sequences
where sequence_schema = 'public';

-- 6. Confirm get_my_ungani_tenant_id() still resolves as expected (same
-- function every other tenant-scoped RPC in this project uses) - just a
-- sanity check before designing new RLS policies against it.
select routine_name
from information_schema.routines
where routine_schema = 'public' and routine_name = 'get_my_ungani_tenant_id';
