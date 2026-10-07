#!/usr/bin/env python3
"""Validate every skill in skills/ and the files built from them. Run locally and in CI.

Checks (the first group mirrors the skill-creator packager, so a failure here is a failure at upload):
  frontmatter keys, name == folder and kebab-case, description <= 1024 chars with no angle brackets,
  exactly one SKILL.md per skill;
and the ones that rot silently:
  SKILL.md <= 500 lines, relative markdown links resolve, reference .sh files parse with `bash -n`,
  .json/.yml/.yaml references parse, dist/<name>.skill contents match skills/<name>, and the trigger
  eval files under evals/trigger/ are well formed.

Exit 0 when clean, 1 otherwise. Needs PyYAML (pip install pyyaml).
"""
import json, re, subprocess, sys, zipfile
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent
SKILLS = ROOT / "skills"
DIST = ROOT / "dist"
ALLOWED = {"name", "description", "license", "allowed-tools", "metadata", "compatibility"}
MAX_DESC, MAX_LINES = 1024, 500
errors: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def check_frontmatter(skill: Path) -> None:
    md = skill / "SKILL.md"
    if not md.exists():
        return err(f"{skill.name}: SKILL.md missing")
    text = md.read_text()
    m = re.match(r"^---\n(.*?)\n---\n", text, re.S)
    if not m:
        return err(f"{skill.name}: no YAML frontmatter")
    try:
        fm = yaml.safe_load(m.group(1))
    except yaml.YAMLError as e:
        return err(f"{skill.name}: invalid frontmatter YAML: {e}")
    if not isinstance(fm, dict):
        return err(f"{skill.name}: frontmatter is not a mapping")
    if extra := set(fm) - ALLOWED:
        err(f"{skill.name}: unexpected frontmatter keys {sorted(extra)}")
    name, desc = fm.get("name"), fm.get("description")
    if name != skill.name:
        err(f"{skill.name}: frontmatter name {name!r} must equal the folder name")
    if isinstance(name, str) and not re.fullmatch(r"[a-z0-9]+(-[a-z0-9]+)*", name):
        err(f"{skill.name}: name must be kebab-case")
    if not isinstance(desc, str) or not desc.strip():
        err(f"{skill.name}: description missing")
    else:
        if len(desc) > MAX_DESC:
            err(f"{skill.name}: description is {len(desc)} chars, max {MAX_DESC}")
        if "<" in desc or ">" in desc:
            err(f"{skill.name}: description contains angle brackets")
    lines = text.count("\n") + 1
    if lines > MAX_LINES:
        err(f"{skill.name}: SKILL.md is {lines} lines, max {MAX_LINES} (move detail to references/)")
    if len(list(skill.rglob("SKILL.md"))) != 1:
        err(f"{skill.name}: a skill must contain exactly one SKILL.md")


def check_links(skill: Path) -> None:
    for md in skill.rglob("*.md"):
        for target in re.findall(r"\]\(([^)\s]+)\)", md.read_text()):
            if re.match(r"^(https?:|mailto:|#)", target):
                continue
            path = (md.parent / target.split("#")[0]).resolve()
            if not path.exists():
                err(f"{md.relative_to(ROOT)}: broken link {target}")


def check_reference_files(skill: Path) -> None:
    for f in skill.rglob("*"):
        if not f.is_file():
            continue
        rel = f.relative_to(ROOT)
        if f.suffix == ".sh":
            r = subprocess.run(["bash", "-n", str(f)], capture_output=True, text=True)
            if r.returncode:
                err(f"{rel}: shell syntax error: {r.stderr.strip()}")
        elif f.suffix == ".json":
            try:
                json.loads(f.read_text())
            except ValueError as e:
                err(f"{rel}: invalid JSON: {e}")
        elif f.suffix in (".yml", ".yaml"):
            try:
                yaml.safe_load(f.read_text())
            except yaml.YAMLError as e:
                err(f"{rel}: invalid YAML: {e}")


def check_dist(skill: Path) -> None:
    pkg = DIST / f"{skill.name}.skill"
    if not pkg.exists():
        return err(f"dist/{skill.name}.skill missing: run ./build.sh")
    with zipfile.ZipFile(pkg) as z:
        packed = {n.split("/", 1)[1]: z.read(n) for n in z.namelist()
                  if not n.endswith("/") and "/" in n and n.split("/", 1)[0] == skill.name}
    current = {str(p.relative_to(skill)): p.read_bytes() for p in skill.rglob("*")
               if p.is_file() and "__pycache__" not in p.parts}
    for rel in sorted(set(packed) | set(current)):
        if rel not in packed:
            err(f"dist/{skill.name}.skill is stale: missing {rel} (run ./build.sh)")
        elif rel not in current:
            err(f"dist/{skill.name}.skill is stale: contains deleted {rel} (run ./build.sh)")
        elif packed[rel] != current[rel]:
            err(f"dist/{skill.name}.skill is stale: {rel} differs (run ./build.sh)")


def check_trigger_evals(names: set[str]) -> None:
    folder = ROOT / "evals" / "trigger"
    for name in sorted(names):
        f = folder / f"{name}.json"
        if not f.exists():
            err(f"evals/trigger/{name}.json missing (queries that should and should not trigger the skill)")
            continue
        try:
            items = json.loads(f.read_text())
        except ValueError as e:
            err(f"{f.relative_to(ROOT)}: invalid JSON: {e}")
            continue
        ok = isinstance(items, list) and all(
            isinstance(i, dict) and isinstance(i.get("query"), str) and isinstance(i.get("should_trigger"), bool)
            for i in items)
        if not ok:
            err(f"{f.relative_to(ROOT)}: must be a list of {{query: str, should_trigger: bool}}")
            continue
        pos = sum(i["should_trigger"] for i in items)
        if pos < 4 or len(items) - pos < 4:
            err(f"{f.relative_to(ROOT)}: needs at least 4 positive and 4 negative queries ({pos}/{len(items) - pos})")
    for f in folder.glob("*.json") if folder.exists() else []:
        if f.stem not in names:
            err(f"{f.relative_to(ROOT)}: no skill named {f.stem}")


def main() -> int:
    skills = sorted(p for p in SKILLS.iterdir() if p.is_dir())
    if not skills:
        err("no skills found")
    for s in skills:
        check_frontmatter(s)
        check_links(s)
        check_reference_files(s)
        check_dist(s)
    check_trigger_evals({s.name for s in skills})
    for p in sorted(DIST.glob("*.skill")) if DIST.exists() else []:
        if not (SKILLS / p.stem).is_dir():
            err(f"dist/{p.name}: no matching skill folder (delete it)")
    if errors:
        print("\n".join(f"FAIL {e}" for e in errors))
        print(f"\n{len(errors)} problem(s)")
        return 1
    print(f"ok: {len(skills)} skills valid, dist in sync, trigger evals well formed")
    return 0


if __name__ == "__main__":
    sys.exit(main())
