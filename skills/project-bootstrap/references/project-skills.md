# Project skill templates

Two small skills every project gets in `.claude/skills/`. They hold the
project's specifics; the generic `verify-and-ship` skill holds the method.
Replace `<…>`, drop rows that don't apply, and keep each under ~150 lines.

## Contents
- `.claude/skills/verify/SKILL.md`
- `.claude/skills/ship-pr/SKILL.md`
- `.claude/skills/ship-pr/references/review-prompt.md`

## verify

```markdown
---
name: verify
description: Prove a change to <project> works the way a <user>, an admin, or a <webhook/integration> sees it - unit and database tests on a real Postgres, <the eval>, and the E2E journey on a production build. Use while iterating and before opening a PR, when asked to run, test, check, or screenshot something, to reproduce a bug, or whenever you would otherwise say "it compiles" or "tests pass".
---

# Verify

Every change ships with evidence from the real thing. "Tests pass" means
nothing if the database tests were skipped.

## 1. Database first
In a cloud session the SessionStart hook did this: check `echo $TEST_DATABASE_URL`
and that Postgres is online. Otherwise:
<commands to start Postgres, create the test DB, export TEST_DATABASE_URL>

Without it, database tests skip and the runner still reports green. Never report
a run that skipped them as passing.

## 2. Fast checks (every change)
<typecheck> · <lint> · <unit tests, with the DB URL set: 0 skipped> · <build>

## 3. Pick the surface
| Change | Run | Proves |
| --- | --- | --- |
| <Money / pricing> | <test paths> | <integer minor units, tiers, rounding> |
| <Payments, webhooks> | <test paths>, then E2E | <signatures; replay never credits twice> |
| <AI / prompts> | <test paths>, then <eval> | <IDs only, schema valid; scores vs baseline> |
| <User journey / UI> | E2E on a production build | <the core journey end to end> |
| <Migration> | migrate a fresh DB, then the whole suite | <applies cleanly; RLS with policies> |

## 4. Drive it like a user
E2E on a production build with the offline fakes: <commands>. Also trigger the
failure path (declined payment, expired link, failed generation) and look at what
the user gets. Check the CLAUDE.md non-negotiables on screen and in emails.

## Evidence
Report the surface, commands, and what you saw: the test summary line (passed /
skipped), the E2E summary, a mobile screenshot for UI changes, and for bug fixes
the regression test failing on the default branch and passing on yours. Say what
you could not run and why.
```

## ship-pr

```markdown
---
name: ship-pr
description: Take finished work in <project> to a pull request a human can review without fighting CI - the CI checks with a real database, verification against the running app, a fresh-context review against the CLAUDE.md non-negotiables, the repo's paperwork (CHANGELOG, ADR, PRD section), and the PR itself. Use whenever you are asked to open, create, ship, or submit a PR, or when implementation is done and the next step is review.
---

# Ship a PR

## 1. Checks
What CI runs, with the database set up (verify skill, step 1): <commands>.
Then the rules no command checks: CHANGELOG entry under [Unreleased]; ADR for a
significant choice; a new migration file (never an edited one); prompt version and
eval scores for a prompt change; required tests for <risky areas>.
Security-sensitive change (<money, auth, admin, personal data, migrations>): run
`/security-review` on the diff and fix what it confirms.

## 2. Verify
The verify skill on the surface the change touches. Keep the summaries for the PR.

## 3. Review in a fresh context
Spawn a reviewer with no memory of this conversation and give it
references/review-prompt.md with the base branch filled in. Fix critical and
important findings you agree with; keep a one-line reason for each you reject.

## 4. Commit and open
Branch you were given, or off the up-to-date default branch. Merge the default
branch in and rerun step 1. Conventional Commits title naming the outcome.
Fill every section of the PR template; "Verified" carries the real commands and
results. If a PR was created for you (e.g. from a UI), read its body and correct
anything that doesn't match what you did.

## 5. Get it green
Fix what CI reports; a failing test is a bug until proven otherwise. Never skip,
disable or loosen a test. Answer every review comment.

## Handoff
PR URL and CI state; how it was verified; review findings fixed and rejected;
what is left for the human (decisions, things you couldn't verify).
```

## review-prompt.md

```markdown
# Review prompt

Give this to a reviewer that has not seen the conversation. Replace <BASE>.

You are reviewing a change to <project>, <one sentence on what it does and for whom>.

Read `CLAUDE.md`, then `git diff <BASE>...HEAD` and `git log <BASE>..HEAD`. Read
surrounding code where the diff alone doesn't show whether something is right.
Do not edit files.

Check, in this order:
1. Non-negotiables from CLAUDE.md (any breach is critical): <list them again>.
2. Correctness: wrong results; races (two webhooks, two tabs, a retried job);
   transactions that commit half the work; missing error paths; time zones.
3. Security and privacy: unchecked input; access checks on every page, action
   and export; secrets or server modules in client code; personal data in logs,
   error reports or exports; RLS missing on a new table.
4. Tests: required tests present and testing behaviour; DB tests that actually run.
5. Repo rules: new migration not edited one, CHANGELOG, ADR, prompt version + eval.

Report each finding as:
[critical|important|minor] path/to/file:LINE
What is wrong, and the concrete input or sequence that triggers it.
Suggested fix.

Verify each finding against the code before reporting; say "no findings" if none.
Do not pad the list.
```
