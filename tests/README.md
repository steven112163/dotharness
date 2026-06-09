# Tests

`block-dangerous.bats` exercises the `block-dangerous.sh` guard with 34 cases: `rm -rf` (path, glob, home, split flags), force-push variants, `reset --hard`, `git clean`, `DROP TABLE`, `.env`/`/etc`/`/tmp` writes, and `killall`, plus the allow cases (bare relative `rm`, the repo's `.claude/tmp`, ordinary source files, `.env.example`).

Run with `bats tests/`. CI runs the same suite (the `bats` job installs `bats`/`jq` on the runner).
