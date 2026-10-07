# Release flow: `main` is staging, `production` moves only by promotion

For a web app on a git-deploying host (Vercel, Netlify, Render) with hosted
Postgres. Before launch, a simpler "merge to main = deploy" is fine if migrations
are add-only; switch to this at launch.

## Pieces

1. **Host**: production deploys from a `production` branch; every other branch,
   including `main`, deploys as staging/preview with staging env vars.
2. **`db-migrate.yml`**: on push to `main` touching the migrations folder, migrate
   **staging**. Also `workflow_call` with a `target` input, so the promote workflow
   can migrate production.
3. **`promote.yml`** (manual, `workflow_dispatch` with an optional commit):
   - *check*: the commit is on `main`; CI passed on that exact commit (query the
     check runs); `production` only moves forward (`git merge-base --is-ancestor`).
   - *migrate*: call `db-migrate.yml` with `target: production`, in a GitHub
     environment `production` that has a required reviewer.
   - *release*: fast-forward `production` to the commit and push with a **deploy
     key** that has write access (GitHub's built-in token may not push commits that
     change workflow files). No force push.
4. **Branch ruleset on `production`**: restrict updates, block force pushes and
   deletion, deploy key in the bypass list. Only the workflow moves it.

## One-time setup (owner)

- GitHub environment `production` with themselves as required reviewer.
- `ssh-keygen -t ed25519 -N "" -f production_deploy_key`; add the `.pub` as a
  deploy key with write access; add the private key as secret
  `PRODUCTION_DEPLOY_KEY`; delete both local files.
- Secrets `STAGING_DATABASE_URL`, `PRODUCTION_DATABASE_URL`.

## Release

1. Merge to `main`; wait for CI, the staging deploy, and the staging migration.
2. Check the change on staging (for payments: one sandbox purchase).
3. Run **Promote to production**; approve the production migration.
4. Health endpoint answers OK; error tracker shows the new release without new
   errors for 15 minutes.

## Roll back

- Code: the host's instant rollback to the previous production deployment, then
  fix forward on `main` and promote again.
- Database: never roll back a migration. Add a migration that fixes it.
- Bad data (not schema): restore from backup only for real loss, into staging
  first.

## Guards worth adding to CI

- Applied migrations are never edited (ci-migration-guard.yml).
- Any date-based launch switch (e.g. a cron schedule that must change when the
  hosting plan changes) as a CI check that warns before the date and fails after,
  so it can't be forgotten.
