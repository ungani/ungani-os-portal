# UNGANI OS — Architecture Overview

Written for a human engineer picking this codebase up cold. This is not a
feature list — it's the shape of the system: what's shared, what's
per-business-type, where things live, and the conventions that keep 19
different kinds of businesses running on one codebase without 19 copies of
everything.

## What this is

A multi-tenant business-management platform (tasks, money, people, items,
calendar, documents) serving 19 different business types (Logistics, Real
Estate, Retail, Hospitality, Automotive, School, Salon, Security, Gym, and
more) from **one shared schema and one shared set of pages** — not a
different app per vertical. No build step: plain HTML/CSS/JS files served
directly, Supabase (Postgres + Auth + RLS) as the backend, Vercel for
hosting + serverless functions + cron. Deploy is `git push` to `main`.

Two shells share almost everything:
- **Client** (`client.html` + ~30 `my-*.html` pages) — what a business
  owner/staff member uses day to day.
- **Admin** (`admin.html` + `admin-*.html` pages) — UNGANI's own internal
  staff, managing every tenant across the platform.

## The core idea: shared tables, business-type-aware rendering

There is no `logistics_items` table and a separate `salon_items` table.
Every business type's "Items" are rows in one `business_items` table;
every "Person" is a row in one `client_people` table; every calendar entry
is a row in one `business_events` table; every money record is a row in
one `transactions` table. What differs per business type is:

1. **Vocabulary** — a Logistics owner sees "Trips" where a Salon owner sees
   "Appointments," but both are `business_events` rows.
2. **Which extra columns/fields apply** — a Real Estate item has
   `bedrooms`/`bathrooms`; a School "Class" item has a `job_stage`-backed
   grade level. Same table, different fields surfaced.
3. **Dashboard content** — what KPIs and quick actions render on
   `client.html` for that tenant.

### The resolution entry point: `ungani-business-config.js`

Everything branches from one thing: **`UnganiBusinessConfig.resolve(tenant)`**
(`ungani-business-config.js:3304`), which takes a tenant row and returns its
matched entry from the `TYPES` array (19 entries, one per business type —
`grep -c "^  {" ungani-business-config.js` → 19). Each entry carries the
vocabulary (`itemsLabel`, `peopleLabel`, `tasksLabel`, ...), the field-set
keys, and (for types with them) a `sections` array for sub-verticals
(Logistics has Cold Chain / Clearing & Forwarding / Transport, for
example).

Every page-level "which business type am I" check ultimately calls
`resolve()` or one of the `detect*()` helper functions built on top of it
(`detectRealEstate`, `detectLogistics`, `detectSchool`, etc. — each page
that needs one defines its own, following the same two-tier pattern: try
`UnganiBusinessConfig.resolve()` first, fall back to keyword-matching on
`business_type`/`business_type_key` text if the canonical resolver comes
back empty). **Always trust the canonical resolver over keyword-matching
when both are available** — a real bug this session
(`nia_industry_vocabulary_architectural_gap`, and the original
`isRealEstate` "Demo Dyar Property" bug) came from keyword-matching running
*before* the real resolver got a chance.

### `ITEM_FIELD_SETS`: the data-driven item form

`my-items.html` (3,378 lines) doesn't have per-business-type form code. It
has one generic form renderer driven by `UnganiBusinessConfig.resolveItemFieldSet(tenant, sectionLabel)`,
which returns an object shaped like:

```js
{
  valueLabel: "Job Value",              // label for the price/value field
  statusOptions: ["quoted", "in production", ...],
  identityFieldId: "sku",               // optional - used for duplicate detection
  fields: [
    { id: "job_stage", label: "Job Stage", type: "text", column: "job_stage", placeholder: "..." },
    { id: "class_subject", label: "Subject", type: "text" }  // no `column` = goes into custom_fields JSONB
  ]
}
```

