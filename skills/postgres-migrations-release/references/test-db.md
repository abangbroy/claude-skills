# Test database pattern (TypeScript + postgres.js + Vitest)

Adapt to the stack; the shape is what matters: one runner, rebuild once per run,
truncate per test, skip loudly.

## Migration runner (`src/lib/db/migrate.ts`)

```ts
import { readdirSync, readFileSync } from "node:fs";
import path from "node:path";
import postgres from "postgres";

const MIGRATIONS_DIR = path.join(process.cwd(), "supabase", "migrations");

/**
 * Local/CI runner. Tracks applied files in dev_meta.migrations. Hosted envs use the provider's tool.
 * Each file runs in one transaction, except files whose first lines contain `-- no-transaction`
 * (for `create index concurrently`); the hosted tool must be told the same (see SKILL.md).
 */
export async function applyMigrations(url: string): Promise<string[]> {
  const sql = postgres(url, { max: 1, onnotice: () => {} });
  try {
    await sql`create schema if not exists dev_meta`;
    await sql`create table if not exists dev_meta.migrations (name text primary key, applied_at timestamptz not null default now())`;
    const done = new Set((await sql<{ name: string }[]>`select name from dev_meta.migrations`).map((r) => r.name));
    const files = readdirSync(MIGRATIONS_DIR).filter((f) => /^\d{4}_.+\.sql$/.test(f)).sort();
    const applied: string[] = [];
    for (const file of files) {
      if (done.has(file)) continue;
      const body = readFileSync(path.join(MIGRATIONS_DIR, file), "utf8");
      if (/^--\s*no-transaction\b/m.test(body.split("\n", 3).join("\n"))) {
        // `create index concurrently` and friends cannot run inside a transaction.
        // Keep such a file to one statement type so a failure leaves nothing half-applied,
        // and make it re-runnable (`if not exists`).
        await sql.unsafe(body);
        await sql`insert into dev_meta.migrations (name) values (${file})`;
      } else {
        await sql.begin(async (tx) => {
          await tx.unsafe(body);
          await tx`insert into dev_meta.migrations (name) values (${file})`;
        });
      }
      applied.push(file);
    }
    return applied;
  } finally {
    await sql.end();
  }
}

/** Drop everything and re-apply all migrations (tests only). */
export async function resetDatabase(url: string): Promise<void> {
  const sql = postgres(url, { max: 1, onnotice: () => {} });
  try {
    await sql.unsafe(`drop schema if exists public cascade; drop schema if exists dev_meta cascade; create schema public;`);
  } finally {
    await sql.end();
  }
  await applyMigrations(url);
}
```

The CLI wrapper (`scripts/db-migrate-local.ts`) refuses URLs that look hosted or
production (`/supabase\.(co|com)/`, `APP_ENV=production`).

## Vitest wiring

`vitest.config.mts`: `globalSetup: ["src/test/global-setup.ts"]`, `fileParallelism: false`.

```ts
// src/test/global-setup.ts — rebuild once per run
import { resetDatabase } from "../lib/db/migrate";
export default async function setup() {
  const url = process.env.TEST_DATABASE_URL;
  if (url) await resetDatabase(url);
}
```

```ts
// src/test/db.ts
import { afterAll, beforeEach, describe } from "vitest";
import { createSql, type Sql } from "@/lib/db/client";

export const TEST_DATABASE_URL = process.env.TEST_DATABASE_URL;
/** `describe` that only runs when a test database is configured. CI must set it. */
export const describeDb = TEST_DATABASE_URL ? describe : describe.skip;

const APP_TABLES = ["payments", "credit_ledger", "jobs", "customers" /* … every app table */];

export function useTestDb(): { sql: () => Sql } {
  let sql: Sql | undefined;
  beforeEach(async () => {
    process.env.DATABASE_URL = TEST_DATABASE_URL;
    sql ??= createSql(TEST_DATABASE_URL!);
    await sql.unsafe(`truncate ${APP_TABLES.join(", ")} restart identity cascade`);
  });
  afterAll(async () => { await sql?.end(); });
  return { sql: () => { if (!sql) throw new Error("useTestDb: not ready"); return sql; } };
}
```

Keep `APP_TABLES` complete: a forgotten table leaks rows between tests and makes
order-dependent failures. A test that lists tables from `pg_tables` and compares
is cheap insurance.

## Python equivalent

pytest: a session-scoped fixture that runs the same runner (or Alembic `upgrade
head`) on `TEST_DATABASE_URL`, a function-scoped fixture that truncates, and
`pytest.mark.skipif(not TEST_DATABASE_URL, reason=...)` — plus `-rs` in CI so
skips are printed, and a CI check that fails on any skip reason mentioning the DB.
