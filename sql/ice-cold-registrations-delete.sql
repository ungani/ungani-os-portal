-- Deletes the 2 confirmed-safe leftover registrations rows for
-- "Ice cold Worldwide Logistics Limited" (olensie@gmail.com / Erick
-- Olensi Osinya) - duplicate submissions 7 seconds apart, the same
-- duplicate-submission bug task #11 is tracking. Confirmed via
-- sql/ice-cold-registrations-investigate.sql: no Auth account exists
-- for this email, and zero references in tenants or users. Nothing else
-- in the schema has an FK to registrations (it's a pre-approval holding
-- table only), so this is a plain, low-stakes delete - but still scoped
-- to the exact 2 IDs (not a name/email match) and wrapped in the same
-- safety-count-check pattern as sql/tenant-cleanup-delete.sql, since any
-- irreversible delete gets that treatment regardless of how low-stakes
-- it looks.

begin;

do $$
begin
  if (
    select count(*) from registrations
    where id in ('f5d13226-64ee-40a4-8451-2af0d05695a5', 'd256b874-6ebd-45ca-b027-8e27c17f31ff')
  ) <> 2 then
    raise exception 'Expected exactly 2 matching registrations rows - found a different count. Aborting, re-verify before retrying.';
  end if;
end $$;

delete from registrations
where id in ('f5d13226-64ee-40a4-8451-2af0d05695a5', 'd256b874-6ebd-45ca-b027-8e27c17f31ff');

-- Final check before commit - confirms both are gone.
do $$
begin
  if exists (
    select 1 from registrations
    where id in ('f5d13226-64ee-40a4-8451-2af0d05695a5', 'd256b874-6ebd-45ca-b027-8e27c17f31ff')
  ) then
    raise exception 'A row still exists after delete - aborting commit.';
  end if;
end $$;

commit;
