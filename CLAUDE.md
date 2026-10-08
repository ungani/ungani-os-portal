# UNGANI OS - Project Rules

Standing rules for working in this repo. Short by design - the reasoning behind each lives in memory; this file is the checklist.

1. **Every feature ships with Nia and both languages.** Before a feature or change is done: Nia can answer the obvious questions about it with the same numbers the page shows, and every new user-facing string has a real Swahili translation in `I18N_TRANSLATIONS.sw` (`client-shared.js`) - not just added to `.en` and left to fall back. Flag this explicitly when reporting a feature done; don't wait to be asked.

2. **Never touch the real admin account without asking.** No login/MFA changes on chris@ungani.com without explicit sign-off. Never let his real password persist in scratch files.

3. **Exhaustive coverage by default.** "Done" means checked across all 19 business types/pages, not just the one that prompted the work.

4. **Every operational record connects to Money.** Trip/Table/Job/Booking-style records must link live to real Money, not just display a number that isn't backed by a transaction.

5. **Flag pending migrations loudly.** Any SQL written but not yet run must be unmissable in the report - never implied as done.

6. **Never fabricate SQL source.** Don't extend, modify, or recreate a database function from a guessed or remembered body. Pull the live definition fresh (`pg_get_functiondef`) before editing, every time - including after a context compaction.

7. **Paste full literal SQL inline, same message.** Never summarize or truncate a migration when handing it over to run.

8. **Verify table/column names, don't infer from JS.** Code can reference a column or table that was renamed or never existed; check the live schema.

9. **Verify the current SQL signature before editing** - overloads and param lists drift; don't recreate a stale version.

10. **Verify a real save, not just a read path.** Exercise the actual write RPC/flow and confirm in the browser or via a fresh read - a mocked test or an unexercised code path proves nothing.

11. **Commit between DDL and a rolled-back test.** A combined script needs an explicit `commit;` between schema changes and a `begin...rollback` test block, or the rollback undoes the DDL too.

12. **SQL before frontend deploy, always in that order.** Never ship client code that calls an RPC that isn't live yet.