The renderer (`renderExtraFieldHtml`/`renderExtraFieldsHtml` in
`my-items.html`) turns that into inputs; the save path
(`saveItem()`) loops the same `fields` array and writes each value either
to a real column (if `field.column` is set) or into the row's
`custom_fields` JSONB (if not). **This is the key extensibility lever**:
adding a new field for one business type almost never means a migration —
add an entry to that type's field set in `ungani-business-config.js`, and
if it doesn't need to be queried/indexed, skip the `column` key entirely.
`business_items.custom_fields` was added specifically for this (Phase 2,
this session's predecessor work).

Field sets are registered in the `ITEM_FIELD_SETS` object at the bottom of
`ungani-business-config.js`, keyed by section key first, then business-type
key as fallback (`resolveItemFieldSet`'s actual lookup order).

## The "5 clusters": how operational activity connects to money

Five business-type groups needed a genuinely new *kind* of record beyond
generic Tasks/Items, and all five follow the same shape: additive nullable
columns on an existing table (never a new table unless the data is truly
many-to-many), a `compute*Settlement()` helper in `client.html` that reads
those columns plus matching `transactions` rows to show a paid/owed
figure, and a picker in `my-money.html` to link a payment back to the
record.

| Cluster | Business types | Table extended | Migration file |
|---|---|---|---|
| 1. Booking (deposit/balance) | Tourism, Events, Photography, Hospitality | `business_events` | `sql/cluster1-*.sql` |
| 2. Job (work-order stages) | Automotive, Printing, Furniture, Construction | `business_items` | `sql/cluster2-job-workorder-stages.sql` |
| 3. Deployment (roster/shift) | Security, Cleaning | `business_events` | `sql/cluster3-deployment-roster-scheduling.sql` |
| 4. Commitments (lease/membership/contract) | Real Estate, Gym, Security, Cleaning | new table `ungani_commitments` (genuinely recurring, many-per-person) | `sql/cluster4-commitments.sql` |
| 5. Appointment (staff + no-double-booking) | Salon, Healthcare, Gym | `business_events` | `sql/cluster5-appointment-scheduling.sql` |

Cluster 4 is the one exception to "extend, don't create a table" — leases/
memberships/contracts are genuinely recurring with their own lifecycle
(active/terminated/frozen, auto-renew), so they got `ungani_commitments`, a
real table, gated behind a Settings toggle (`tenants.commitments_enabled`)
that also relabels the sidebar per business type ("Leases" for Real
Estate, "Memberships" for Gym).

**Gotcha found live this session**: a migration file being internally
correct does not mean it ran. `get_my_ungani_commitments()` and
`owner_upsert_ungani_commitment()` were both fully defined in
`sql/cluster4-commitments.sql` but returned zero rows from
`information_schema.routines` in production — the file (or just those two
statements) was never actually executed. **Always verify a migration
landed by querying `information_schema.tables`/`information_schema.routines`
live, not by re-reading the file.**

Cluster 5's no-double-booking check (`checkAppointmentConflict()` in
`my-calendar.html`) is an application-level check-then-insert, not a
database exclusion constraint — a genuine (documented, accepted) race is
possible under truly concurrent simultaneous saves.

## Universal 360: the profile-panel system

Five entity types (Person, Organization, Document, Item/Location, Event)
have a "360 view" — click a row anywhere in the app, get a slide-in panel
showing that record's connections (linked people, payment history, related
tasks, event history) rather than just an edit form. This lives in
`client-shared.js` as a family of functions:
`openUnganiPersonProfile()`, `openUnganiOrganizationProfile()`,
`openUnganiDocumentProfile()`, plus item/location-specific and
event-specific panel builders. All of them render into the same generic
side-panel shell:

```js
UnganiClientShared.openSidePanel({ title, bodyHtml, onOpen })
UnganiClientShared.closeSidePanel()
```

**Known gotcha, fixed this session**: inside the HTML strings these
functions generate, Edit/Discussion buttons and cross-links used bare
`onclick="closeSidePanel(); openPersonModal('id')"`. `closeSidePanel` is
only ever exposed as `UnganiClientShared.closeSidePanel` — never a bare
global — so every one of those clicks threw `ReferenceError` before
`openPersonModal` (or whatever the second call was) ever ran. This was
broken **app-wide, on every business type, since these panels shipped**,
and nothing in prior testing caught it because testing checked the panel
*rendered*, not that its embedded buttons' click chain *completed*.
**If you add a new onclick string inside a `client-shared.js` template
literal that needs a shared-module function, always prefix it
`UnganiClientShared.foo()` — never assume a shared function is a bare
global just because it's callable that way from real `<script>` code in
the same file.**

