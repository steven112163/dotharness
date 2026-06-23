# dotharness

Personal monorepo for Claude Code skills, rules, and configuration.

## Structure

```text
skills/                → own skills, symlinked to ~/.claude/skills/        (skills/README.md)
  dev-team/            → agent team orchestration (lead spawns native agents as teammates)
  research/            → multi-mode research with anti-sycophancy safeguards
  survey/              → literature survey with grounded citations
  create-pr/           → PR creation with CK team template
  ck-profile/          → static + runtime GPU profiling of a CK target
  multi-review/        → multi-angle code review, consolidated and validated
  council/             → multi-model debate (GPT, DeepSeek, Gemini) with synthesis
  llm/                 → external LLM gateway skill (wraps bin/llm)
agents/                → native subagents (worker roles)                   (agents/README.md)
hooks/                 → lifecycle hook scripts                            (hooks/README.md)
rules/                 → user-level rules loaded by Claude Code            (rules/README.md)
output-styles/         → output styles                                     (output-styles/README.md)
bin/                   → helper scripts, symlinked to ~/bin/ (on PATH)     (bin/README.md)
tests/                 → bats + pytest suites (tests/bats, tests/python)   (tests/README.md)
third-party/
  mattpocock-skills/   → git submodule (engineering + productivity skills)
statusline.sh          → compact status line, symlinked to ~/.claude/
setup.sh               → symlinks, hooks, output style, plugins, pre-commit provisioning
.pre-commit-config.yaml → lint/format/secret gate
.github/workflows/ci.yml → CI: pre-commit + bats + pytest + full-history gitleaks
```

## Setup

```bash
git submodule update --init
./setup.sh
```

Symlinks `skills/`, `hooks/`, `output-styles/`, `rules/`, third-party skills, and `statusline.sh` into `~/.claude/`, and `bin/` scripts into `~/bin/`. Registers hooks and sets the `dotharness` output style in `~/.claude/settings.json` (requires `jq`), creating that file if it does not yet exist (fresh-machine safe). Installs plugins via the Claude CLI. Provisions a repo-local `.venv` with `pre-commit` and installs the git pre-commit hook. Existing files are backed up to `.bak`. Re-running is idempotent. Per-folder `README.md` files are skipped, so they document the repo without being linked into the live `~/.claude/` tree.

Optional: desktop notifications work out of the box, but Teams notifications need a webhook URL you configure manually — see [hooks/README.md](hooks/README.md#teams-notifications).

## Documentation

Each component is documented next to its code:

- [Rules](rules/README.md) — always-loaded and path-scoped rule files
- [Skills](skills/README.md) — own skills, third-party submodule skills, and plugins
- [Agents](agents/README.md) — native subagents and how `dev-team` uses them
- [Hooks](hooks/README.md) — lifecycle hooks and Teams notification setup
- [Output styles](output-styles/README.md) — the `dotharness` voice
- [Binaries](bin/README.md) — `bin/` helper scripts on `PATH`
- [Tests](tests/README.md) — the bats hook/script suites and the pytest suite for the ck-profile helpers

## Pre-commit and CI

A `pre-commit` gate runs lint, format, and secret checks on every commit, and a GitHub Actions workflow enforces the same set on push and pull request.

**Hooks (`.pre-commit-config.yaml`), framework-managed:**

- `shellcheck` — shell linting (hooks, `bin/`, `statusline.sh`, `setup.sh`, skill scripts)
- `shfmt` — shell formatting at 4-space indent (`-i 4`), matching `auto-format.sh`
- `ruff` + `ruff-format` — Python lint and format for the ck-profile scripts
- `typos` — spell-checking for code and docs; `_typos.toml` allowlists GPU terms (`VALU`, `HSA`) that are not typos
- `actionlint` (docker) — GitHub Actions workflow linting, including the embedded `run:` shell via the image's bundled shellcheck
- `gitleaks` — secret scanning on staged diffs (regex + entropy)
- `pre-commit-hooks` — trailing whitespace, end-of-file, merge-conflict, large-file, JSON/YAML validity, shebang/executable consistency, case-conflict, mixed-line-ending (LF), and `detect-private-key` (excluding `security-scan.sh`, which greps for the key-header marker)

`setup.sh` provisions a repo-local `.venv`, installs `pre-commit` into it, and registers the git hook. Run the gate manually with `.venv/bin/pre-commit run --all-files`. The `actionlint` hook runs in a container, so it needs a running Docker daemon.

**CI (`.github/workflows/ci.yml`).** Four jobs on push and pull request: `pre-commit` (all hooks on all files), `bats` (installs `bats`/`jq`/`python3-yaml`, runs the shell [tests](tests/README.md) in `tests/bats/`), `pytest` (runs the Python [tests](tests/README.md) in `tests/python/`), and `gitleaks` (full-history secret scan with `fetch-depth: 0`, catching secrets the staged-only pre-commit hook cannot see).

## Statusline

`statusline.sh` renders a compact single line: directory, git branch, time, model, session name, context usage, effort level, output style, and thinking indicator.
