#!/bin/bash
# SessionStart hook for Claude Code cloud sessions: install dependencies and start the
# local Postgres the database tests need. Idempotent; local machines skip it.
#
# Register in .claude/settings.json:
#   {"hooks": {"SessionStart": [{"hooks": [{"type": "command",
#     "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/session-start.sh"}]}]}}
#
# Adapt: the install command, database names, and the exported variables.
set -euo pipefail

if [ "${CLAUDE_CODE_REMOTE:-}" != "true" ]; then
  exit 0
fi

cd "$CLAUDE_PROJECT_DIR"

# Dependencies. `npm install` (not `ci`) reuses node_modules from the cached container state.
# Python: `pip install -r requirements.txt` or `uv sync`.
npm install --no-audit --no-fund

# Postgres. Cloud sandboxes often have a cluster installed but stopped.
if command -v pg_lsclusters >/dev/null; then
  version=$(pg_lsclusters --no-header | awk 'NR==1 {print $1}')
  if [ -n "$version" ] && ! pg_lsclusters "$version" main | grep -q online; then
    pg_ctlcluster "$version" main start
  fi
  runuser -u postgres -- psql -q -c "alter user postgres password 'postgres'"
  for name in app_test app_e2e; do
    if ! runuser -u postgres -- psql -tAc "select 1 from pg_database where datname = '$name'" | grep -q 1; then
      runuser -u postgres -- psql -q -c "create database $name"
    fi
  done
fi

# Session environment. Without the test DB URL, database tests skip and the runner still says green.
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  echo 'export TEST_DATABASE_URL=postgresql://postgres:postgres@localhost:5432/app_test' >> "$CLAUDE_ENV_FILE"
  chromium=$(ls -d /opt/pw-browsers/chromium-*/chrome-linux*/chrome 2>/dev/null | head -1 || true)
  if [ -n "$chromium" ]; then
    echo "export PLAYWRIGHT_CHROMIUM_PATH=$chromium" >> "$CLAUDE_ENV_FILE"
  fi
fi