Each page wires its own row-click handler to call the relevant
`openXProfile(id)` function with a small options object naming its own
local functions by string (`{ editFnName: "openPersonModal", ... }`) —
this is how one shared panel implementation can call back into
page-specific edit/delete/discuss functions without a hard import.

## Standing conventions

- **Tenant scoping**: every table has `tenant_id`; every RLS policy and
  every RPC filters on it via `get_my_ungani_tenant_id()`. There is no
  query anywhere that should omit this filter.
- **Soft delete**: `deleted_at is null` gates almost every read. Hard
  deletes are rare and deliberate (Recently Deleted / restore flows exist
  precisely because of this).
- **RPC naming**: `owner_upsert_ungani_*` for owner-only writes,
  `get_my_ungani_*` for tenant-scoped reads, `check_my_ungani_*` for
  validation-only calls (duplicate checks, etc.), `is_*`/`is_ungani_admin`
  for boolean permission checks. All are `security definer` with
  `set search_path to 'public'`.
- **Never fabricate a function body.** If you need to extend an existing
  RPC and don't have its current live source in front of you, run
  `select pg_get_functiondef('public.the_function'::regproc)` (or the
  `information_schema.routines` equivalent) and get the real body pasted
  back before writing a byte of the "updated" version. This bit this
  project's history at least twice before the discipline was made
  explicit — a plausible-looking guessed rewrite of an RPC silently
  dropped real parameters/joins/exception handling.
- **Additive-only migrations.** New columns are nullable, existing columns
  are never renamed, existing function signatures are never removed
  without checking every call site first (a stale 7-param
  `owner_upsert_ungani_team_member` overload sat alongside the real 9-param
  one for a while — always confirm the *real* live signature via
  `information_schema.routines`, not by grepping the newest-looking SQL
  file, before touching a shared RPC).
- **Business-type-aware wording, not business-type-aware code paths,
  wherever possible.** The preference throughout this codebase is one
  code path with a vocabulary/config lookup, not an `if (isLogistics) {...}
  else if (isSalon) {...}` fork repeated on every page. `ITEM_FIELD_SETS`
  and the cluster settlement functions are the model to follow when adding
  a new business-type-specific behavior.
- **`custom_fields` JSONB is the default extension point** for anything
  that doesn't need to be filtered/joined/indexed on. Reach for a real
  column only when a feature genuinely needs to query on it (and then add
  the index — see the Performance section below).

## Nia (the in-app assistant)

