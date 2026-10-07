# Templates

## Contents
- CLAUDE.md
- ADR template (`docs/decisions/0000-template.md`)
- Build plan
- PR template (`.github/pull_request_template.md`)

## CLAUDE.md

Replace everything in `<…>`. Delete sections that don't apply (no money → no
money rules). Keep it short: it loads on every turn.

```markdown
# CLAUDE.md — conventions for this repo

Read `docs/prd/MVP_v1.md` and `docs/BUILD_PLAN.md` before starting a task. Work one build-plan task at a time.

## Non-negotiables
- <Rule that protects money, e.g. "Money logic is idempotent. Payment webhooks verify signatures and can be replayed without double-crediting.">
- <Rule that protects data, e.g. "Personal data (email, phone, consent) lives only in `customers`. Everything else references `customer_id`.">
- <Rule that protects trust in AI output, e.g. "The LLM never writes URLs or prices. It returns catalog IDs; the app inserts links and computes money.">
- <Product/brand rule, e.g. "Buttons say 'Buy now →'. No marketplace name or logo in the UI.">

## Code
- TypeScript strict. No `any` without a comment explaining why.
- Validate all external input and all LLM output with Zod schemas in `src/lib/schemas`.
- Module layout:
  - `src/lib/<area>` — <one line on what lives there>
- Data access functions take a `Db` (pool or transaction) as their first argument.
- Money is integer minor units in code (`src/lib/money.ts`).
- Secrets are server-only. Never import db, env or adapters into client components.
- Development fakes (`<SERVICE>_PROVIDER=fake`) exist for local dev and tests; `env.ts` refuses them in production.
- Prompts live in `prompts/` as files, not inline strings.
- A failure you catch and don't rethrow goes through `reportError` with `area`, `op` and ids only.

## Skills
- `.claude/skills/verify` — how to prove a change works. Use before saying something works.
- `.claude/skills/ship-pr` — checks, review and paperwork before opening a PR.

## Enforced by hooks (`.claude/hooks/`)
- Applied migrations, `.env`/key files and lockfiles cannot be edited; the edit is refused with the reason.
- Each edited file is formatted and linted straight after the edit.
- Finishing runs `scripts/fast-checks.sh`; failures and skipped tests block it. Fix the cause, never the check.

## Tests
- Unit tests required for: <money, credits, webhooks, link validation, …>.
- Database tests run when `TEST_DATABASE_URL` is set (CI runs Postgres); a run that skipped them is not a pass.
- E2E smoke test: <the core journey>.
- If a prompt changes, run `npm run eval` and record before/after scores in `docs/ai/`.

## Database
- Schema changes only via new files in `<migrations dir>/NNNN_description.sql`. Never edit an applied migration (CI enforces it).
- Migrations only add; they must work with the code production runs now. Rename or drop in steps (expand, then contract).
- Every table has RLS enabled, with policies in the same migration.

## Git
- Conventional Commits. One logical change per PR.
- Update `CHANGELOG.md` (Unreleased) in the same PR.
- Significant technical choice → ADR in `docs/decisions/` from `0000-template.md`.
- User-facing behaviour change → name the PRD section affected in the PR.
```

## ADR template

```markdown
# NNNN — Title

- **Date:** YYYY-MM-DD
- **Status:** proposed | accepted | superseded by NNNN

## Context
What problem or constraint forced a decision.

## Options considered
1. Option A — pros / cons
2. Option B — pros / cons

## Decision
What we chose.

## Consequences
What becomes easier or harder; what to revisit and when.
```

Amend an accepted ADR with a dated `## Amendment` section rather than
rewriting it, so the history of the reasoning survives.

## Build plan

```markdown
# Build plan — MVP v1

## M0 — Foundation
- [ ] M0-1 Scaffold (strict TS, lint, test, e2e, eval scripts)
- [ ] M0-2 Repo protection: default branch requires PR + CI; Dependabot; secret scanning  *(owner)*
- [ ] M0-3 Staging and production projects (database, hosting)  *(owner: accounts and keys)*

## M1 — <first user-visible slice>
- [ ] M1-1 …
```

Tick a task when its PR merges, and add a short italic note when it's done
but blocked on the owner (`*code done; keys pending*`).

## PR template

```markdown
## What changed
<!-- One or two sentences. -->

## Why
<!-- Issue or build-plan task id. -->

## How it was tested
- [ ] Unit tests added/updated
- [ ] E2E passes (if a user flow changed)
- [ ] Eval run and scores recorded (if prompts or models changed)

## Verified
<!-- First line: "Ran it locally: yes" or "no - <why>". Then the commands and what you saw:
     test summary with 0 skipped, E2E summary, eval rows, screenshots for UI. -->

## Checklist
- [ ] PRD section affected: <!-- or "none" -->
- [ ] Database migration included: yes / no
- [ ] CHANGELOG.md updated (Unreleased)
- [ ] ADR added (if a significant technical decision was made)
- [ ] Non-negotiables in CLAUDE.md still hold
```
