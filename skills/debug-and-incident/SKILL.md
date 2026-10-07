---
name: debug-and-incident
description: Find the root cause of a bug quickly and handle a production incident without making it worse - reproduce first, narrow with git bisect and input minimising, test hypotheses one at a time, prove a flaky test with repeated runs instead of retrying it, fix the cause with a regression test, and for live incidents stabilise first (kill switch, code rollback), then diagnose, then write a blameless postmortem that adds a test, an alert or a guard. Use whenever something is broken, an error report or failing test arrives, a CI failure isn't obviously caused by the diff, a test is flaky, or production misbehaves.
---

# Debug and incident

Speed in debugging comes from not guessing. Every minute spent changing code
before the failure reproduces is a minute spent on a theory. The order is
always: reproduce, narrow, explain, fix, prevent.

## 1. Reproduce before touching anything

- Get the smallest **deterministic** reproduction: a failing test, or a
  script that exits non-zero. If the report is a production error, take from
  it the release, request id, route, and the *shape* of the input (never copy
  personal data into a ticket, a test or a log).
- Can't reproduce? Don't guess a fix. Add logging or an assertion at the
  suspected boundary, ship that, and wait for the next occurrence. Say so
  plainly: "not reproduced; instrumented X".
- Pin everything that varies: clock (inject time, don't `sleep`), random seed,
  locale and time zone, test order, database state, environment variables.

## 2. Narrow it

Pick the cheapest tool that halves the search space:

- **Was it ever working?** `git bisect run` finds the first bad commit
  automatically. Keep the repro script **outside the work tree** (old commits
  don't contain it):
  ```
  git bisect start <bad> <good>
  git bisect run /path/to/repro.sh   # exit 0 = good, 1 = bad, 125 = can't test this commit
  git bisect reset
  ```
  It finds the first bad commit in about log2(n) steps; read that commit's
  diff before believing it (a flaky repro makes bisect confidently wrong, so
  make the script deterministic first).
- **Which input?** Shrink the failing input by halves until removing anything
  more makes it pass. The minimal input usually names the cause.
- **Working vs failing environment?** Diff what differs: versions, env vars,
  config, data volume, the first row where results diverge.
- **Which layer?** Check the value at each boundary (request → handler →
  database → response) and find the first place it's already wrong.

## 3. Explain: hypotheses, one at a time

Write 2–3 hypotheses and, for each, a **cheap test that would rule it out**.
Run the cheapest first. Change one thing per experiment. Keep a short log
(hypothesis, test, result); when you've "tried everything", the log shows what
you haven't. If you have been in the same place for 30 minutes, say what is
known, what is not, and ask for a second pair of eyes, rather than trying
random edits.

Distrust the first plausible explanation until something predicts a *second*
symptom you then observe.

## 4. Fix the cause, not the symptom

- Ask "why" until the fix would have prevented the whole class of bug, not
  only this input. Then `grep` for the same pattern elsewhere.
- Write the regression test first and watch it fail for the right reason (the
  verify-and-ship skill has the recipe). Make the smallest fix. No drive-by
  refactors in a bug-fix PR.
- A `try/catch` that swallows, a retry added "just in case", a longer timeout
  or an `if (x == null) return` are symptoms being hidden. Use them only when
  the cause is genuinely outside your control, and say so in a comment.

## 5. Flaky tests are bugs with a reproduction rate

Never retry-until-green, skip or quarantine. Instead, **measure**: run the
test 50–200 times in a loop alone, then with its file, then with the suite:
`for i in $(seq 100); do <run the one test> || { echo "failed on run $i"; break; }; done`,
or the runner's own option (Playwright `--repeat-each`, pytest-repeat `--count`). Where it starts
failing tells you the cause:

| Fails when | Usual cause |
| --- | --- |
| alone, sometimes | time, randomness, a real timer or `sleep`, an unawaited promise |
| only with other tests | shared state: leftover rows, module-level mocks, env mutation, test order |
| only in parallel | shared database or port, a file path, a lock |
| only in CI | slower machine exposing a race; missing env var; time zone; a skipped dependency |

Fix the cause (inject the clock, await the event, isolate the data), then
repeat the loop until zero failures in the same count, and report that count.

## 6. Production incident

Stop the bleeding first; understanding comes second.

1. **Declare and assign**: one person drives, writes the timeline in one place
   (time, what was seen, what was done). Tell users or the owner early and
   plainly, with the next update time.
2. **Stabilise, cheapest reversible action first**: turn the feature off
   with its kill switch; roll back **code** with the host's instant rollback
   (migrations are add-only, so the old code works on the new schema; see
   postgres-migrations-release); pause the job queue or webhook intake if
   it's amplifying damage. Don't hot-patch forward unless rollback is
   impossible.
3. **Protect money and data**: payments taken without product, double
   charges, leaked personal data are handled before the rest. Reconcile from
   the gateway's records, not from your own database alone.
4. **Diagnose** from step 1–3 above on a copy, never by experimenting in
   production. Use the release tag on the error report to confirm which
   deploy introduced it.
5. **Fix forward** through the normal PR path with a regression test, then
   promote. Hotfix still means green CI.
6. **Postmortem within two working days**: blameless, in
   [references/postmortem.md](references/postmortem.md). Every incident ends
   with at least one *durable* change: a test, an alert, a guard or hook, or a
   rule in CLAUDE.md. "Be more careful" is not one.

## What to have in place before the incident

These are what make the steps above take minutes instead of hours; add them
during the build, not during the outage.

- **Kill switches**: a flag per risky feature (payments, generation,
  emails), read at the boundary, defaulting to the safe state, with an env
  var override that works even if the database is the problem. Test the off
  state like any other path.
- **Correlation**: a request id on every log line and error report, and the
  release id tagged on errors, so "which deploy" is a click.
- **Structured logs** with ids only, never personal data, and a health
  endpoint that checks the database and the queue.
- **Alerts** on the failures that cost money: rejected or missed webhooks,
  dead jobs, failed refunds, error-rate jump after a release, daily
  AI-spend cap reached.
- **A runbook per scary scenario** ("customer paid but has nothing", "webhook
  stopped", "AI provider down"), written when calm.

## Report

For a bug: the reproduction, the root cause in one sentence, the fix, the
regression test and the before/after evidence. For an incident: impact,
timeline, cause, what stopped it, and the durable changes with owners.
