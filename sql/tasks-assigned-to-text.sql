-- Fixes: "Could not save task: invalid input syntax for type uuid: 'test'"
--
-- tasks.assigned_to is currently typed uuid, but the app has never once
-- treated it as a real foreign key - confirmed via a full grep of every
-- reference to it: the Add/Edit Task form is a plain free-text <input>
-- (placeholder "Staff, driver, agent, stylist, manager...", not a
-- dropdown), the task list reads it as display text, and the task search
-- box does a free-text ilike() match against it. No app code anywhere
-- constructs, expects, or JOINs against a real UUID value here. This
-- also means the Tasks search box has been silently at risk of the same
-- crash any time a search term touches a task whose assigned_to holds a
-- non-UUID-shaped value (i.e. always, since every real value in this
-- column is a person's name/role, never a UUID).
--
-- Changing to text matches how every other "who/what is this related to"
-- field in the app already works (documents.related_person,
-- business_records.related_person, tasks.related_item, etc. - all text).
-- A uuid->text cast is always safe (every uuid has a valid text
-- representation), so this won't fail or lose data even if the column
-- currently holds real UUID-shaped values.

alter table public.tasks
  alter column assigned_to type text using assigned_to::text;
