#!/bin/bash
# Stop hook: before Claude declares the work done, run the project's fast checks and refuse to stop while
# they fail or while database tests were skipped (a skipped run still reports green).
#
# Expects `scripts/fast-checks.sh` in the repo: typecheck, lint and the unit tests with the test database
# URL set, exiting non-zero on failure. Override with FAST_CHECKS. Needs jq.
#
# Loop guard: after MAX_BLOCKS consecutive refusals in one session the hook lets Claude stop and say what
# is still failing, so a check that can't be fixed from here never traps the session.
set -uo pipefail

MAX_BLOCKS=${MAX_BLOCKS:-2}
REQUIRE_NO_SKIPS=${REQUIRE_NO_SKIPS:-1}

command -v jq >/dev/null || { echo "stop-check: jq not installed, hook is NOT active" >&2; exit 0; }
input=$(cat)
sid=$(jq -r '.session_id // "nosession"' <<<"$input")
root=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
cd "$root" || exit 0

counter="${TMPDIR:-/tmp}/claude-stop-check-$sid"
checks=${FAST_CHECKS:-}
[ -z "$checks" ] && [ -x scripts/fast-checks.sh ] && checks=scripts/fast-checks.sh
[ -n "$checks" ] || exit 0                                     # project hasn't defined checks yet

# Nothing changed since the last commit and nothing untracked: nothing to verify.
[ -n "$(git status --porcelain 2>/dev/null)" ] || { rm -f "$counter"; exit 0; }

block() {
  n=$(( $(cat "$counter" 2>/dev/null || echo 0) + 1 ))
  if [ "$n" -gt "$MAX_BLOCKS" ]; then rm -f "$counter"; exit 0; fi
  echo "$n" > "$counter"
  jq -n --arg r "$1" '{decision: "block", reason: $r}'
  exit 0
}

out=$(timeout 540 bash -c "$checks" 2>&1); code=$?
tail=$(echo "$out" | tail -40)

if [ $code -ne 0 ]; then
  block "The fast checks failed (exit $code). Fix the cause; do not skip, loosen or delete a test. Last output:
$tail"
fi
if [ "$REQUIRE_NO_SKIPS" = "1" ] && echo "$out" | grep -qE '(^|[^0-9])[1-9][0-9]* (skipped|todo)'; then
  block "The checks passed but some tests were SKIPPED, so they proved nothing. Usually the test database URL is not set or Postgres is not running (see the verify skill, step 1). Fix that and rerun. Summary lines:
$(echo "$out" | grep -E 'skipped|todo' | head -10)"
fi

rm -f "$counter"
exit 0
