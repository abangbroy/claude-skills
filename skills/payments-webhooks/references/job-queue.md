# Postgres job queue (no extra infrastructure)

Enough for serverless apps at small scale: no Redis, no workers. Work starts
right after the request (Next.js `after()`, or a background task) and a cron
sweep picks up anything left.

## Table

```sql
create table jobs (
  id bigint generated always as identity primary key,
  kind text not null,                        -- e.g. generate_plan, send_email, payment_reconcile
  payload jsonb not null default '{}',       -- ids only, never personal data
  dedupe_key text unique,                    -- enqueue is idempotent on this key
  status text not null default 'queued'
    check (status in ('queued', 'running', 'succeeded', 'failed', 'dead')),
  attempts int not null default 0,
  max_attempts int not null default 3,
  run_after timestamptz not null default now(),
  locked_at timestamptz,
  last_error text,
  dead_handled_at timestamptz,               -- set when onDead finished
  dead_attempts int not null default 0,      -- onDead tries so far (its own backoff)
  dead_retry_at timestamptz,                 -- earliest next onDead try; null = now
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index jobs_ready_idx on jobs (status, run_after);
alter table jobs enable row level security;  -- server only
```

## Claim one job

```sql
update jobs set status = 'running', attempts = attempts + 1, locked_at = now(), updated_at = now()
where id = (
  select id from jobs
  where attempts < max_attempts
    and ((status in ('queued', 'failed') and run_after <= now())
      or (status = 'running' and locked_at < now() - interval '10 minutes'))
  order by run_after
  limit 1
  for update skip locked
)
returning *;
```

A job stuck `running` past the lock timeout (its worker was killed by a
platform time limit) is re-claimed only while attempts remain. One that dies on
its **last** attempt matches no claim, so nothing would ever move it on: it
stays `running` forever, `onDead` never fires, and a paying customer is never
refunded. The cron sweep therefore also runs both of these on every tick:

```sql
-- 1. Exhausted jobs become dead (covers a worker killed on the last attempt, and any
--    `failed` row at max attempts if your handler forgot to mark it dead).
update jobs
set status = 'dead', last_error = coalesce(last_error, 'worker lost on final attempt'), updated_at = now()
where attempts >= max_attempts
  and (status = 'failed' or (status = 'running' and locked_at < now() - interval '10 minutes'))
returning id, kind;

-- 2. Claim one dead job whose onDead has not finished; run onDead on it.
update jobs set dead_attempts = dead_attempts + 1,
                dead_retry_at = now() + least(power(2, dead_attempts) * interval '1 minute', interval '1 hour')
where id = (
  select id from jobs
  where status = 'dead' and dead_handled_at is null and coalesce(dead_retry_at, now()) <= now()
  order by id
  limit 1
  for update skip locked
)
returning *;
-- onDead succeeded: update jobs set dead_handled_at = now() where id = $1;
```

Alert when `dead_attempts` passes 5 for any job: a refund that keeps failing
needs a human.

## Rules

- **Enqueue in the same transaction** as the row that needs the work (the
  payment, the order). Then there is never a paid order without its job.
- `insert … on conflict (dedupe_key) do nothing`: safe to enqueue twice.
- Backoff on failure: `run_after = now() + least(2^attempts minutes, 1 hour)`.
- **Time budget**: a runner claims one job at a time and only starts a job whose
  expected duration fits before its own deadline; pass the deadline to the
  handler so long calls (LLM, gateway) use a shorter timeout.
- **Late workers**: when finishing, update with `where id = $1 and attempts =
  $claimedAttempt`, so a worker whose attempt was superseded can't overwrite the
  newer result.
- **onDead** (e.g. refund the credit, email an apology) is retried with backoff
  until it succeeds (`dead_handled_at`), and both a dead job and a failed
  `onDead` are reported to error tracking with the job kind and ids.
- Cron sweep: every minute in production. On hosting plans that only allow daily
  crons, say so in a CI guard that fails after the launch date.
