#!/bin/bash
# scripts/fast-checks.sh: the one command that means "this change is not obviously broken".
# The Stop hook runs it before Claude may finish; CI runs the same steps; `verify` points at it.
# Keep it under ~2 minutes (anything slower belongs in CI or E2E). Adapt the commands.
#
# It must exit non-zero on any failure, and must print the test summary line (with the skipped count)
# because the Stop hook refuses a run that skipped tests.
set -euo pipefail
cd "$(dirname "$0")/.."

# Database tests skip without this, and the runner still says green.
: "${TEST_DATABASE_URL:?TEST_DATABASE_URL is not set: database tests would skip (see the verify skill, step 1)}"

npm run typecheck
npm run lint
npm test -- --run          # Python: pytest -q -rs   (prints skip reasons)
