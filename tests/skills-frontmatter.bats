#!/usr/bin/env bats
# Validates the frontmatter of every own skill's SKILL.md: it must parse as a
# YAML mapping, its `name` must match the directory (skill discovery relies on
# this), `description` must be a non-empty string, and `argument-hint`, when
# present, must be a non-empty string.

@test "all skills have valid SKILL.md frontmatter" {
    skills_dir="${BATS_TEST_DIRNAME}/../skills"
    run python3 -c '
import sys, os, glob, yaml
root = sys.argv[1]
paths = sorted(glob.glob(os.path.join(root, "*", "SKILL.md")))
assert paths, "no SKILL.md files found under " + root
errors = []
for p in paths:
    name_dir = os.path.basename(os.path.dirname(p))
    text = open(p, encoding="utf-8").read()
    if not text.startswith("---\n"):
        errors.append(name_dir + ": missing frontmatter block")
        continue
    try:
        fm = yaml.safe_load(text.split("---\n", 2)[1])
    except yaml.YAMLError as e:
        errors.append(name_dir + ": YAML error: " + str(e))
        continue
    if not isinstance(fm, dict):
        errors.append(name_dir + ": frontmatter is not a mapping")
        continue
    if fm.get("name") != name_dir:
        errors.append(name_dir + ": name=" + repr(fm.get("name")) + " does not match directory")
    desc = fm.get("description")
    if not (isinstance(desc, str) and desc.strip()):
        errors.append(name_dir + ": empty or missing description")
    if "argument-hint" in fm:
        ah = fm.get("argument-hint")
        if not (isinstance(ah, str) and ah.strip()):
            errors.append(name_dir + ": argument-hint present but empty")
if errors:
    print("\n".join(errors))
    sys.exit(1)
' "$skills_dir"
    [ "$status" -eq 0 ]
}
