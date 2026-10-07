---
name: postgres-migrations-release
description: Safe Postgres schema changes and releases for a web app - numbered add-only migrations linted in CI, expand-then-contract renames and drops, safe constraints and lock timeouts, row-level security with every table, database tests that rebuild from migrations and can't silently skip, a CI guard against editing applied migrations, a staging → promote → production flow that migrates before code ships, rollback, and encrypted backups with restore tests. Use whenever you write or review a migration, add a table or column, touch RLS, set up database tests, plan a deploy, release, rollback or backup, or connect an app to Supabase or another hosted Postgres.
---

# Postgres migrations and releases

The rule that makes everything else simple: **a migration must work with the
code production is running right now.** It is applied before the new code
ships, and it stays if that code is rolled back. Follow that and code
rollback is always one click, the database only ever moves forward, and
deploys never race their schema.

## Writing a migration

- **A new numbered file** (`NNNN_description.sql`, next number after the
  highest). Never edit, rename or delete one that has merged: it has already
  run on staging and maybe production, so changing it changes nothing there
  and makes fresh databases differ from real ones. Fix a wrong migration with
  another migration. Enforce it in CI
  ([references/ci-migration-guard.yml](references/ci-migration-guard.yml)).
- **Only add.** New tables, new nullable columns or columns with defaults,
  new indexes, new constraints that existing rows already satisfy. Each of
  these is invisible to old code.
- **Rename or drop in steps across releases** (expand, then contract):
  1. Release A: add the new column; write both; read the new one; backfill.
  2. Release B, once A is stable: stop using the old column.
  3. Release C: drop the old column.
- **Watch for the quiet breakers**: `not null` without a default (old code's
  inserts fail); a new `check` or `unique` that live data violates; changing
  a column type; an enum value removed; an index built without
  `concurrently` on a big hot table (locks writes); a long backfill inside the
  migration transaction (do it in batches or a job).
- **`create index concurrently` cannot run inside a transaction**, and most
  runners wrap each file in one. Put it alone in its own file, first line
  `-- no-transaction`, written `if not exists` so a half-failed run (it leaves
  an invalid index behind: drop it, rerun) can be repeated. The runner in
  [references/test-db.md](references/test-db.md) honours the marker. Whether
  your hosted migration tool does is something to prove, not assume: apply
  such a file to a throwaway database with that tool before relying on it.
- **Constraints on a table that already has rows: two steps.**
  `alter table orders add constraint total_nonneg check (total >= 0) not
  valid;` takes only a brief lock, is enforced for new rows at once, and
  succeeds even if old rows violate it. After cleaning up old rows (a batch
  job, not this migration), a later migration runs `alter table orders
  validate constraint total_nonneg;`, which scans without blocking writes and
  fails, changing nothing, if a bad row remains. Same for foreign keys. For
  `set not null` on a big table: add `check (col is not null) not valid`,
  validate it, then `set not null` (Postgres 12+ reuses the validated check
  instead of rescanning), then drop the check.
- **Fail fast instead of queueing.** An `alter table` waits for a lock, and
  every query behind it waits for the `alter`, so one slow transaction can
  stall the whole app. Start any migration that alters an existing busy table
  with `set local lock_timeout = '5s';` (inside the transaction): it errors
  quickly, the deploy stops, and you retry at a quieter moment.
- **Lint migrations in CI** (Squawk or similar): it flags these exact
  mistakes (index without `concurrently`, `not null` add, drop column, a
  constraint without `not valid`) before review does. Wire it in
  [references/ci-migration-guard.yml](references/ci-migration-guard.yml);
  suppress a rule per file with a reason, never globally.
- **Row-level security with the table, in the same file.** `alter table …
  enable row level security` plus the policies the table needs. If only the
  server touches it (direct connection as a privileged role), say so in a
  comment and revoke the client roles' grants, guarded so the file also runs
  on plain Postgres in CI:
  ```sql
  -- RLS on, no client policies: only the server reads and writes this table.
  alter table recipes enable row level security;
  do $$ begin
    if exists (select 1 from pg_roles where rolname = 'anon') then
      execute 'revoke all on table recipes from anon'; end if;
    if exists (select 1 from pg_roles where rolname = 'authenticated') then
      execute 'revoke all on table recipes from authenticated'; end if;
  end $$;
  ```
- **Views bypass RLS by default** (they run as their owner). On Supabase that
  makes a view readable through the public REST API. Create views
  `with (security_invoker = true)`.
- Money columns are `numeric(12,2)` (or integer minor units); code converts at
  one boundary. Timestamps are `timestamptz`.
- Personal data in one table (`customers`); everything else references its id,
  so deletion and export requests touch one place.

## Testing migrations and database code

- **One migration runner for local and CI** that applies the files in order
  and records them in a tracking table; hosted environments use the
  provider's tool (`supabase db push`). Sketch in
  [references/test-db.md](references/test-db.md).
- **Rebuild the test database from migrations once per test run**, truncate
  app tables before each test. Tests then always run against the real schema.
- **Skipped DB tests are the classic false green.** A `describeDb` that skips
  without a `TEST_DATABASE_URL` is fine for laptops, but CI must set it, and
  whoever reports results must read the skipped count.
- **Old code on the new schema**: copy the new migration into a worktree of the
  default branch and run its tests there. Passing proves the migration is safe
  to apply before the code ships.
- Concurrency-sensitive code (balances, payments, job claims) gets tests that
  run two transactions at once, not just sequential ones.

## Release flow

From launch, separate staging from production
([references/release-flow.md](references/release-flow.md) has the workflows):

```
PR → main ─► staging deploy + staging DB migration
               │ check it on staging
               ▼
Promote workflow (manual): check CI green on that commit → migrate production DB
(approval) → fast-forward the production branch → host deploys production
```

- Releasing is a deliberate click, not a merge. Hotfixes go the same way.
- **Rollback is code only**: the host's instant rollback to the previous
  deployment. Never roll back a migration; add-only makes old code safe on the
  new schema. A wrong migration gets a fixing migration.
- After a release: health endpoint OK, error tracker shows the new release with
  no new errors for ~15 minutes.

## Backups

- Nightly `pg_dump -Fc`, encrypted with a public key (`age`), uploaded off-site
  (R2/S3) with a retention rule that matches the privacy notice (e.g. 35 days),
  so deletion requests are honoured within that window.
- The private key lives offline, never in CI or the host.
- **A backup that was never restored is a hope.** Restore into staging monthly,
  check row counts of the money and customer tables, log the date and result in
  the runbook.

## Hosted Postgres gotchas

- **Poolers**: drivers that pipeline queries (postgres.js) can hang through a
  transaction-mode pooler (Supabase's shared Supavisor on 6543). Use the
  session pooler (5432) or a dedicated PgBouncer, and size the pool to the
  plan's connection limit. Prepared statements also break in transaction mode.
- **Region**: run server functions in the same region as the database; a
  cross-ocean round trip per query makes every page slow.
- Require TLS to the database; refuse a local-looking or test URL in
  production and a production URL in tests or seed scripts.
- Migrations in CI connect with a secret per environment
  (`STAGING_DATABASE_URL`, `PRODUCTION_DATABASE_URL`); the production one sits
  behind a GitHub environment with a required reviewer.
