#!/bin/bash
# PreToolUse hook (matcher Edit|Write|MultiEdit|NotebookEdit): refuse edits that a project rule forbids,
# so the rule holds even when the agent forgot it. Denial text goes back to Claude as the reason.
#
# Blocks: (1) a migration that already exists on the default branch (applied migrations are never edited),
#         (2) real secret files (.env, keys), (3) hand-edited lockfiles (run the package manager instead).
# Needs jq. Adapt MIGRATIONS_DIR and the lists below.
set -uo pipefail

MIGRATIONS_DIR=${MIGRATIONS_DIR:-supabase/migrations}

command -v jq >/dev/null || { echo "guard-edit: jq not installed, guard is NOT active" >&2; exit 0; }
input=$(cat)
file=$(jq -r '.tool_input.file_path // .tool_input.notebook_path // empty' <<<"$input")
[ -n "$file" ] || exit 0

root=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
rel=${file#"$root"/}

deny() {
  jq -n --arg r "$1" '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $r}}'
  exit 0
}

# 1. Applied migrations are immutable. "Applied" = present on the default branch.
case "$rel" in
  "$MIGRATIONS_DIR"/*)
    base=$(git -C "$root" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
    if git -C "$root" cat-file -e "$base:$rel" 2>/dev/null; then
      deny "$rel already exists on $base, so it has run on staging or production. Editing it changes nothing there. Add a new numbered migration that fixes it."
    fi
    ;;
esac

# 2. Secrets are never written by the agent (examples are fine).
case "$(basename "$rel")" in
  .env.example|.env.sample|.env.template) ;;
  .env|.env.*|*.pem|*.key|id_rsa|id_ed25519)
    deny "$rel looks like a secrets file. Do not write secrets from a session; document the variable in .env.example and ask the owner to set the value."
    ;;
esac

# 3. Lockfiles come from the package manager.
case "$(basename "$rel")" in
  package-lock.json|pnpm-lock.yaml|yarn.lock|bun.lockb|uv.lock|poetry.lock|Cargo.lock)
    deny "$rel is generated. Change the manifest and run the package manager (npm install, pnpm install, uv lock) instead of editing the lockfile."
    ;;
esac

exit 0
