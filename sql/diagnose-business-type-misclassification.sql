-- UNGANI OS: diagnostic only, no writes. Run all 4 queries and paste back
-- the literal output for every one (including "no rows" if that's what
-- a query returns) - this is confirming a suspected app-wide business-
-- type misclassification bug before any fix is designed, not something
-- to summarize/paraphrase.
--
-- Context: client-side business-type detection (ungani-business-config.js
-- resolve()) keyword-matches a blob of tenant text and can misclassify a
-- tenant's ENTIRE app experience (not just Items) if their business name
-- happens to contain a word that belongs to a DIFFERENT type's keyword
-- list (e.g. "Beauty" anywhere in the name matches Salon's keyword list
-- and would hijack a Retail tenant into Salon). While investigating the
-- fix, found that approve_ungani_registration() ALSO cross-references a
-- separate public.business_types table when approving a registration -
-- a second, independent source of business-type truth that may or may
-- not agree with ungani-business-config.js's own type keys/names. These
-- queries check both: the real tenant likely affected, and whether that
-- second table's data is even usable as an authoritative signal.

-- ============================================================================
-- QUERY 1: business_types table - real columns (don't assume names).
-- ============================================================================
select column_name, data_type
from information_schema.columns
where table_schema = 'public' and table_name = 'business_types'
order by ordinal_position;

-- ============================================================================
-- QUERY 2: business_types table - full contents. This is a config/lookup
-- table, expected to be small - need to see every row to know whether its
-- keys/slugs/names line up with ungani-business-config.js's type keys
-- (real_estate, salon, retail, healthcare, etc.) or use a different
-- convention.
-- ============================================================================
select *
from public.business_types
order by 1;

-- ============================================================================
-- QUERY 3: the specific tenant(s) that look like the reported Retail /
-- Hardware / Cosmetics / Beauty case - matches loosely on purpose (ilike
-- both business_type and business_type_key) since we don't have the
-- tenant's id or exact name yet.
-- ============================================================================
select
  id,
  business_name,
  business_type,
  business_type_key,
  business_type_id,
  selected_sections,
  created_at
from public.tenants
where business_type ilike '%retail%'
   or business_type_key ilike '%retail%'
   or business_name ilike '%hardware%'
   or business_name ilike '%cosmetic%'
   or business_name ilike '%beauty%'
order by created_at desc;

-- ============================================================================
-- QUERY 4: every tenant's business_name/business_type/business_type_key/
-- business_type_id, so we can see real-world drift patterns across the
-- whole (small, pre-launch) tenant base, not just the one reported case -
-- this is what lets us confirm the fix closes the gap for all business
-- types, not just Retail.
-- ============================================================================
select
  id,
  business_name,
  business_type,
  business_type_key,
  business_type_id,
  selected_sections
from public.tenants
order by created_at desc;
