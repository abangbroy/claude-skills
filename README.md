# claude-skills

Reusable Claude Code skills distilled from building and shipping real products
(first source: luhur-gift, a paid Next.js + Postgres + LLM web app). Each skill
holds the method; each project keeps its own specifics in `.claude/skills/`.

| Skill | Use it when |
| --- | --- |
| [`project-bootstrap`](skills/project-bootstrap/SKILL.md) | Starting a new project or making a repo Claude-ready: PRD, build plan, CLAUDE.md non-negotiables, ADRs, CI, dev fakes, cloud SessionStart hook, project verify/ship-pr skills |
| [`verify-and-ship`](skills/verify-and-ship/SKILL.md) | Proving a change works and taking it to a green, mergeable PR |
| [`postgres-migrations-release`](skills/postgres-migrations-release/SKILL.md) | Migrations, RLS, database tests, staging → production releases, rollback, backups |
| [`payments-webhooks`](skills/payments-webhooks/SKILL.md) | Checkout, gateways, webhooks, credits and wallets, refunds, reconciliation |
| [`llm-product-features`](skills/llm-product-features/SKILL.md) | App features that call an LLM: IDs not URLs, validation, adapters, prompts, evals, cost |

## Install

**claude.ai account (every session, every project):** upload each file in
`dist/` at claude.ai → Settings → Capabilities → Skills (or click **Save skill**
on the file card when Claude sends it). Re-upload after changing a skill.

**One project only:** copy a folder from `skills/` into that repo's
`.claude/skills/`.

## Change a skill

1. Edit `skills/<name>/SKILL.md` (keep it under ~500 lines; long material goes
   in `references/`).
2. Rebuild the upload files: `./build.sh` (needs the skill-creator packager;
   see the script).
3. Commit, push, and re-upload the changed `.skill` file.

Add a lesson when a project teaches one: a failure that cost time, with the
reason, in the skill it belongs to. Keep the descriptions specific; every
enabled skill's description loads into every session.
