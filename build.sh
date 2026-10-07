#!/bin/bash
# Package every skill in skills/ into dist/<name>.skill for upload to claude.ai.
# Uses the skill-creator packager (validates frontmatter, then zips the folder).
# SKILL_CREATOR defaults to the copy synced into Claude Code sessions.
set -euo pipefail

root=$(cd "$(dirname "$0")" && pwd)
creator=${SKILL_CREATOR:-$(ls -d /root/.claude/skills/synced/*/skill-creator 2>/dev/null | head -1)}
if [ -z "$creator" ] || [ ! -f "$creator/scripts/package_skill.py" ]; then
  echo "skill-creator not found; set SKILL_CREATOR=/path/to/skill-creator" >&2
  exit 1
fi

mkdir -p "$root/dist"
for skill in "$root"/skills/*/; do
  (cd "$creator" && python3 -m scripts.package_skill "$skill" "$root/dist")
done
ls -l "$root/dist"
