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
| [`llm-product-features`](skills/llm-product-features/SKILL.md) | App features that call an LLM: IDs not URLs, validation, retries, adapters, prompts, evals and judges, caching, cost |
| [`debug-and-incident`](skills/debug-and-incident/SKILL.md) | Finding a root cause fast (reproduce, bisect, hypotheses), flaky tests, and handling a production incident and its postmortem |

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
3. Check everything: `python3 scripts/validate.py` (needs PyYAML). It checks
   frontmatter against the packager's rules (name equals folder, description
   at most 1024 characters with no angle brackets), the 500-line limit, that
   links resolve, that shell, YAML and JSON references parse, and that
   `dist/` matches `skills/`. CI runs the same check on every PR.
4. Commit, push, and re-upload the changed `.skill` file.

## Does a description trigger the skill?

`evals/trigger/<skill>.json` holds queries that should and should not load
each skill (near-misses on purpose: a description that is too broad fires on
them). They are in the format the skill-creator tools take, so a description
change can be measured rather than guessed:

```
python -m scripts.run_eval --eval-set evals/trigger/<skill>.json \
  --skill-path skills/<skill> --runs-per-query 3 --verbose
```

(run from the skill-creator directory; it calls `claude -p`, so it spends
tokens and is not part of CI). Treat a miss as a prompt to fix the
description, then add the query that exposed it to the file.

Add a lesson when a project teaches one: a failure that cost time, with the
reason, in the skill it belongs to. Keep the descriptions specific; every
enabled skill's description loads into every session.
