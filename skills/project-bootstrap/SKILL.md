---
name: project-bootstrap
description: Set up a new or young repository so Claude Code can build it safely for months - PRD and build plan, a short CLAUDE.md with the product's non-negotiables, ADRs, CHANGELOG, CI with a real database, dev fakes for paid services, a cloud SessionStart hook, and the project's own verify and ship-pr skills. Use whenever the user starts a new project or repo, says "set up", "scaffold", "bootstrap", "make this repo Claude-ready", asks for a CLAUDE.md, or is about to build an MVP - even if they only describe the product idea and don't ask for setup.
---

# Project bootstrap

A project goes well when every session starts from the same written rules and
can prove its own work. This skill sets that up before the first feature. It
comes from building a paid web product end to end with Claude Code: what paid
off was a short list of rules that money or users depend on, a build plan
worked one task at a time, a decision record for every real choice, and tests
that cannot quietly skip.

Do the steps in order. Each produces files in the repo; show the user a short
summary after each step instead of asking permission for every file. Ask only
for decisions that are theirs (product scope, pricing, stack when they care).

## 1. Interview (5 minutes, not 50)

Get answers to these, from the conversation if they're already there:

- What it does, for whom, and the one journey that must work (e.g. "answer
  questions → see preview → pay → get plan").
- Does it take money? Hold personal data? Call an LLM? Send email? Each "yes"
  adds non-negotiables and a dev fake (step 4).
- Stack and hosting, if they care. Default for a web product: Next.js +
  TypeScript strict + Postgres + Vercel; Python + FastAPI + Postgres for
  data/API work. Record the choice as ADR 0001.
- Country and law that apply (data protection, tax, language of the UI).

## 2. Product docs

- `docs/prd/MVP_v1.md` — problem, users, the core journey, features with
  acceptance criteria, what is out of scope, open questions. Version it
  (`MVP_v1`, `MVP_v2`) instead of rewriting history.
- `docs/BUILD_PLAN.md` — milestones `M0…Mn`, each a checklist of tasks with
  ids (`M2-3`). One task ≈ one PR. Note tasks that only the user can do
  (accounts, keys, legal review) so they are not mistaken for code work.
- `docs/decisions/0000-template.md` and `0001-<stack>.md` — template in
  [references/templates.md](references/templates.md). Any choice someone
  might later ask "why?" about gets an ADR, with options considered.
- `CHANGELOG.md` with `## [Unreleased]` (Keep a Changelog). Every PR adds a
  line; it becomes the release notes and the handover.

## 3. CLAUDE.md

Loaded on every turn, so keep it under ~80 lines and make every line earn its
place. Template in [references/templates.md](references/templates.md). It has:

- **Non-negotiables**: the 5–8 rules that, broken once, cost money, leak
  data or break trust. Write them as facts about the product, e.g. "The LLM
  never writes URLs; it returns catalog IDs and the app inserts links",
  "Payment webhooks verify signatures and can be replayed without
  double-crediting", "Personal data lives only in `customers`". These are
  what reviewers check first.
- **Code conventions**: strict types, validation of all external input and
  all LLM output at the boundary, module layout (one line per module),
  money as integer minor units, secrets server-only, how errors are reported.
- **Tests required for** the risky areas (money, auth, webhooks, anything
  idempotent), and how database tests run.
- **Database rules** (see the postgres-migrations-release skill): new
  numbered migration files only, add-only, RLS with the table.
- **Git**: Conventional Commits, one logical change per PR, CHANGELOG in the
  same PR, ADR for significant choices, PRD section named for user-facing
  changes.
- Pointers to the project skills (step 6).

Do not paste the PRD or architecture into CLAUDE.md; link them.

## 4. Dev fakes for every paid or external service

For each external service (LLM, payment gateway, email, search, maps) define
an interface in the code and two implementations: the real one and a
deterministic fake (`AI_PROVIDER=fake`, `PAYMENT_GATEWAY=fake`,
`EMAIL_PROVIDER=console`). Then:

- Tests and E2E run fully offline and free, in CI and in cloud sessions.
- The env loader refuses fakes when `APP_ENV=production`, and refuses an
  unset `APP_ENV` on the production host, so a forgotten variable can't make
  production "pay" with the fake gateway.
- Validate env at startup with a schema; fail with the variable's name.

## 5. CI and cloud sessions

- **CI** (`.github/workflows/ci.yml`): typecheck, lint, unit tests with a
  real Postgres service, build, dependency audit; E2E only on PRs after the
  check job passes. Skip docs-only changes, cancel superseded PR runs, set
  job timeouts (free CI minutes run out). Starter in
  [references/ci.yml](references/ci.yml).
- **Skipped tests are failures.** Database tests usually skip when no DB URL
  is set, and the runner still says green. Make CI set the URL, and make the
  verify skill check the skipped count.
- **Cloud SessionStart hook** (`.claude/hooks/session-start.sh` +
  `.claude/settings.json`): install deps, start the local database, create
  test databases, export the test DB URL via `$CLAUDE_ENV_FILE`. Cloud
  containers start without `node_modules` and with Postgres stopped. Starter
  in [references/session-start.sh](references/session-start.sh). Run it twice
  to prove it's idempotent, then run one lint and one DB test.
- Allowlist only exact, side-effect-free commands (`Bash(npm run lint)`), never
  interpreter or runner wildcards.
- **Enforce the rules with hooks, don't just write them down.** A rule in
  CLAUDE.md is followed when the model remembers it; a hook is followed every
  time, and costs no context. Three small hooks in
  [references/hooks/](references/hooks/) (settings snippet in
  `settings.json`; copy the scripts to `.claude/hooks/`):
  - `guard-edit.sh` (PreToolUse) refuses edits to a migration that already
    exists on the default branch, to `.env`/key files, and to lockfiles.
  - `after-edit.sh` (PostToolUse) formats and lints just the edited file and
    hands errors straight back, so a mistake is fixed one edit after it
    happens.
  - `stop-check.sh` (Stop) runs `scripts/fast-checks.sh`
    ([template](references/fast-checks.sh)) and refuses to let Claude finish
    while it fails **or while tests were skipped**. After two refusals in a
    row it lets Claude stop and report, so an unfixable check never traps a
    session.

  Pipe-test each hook with a synthetic JSON payload before trusting it (the
  scripts show the input shape), and commit `.claude/settings.json` so every
  cloud session gets them. Hooks that need `jq` say so loudly when it is
  missing; the SessionStart hook installs or checks it.

## 6. The project's own skills

Generic skills (verify-and-ship) give the method; the project needs the
specifics. Create two small project skills in `.claude/skills/` from the
templates in [references/project-skills.md](references/project-skills.md):

- `verify` — how to set up the DB, the fast checks, a table "change in area X
  → run these tests → proves Y", how to run E2E on a production build, and
  what evidence to report.
- `ship-pr` — checks, the repo's paperwork, a fresh-context review prompt
  listing the non-negotiables, the PR template, getting CI green.

Fill the area table from the real module layout; leave rows for areas that
don't exist yet out rather than inventing them.

## 7. Before the first feature

Commit the bootstrap as one PR (`chore: bootstrap project conventions`), with
CI green on it. Then work the build plan one task per PR, ticking tasks in
`BUILD_PLAN.md` as they merge. After an unattended run, write
`docs/HANDOVER.md`: what was built, what the user must do (accounts, keys, in
order), decisions made on their behalf and where to change them, known gaps.
