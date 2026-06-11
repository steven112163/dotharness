# Tests

Two suites live here: bats for the shell hooks and skill scripts, pytest for the
ck-profile Python helpers.

## bats (shell)

- `block-dangerous.bats` — the `block-dangerous.sh` guard: `rm -rf` (path, glob,
  home, split flags), force-push variants, `reset --hard`, `git clean`,
  `DROP TABLE`, `.env`/`/etc`/`/tmp` writes, and `killall`, plus the allow cases
  (bare relative `rm`, the repo's `.claude/tmp`, ordinary source files,
  `.env.example`).
- `commit-lint.bats` — the `commit-lint.sh` conventional-commit check: conforming
  messages (scoped, single-quoted, heredoc) pass; malformed ones (no type, wrong
  separator, bad type case, uppercase subject, trailing period, over 72 chars) are
  denied; non-commit, amend-reuse, `--allow-empty-message`, and non-Bash calls skip.
- `skills-frontmatter.bats` — every `skills/*/SKILL.md` frontmatter parses as YAML,
  with `name` matching the directory and a non-empty `description` (needs PyYAML).
- `multi-review.bats` — the `gather_context.sh` context builder (local-mode diff
  capture, chunk split, relative `REVIEW_DIR`).

Run with `bats tests/`. CI runs the same suite (the `bats` job installs
`bats`/`jq`/`python3-yaml` on the runner).

## pytest (Python)

`test_gpu_specs.py`, `test_parse_resource_usage.py`, and `test_aggregate.py` cover
the pure helpers in `skills/ck-profile/scripts/` (hardware-spec lookups, build-log
parsing and VGPR/spill math, bottleneck classification and stats). `conftest.py`
puts the script directory on `sys.path` so they import by name.

Run with `pytest` (config in `pyproject.toml`). CI runs it in the `pytest` job.