`nia-assistant.js` (7,704 lines) is a single shared module included on
every client and admin page. It renders its own floating action button
(`renderFab()`) and handles both scripted intents (keyword-matched
business questions — "how much do I owe on rent," "who's booked this
week") and free-text fallback. Business-type vocabulary awareness for Nia
lives in the same `PAGE_CONFIGS`-style structures inside this file, kept
in sync with `ungani-business-config.js` by convention, not by import (if
you add a new Item/Person/Task vocabulary term to the business config,
check whether Nia's keyword matching needs the same update — this has
been a recurring gap, tracked as "Nia keyword coverage audit" tasks
several times this session and its predecessors).

## Where things live (file map)

```
client.html              — the client dashboard shell (bespoke, not on the shared sidebar)
client-shared.js          — shared client-side module: auth, nav, 360 panels, modals, toasts,
                             Team Chat popup, notifications, theme, push
admin.html, admin-*.html  — admin pages, all on the shared admin shell
admin-shared.js           — admin equivalent of client-shared.js
ungani-business-config.js — the 19 business types, ITEM_FIELD_SETS, resolve()
ungani-presets.js         — per-type UI presets (task types, categories, etc.)
ungani-nav-config.js      — client sidebar structure (shared across my-*.html pages)
ungani-admin-nav-config.js— admin sidebar structure
ungani-theme.js           — light/dark theme, shared by every page
nia-assistant.js          — Nia, the in-app assistant
team-chat-shared.js       — Team Chat (internal messaging) shared module
ungani-connect-panel.js   — "Discuss" panel (comments/activity timeline) shared module
push-notifications.js     — web push subscribe/badge helpers
my-*.html                 — ~30 client feature pages (Tasks, Money, People, Items,
                             Calendar, Documents, Quotations, Orders, ...), each on the
                             shared sidebar shell via UnganiClientShared.initPage({pageKey, ...})
sql/                       — every migration ever written this project's life (212 files at
                             last count) - NOT all of them are guaranteed to have been run;
                             see "Verifying a migration landed" below
api/                       — Vercel serverless functions (cron jobs, webhook receivers,
                             email/push senders)
```

Every shared-shell client page follows the same boot pattern:

```js
window.addEventListener("load", function () {
  UnganiClientShared.initPage({
    pageKey: "items",           // must match ungani-nav-config.js's key for sidebar highlighting
    pageTitle: "...",
    pageSubtitle: "...",
    onReady: startItemsPage      // your page's real init function, called once auth+tenant context is ready
  });
});
```

`initPage()` (`client-shared.js:1944`) handles auth, Supabase client
creation, tenant resolution, theme, offline-fallback, and sidebar
rendering before calling your `onReady` callback with a `context` object
(`{ supabaseClient, tenantId, tenant, ... }`) that every page's functions
thread through.

## Scalability notes (from this session's architecture review)

No N+1 query patterns were found anywhere in the clusters or 360 panels —
everything either batches via `Promise.all`, uses a bounded `.limit()`
select, or computes in-memory from an already-fetched array
(`computeBookingSettlement`/`computeJobSettlement`/etc. in `client.html`
are pure `.filter()`/`.reduce()` over data the dashboard already loaded in
one bounded batch of `Promise.all(safeSelect(table, 250))` calls — see
`loadDashboardData` in `client.html`).

The real risk pattern found was **missing indexes on newer columns that
are genuinely filtered/joined on in hot paths** — e.g.
`checkAppointmentConflict()` running `.eq("tenant_id",...).eq("staff_person_id",...).eq("event_date",...)`
against `business_events` on every single appointment save, with no
supporting index. `sql/perf-missing-indexes-clusters-and-360.sql` covers
the ones found and confirmed as of this session; if you add a new
cluster-style column that gets filtered on in a query that runs on every
save/load, add its index in the same migration, not as an afterthought.

### Verifying a migration landed

Reading a `.sql` file tells you what *should* be true, not what *is* true.
Before assuming a table/column/function exists in production:

```sql
select table_name from information_schema.tables
where table_schema = 'public' and table_name = 'the_table';

select column_name from information_schema.columns
where table_schema = 'public' and table_name = 'the_table' and column_name = 'the_column';

select routine_name, security_type from information_schema.routines
where routine_schema = 'public' and routine_name = 'the_function';
```

This project has hit "the file is correct but was only partially run" at
least twice (Cluster 4's commitments RPCs, this session; the audit_log
write path, earlier).

## Known gaps at time of writing (not fixed, flagged honestly)

- **Per-sub-type dashboard content** for the Education vertical (Primary
  School / High School / College) — `renderSchoolDashboard()` is still one
  flat function; `business_sub_type_key` has zero references in
  `client.html`.
- **Bulk invoicing** for Education (invoice a whole class at once) — not
  built.
- **Cluster 4 translatable strings** — not wrapped in a `t()` helper yet.
- **A systemic PUBLIC-execute grant sweep** was flagged as needed but not
  completed — some RPCs may be callable without the `authenticated` role
  check that most of the codebase relies on. Worth a dedicated audit
  before assuming every RPC is safe by default.
- **Safari-specific calendar overlap bug** — investigated, not resolved.
  No viable local testing path was found (Playwright's webkit engine isn't
  supported on the macOS version this was investigated on; `safaridriver`
  requires interactive `sudo`; AppleScript automation is blocked by
  accessibility permissions in this environment). Needs either a real
  Safari-capable CI runner or manual reproduction on an actual Mac with
  permissions granted.
- **i18n** (multi-language support) — scoped and phased, not started.
- A long tail of smaller deferred items lives in the project's own task
  tracker/memory notes (theme consistency audit, button-style
  consolidation across ~12 standalone pages, a few in-progress
  investigations) — check the current task list rather than assuming this
  document is exhaustive on backlog state, since that changes session to
  session and this document does not.
