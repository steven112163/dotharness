# Tests

Two suites live here: bats for the shell hooks and skill scripts (under
`tests/bats/`), pytest for the ck-profile Python helpers (under `tests/python/`).

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

Run with `bats tests/bats/`. CI runs the same suite (the `bats` job installs
`bats`/`jq`/`python3-yaml` on the runner).

## pytest (Python)

`test_gpu_specs.py`, `test_parse_resource_usage.py`, and `test_aggregate.py` cover
the pure helpers in `bin/` and `lib/ck-profile/` (hardware-spec lookups, build-log
parsing and VGPR/spill math, bottleneck classification and stats).

`test_ckprofile_mcp_job_store.py`, `test_ckprofile_mcp_server.py`,
`test_ckprofile_mcp_validation.py`, and `test_ckprofile_mcp_detach.py` cover the
ck-profile MCP server in `lib/ck-profile-mcp/`: job state/reconciliation/retention,
the `run_profile`/`get_job_status`/`get_summary` tool surface (`ckRemote` stubbed via
a fake `PATH` entry), input validation, and the `start_new_session=True` detachment
`run_profile` relies on.

`conftest.py` puts `bin/`, `lib/ck-profile/`, and `lib/ck-profile-mcp/` on `sys.path`
so all of the above import by name.

Run with `pytest` (config in `pyproject.toml` points at `tests/python`). CI runs
it in the `pytest` job.
