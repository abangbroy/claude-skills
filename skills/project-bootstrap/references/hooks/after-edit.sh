#!/bin/bash
# PostToolUse hook (matcher Edit|Write|MultiEdit): format and lint ONLY the file just edited, so
# mistakes surface one edit after they happen instead of at the end of a long session.
# Fast on purpose (whole-project typecheck belongs in the Stop hook). Silent when a tool isn't installed.
# On a lint error it returns decision "block" with the output so Claude fixes it now. Needs jq.
set -uo pipefail

command -v jq >/dev/null || { echo "after-edit: jq not installed, hook is NOT active" >&2; exit 0; }
input=$(cat)
file=$(jq -r '.tool_response.filePath // .tool_input.file_path // empty' <<<"$input")
[ -n "$file" ] && [ -f "$file" ] || exit 0

root=${CLAUDE_PROJECT_DIR:-$(git rev-parse --show-toplevel 2>/dev/null || pwd)}
cd "$root" || exit 0
bin="$root/node_modules/.bin"
out=""

case "$file" in
  *.ts|*.tsx|*.js|*.jsx|*.mjs|*.cjs)
    [ -x "$bin/prettier" ] && timeout 30 "$bin/prettier" --write "$file" >/dev/null 2>&1
    if [ -x "$bin/eslint" ]; then
      out=$(timeout 60 "$bin/eslint" --no-warn-ignored "$file" 2>&1) || true
      # eslint exits non-zero on errors only; an empty-or-clean run leaves out empty of "error".
      echo "$out" | grep -qE '(^|[[:space:]])error([[:space:]]|$)' || out=""
    fi
    ;;
  *.json|*.css|*.md|*.yml|*.yaml)
    [ -x "$bin/prettier" ] && timeout 30 "$bin/prettier" --write "$file" >/dev/null 2>&1
    ;;
  *.py)
    if command -v ruff >/dev/null; then
      timeout 30 ruff format "$file" >/dev/null 2>&1
      out=$(timeout 30 ruff check "$file" 2>&1) || true
      echo "$out" | grep -qE 'All checks passed|^$' && out=""
    fi
    ;;
esac

if [ -n "$out" ]; then
  jq -n --arg r "Lint errors in ${file#"$root"/} after your edit. Fix them before continuing:
$(echo "$out" | head -40)" '{decision: "block", reason: $r}'
fi
exit 0
