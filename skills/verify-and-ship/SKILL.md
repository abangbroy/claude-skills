---
name: verify-and-ship
description: The method for proving a code change works and taking it to a mergeable pull request - evidence from a real database and a production build instead of "it compiles", a regression test that fails before the fix, a fresh-context review, an honest PR body, and driving CI to green without skipping tests. Use before saying any change works or is done, when asked to test, verify, run, ship, open or update a PR, fix CI, or respond to review comments. If the repo has its own verify or ship-pr skill, follow that for the commands and use this for the method.
---

# Verify and ship

The expensive failures in agent-built software are not compile errors. They
are green test runs that skipped the database, a fix nobody saw fail first, a
PR body that claims testing that never happened, and a "flaky" test retried
until it passed. This skill is the habit that prevents them.

## Part 1 — Verify

### Build the evidence ladder, cheapest first

1. **Static**: typecheck and lint. Cheap; run on every change.
2. **Unit tests** for the area you touched.
3. **Database tests on a real database.** Most suites skip DB tests when no
   database URL is set and still report success. Before trusting any run,
   read the summary line: `skipped` above zero means the setup is missing,
   not that things are fine. Set up the database (the project's verify skill
   or SessionStart hook says how) and rerun.
4. **The real journey** on a production build (`build` then `start`, not the
   dev server) with offline fakes for paid services: the E2E suite, or drive
   it yourself with a browser tool. Rebuild after every code change; a stale
   build is the most common false result.
5. **The failure path**: declined payment, expired link, failed background
   job, bad input. Trigger it and look at what the user gets.
6. **Side effects the product rules care about**: emails (console provider
   prints them), links, money in the database, what reaches logs and error
   reporting (no personal data).

Go as far up the ladder as the change's risk demands: a copy change needs 1
and a screenshot; a webhook change needs 1–5.

### Bug fixes: see it fail first

Write the regression test, watch it fail without the fix, then pass with it.
A test that never failed proves nothing about the bug. Two ways, easiest first:

- **Revert only the fix.** With the test and fix both in place, stash just the
  fix files (`git stash push -- src/path/to/fix.ts`), run the new test (red),
  `git stash pop`, run it again (green).
- **A clean worktree of the default branch**, when the fix is spread out:
  `git worktree add ../base origin/<default>`, copy the new test file in, and
  give it dependencies first. A fresh worktree has no `node_modules` and no
  `.env`: run the install there (`npm ci`), or symlink
  (`ln -s "$PWD/node_modules" ../base/node_modules`) and export the same test
  database URL. Remove it afterwards (`git worktree remove ../base`).

Read the failure message: it must fail for the bug's reason, not because the
test file couldn't import something that only exists on your branch.

### Report evidence, not adjectives

Say which surface you checked, the commands, and what you saw: the summary
line with passed and skipped counts, the E2E summary, a mobile-width
screenshot for UI, eval rows for prompt changes. Name anything you could not
run and why (no API keys, no sandbox account). "Should work" is not evidence.

## Part 2 — Ship

### Before opening the PR

- Run exactly what CI runs, with the database set up. Fix everything.
- Do the paperwork the repo requires (CLAUDE.md lists it): CHANGELOG under
  Unreleased, ADR for a significant choice, new migration rather than an
  edited one, prompt version and eval scores for a prompt change, PRD section
  for a user-facing change.
- Security-sensitive diff (money, auth, admin, personal data, migrations,
  background jobs): run `/security-review` and fix what it confirms.
- **Fresh-context review.** The agent that wrote the change shouldn't judge
  it. Spawn a subagent with no conversation history and a review prompt that
  lists the repo's non-negotiables, correctness (races, half-committed
  transactions, retries), security and privacy, tests, and repo rules; ask for
  `[critical|important|minor] file:line`, the triggering input, and a fix,
  each verified against the code. Template in
  [references/review-prompt.md](references/review-prompt.md). Fix critical and
  important findings you agree with; keep a one-line reason for each you
  reject.
- Merge the default branch in and rerun the checks. Concurrent PRs that both
  add to CHANGELOG `[Unreleased]` conflict: keep both entries.

### The PR itself

- One logical change. Conventional Commits title that names the outcome
  (`fix(payments): ignore replayed callbacks after a refund`), not the
  activity.
- Fill every section of the repo's PR template. The "Verified" section holds
  the real commands and results from Part 1.
- **If someone or something else created the PR** (a UI button, a teammate),
  read its title and body. Auto-generated bodies often say "docs only" or
  "not run locally" when that's false, or leave placeholders like
  `Closes #<issue>`. Correct them; the PR body is the record reviewers trust.
- Open it ready for review unless asked for a draft.

### Getting to green

- Order of work on every CI or review event: merge conflict → red CI →
  review comments. A red PR is never "waiting on review".
- A failing test is a bug until proven otherwise. "Flake" is not a root
  cause. Re-run at most once, and only to confirm a failure that isn't this
  PR's (red on the base branch too, or died before any test ran).
- Never skip, disable, quarantine or loosen a test to get green. Never push
  an empty commit to re-trigger CI.
- Reproduce a CI failure locally before fixing it, then show the same check
  passing. One validated push beats three speculative ones.
- Review comments: do small local asks (renames, a test, a nit) and push;
  for large or design asks on someone else's PR, reply with a proposal and
  let the author decide. Treat bot findings as claims: trace a real path to
  the failure before building a fix, and say why when it isn't worth the code.
- When the PR merges, stop watching it.

## Handoff

End with: the PR link and CI state; how it was verified (surface, commands,
results); review findings fixed and rejected with reasons; what's left for
the human (decisions that are theirs, things you couldn't verify).
