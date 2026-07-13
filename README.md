# dotharness

Host-level configuration hub for Claude Code. Clone once; `setup.sh` symlinks skills, rules, hooks, agents, CLI tools, and libraries into `~/.claude/`, `~/bin/`, and `~/lib/` so they are available in **every repo on this machine** — no per-project install needed.

## How it works

Everything lives here and is symlinked outward:

| Source | Symlink target | Available as |
|---|---|---|
| `rules/` | `~/.claude/rules/` | Always-loaded / path-scoped Claude rules |
| `skills/` | `~/.claude/skills/` | `/skill-name` invocations in any session |
| `agents/` | `~/.claude/agents/` | Subagent worker roles |
| `hooks/` | `~/.claude/hooks/` | Lifecycle scripts (PreToolUse, SessionStart, …) |
| `output-styles/` | `~/.claude/output-styles/` | Voice/format presets |
| `bin/` | `~/bin/` (on PATH) | CLI commands (`ckBuild`, `ckRunProfile`, `llm`, …) |
| `lib/` | `~/lib/` | Internal libraries imported by `bin/` scripts |
| `gitignore_global` | `~/.gitignore_global` | Git ignore patterns applied to every repo via `core.excludesFile` |

Changes to any file here take effect immediately in all repos — no reinstall.

## Structure

```text
CLAUDE.md              → guidance for Claude Code in this repo; AGENTS.md is a symlink to it
skills/                → own skills                                        (skills/README.md)
agents/                → native subagents (worker roles)                   (agents/README.md)
hooks/                 → lifecycle hook scripts                            (hooks/README.md)
rules/                 → user-level rules loaded by Claude Code            (rules/README.md)
output-styles/         → output styles                                     (output-styles/README.md)
bin/                   → helper scripts, symlinked to ~/bin/ (on PATH)     (bin/README.md)
lib/                   → internal libraries, symlinked to ~/lib/
  ck-profile/          → Python libs + data for ck*Profile binaries        (lib/ck-profile/README.md)
  ck-profile-mcp/      → ck-profile MCP server (registered at user scope)
tests/                 → bats + pytest suites                              (tests/README.md)
third-party/
  mattpocock-skills/   → git submodule (engineering + productivity skills)
template/              → templates for plan/implementation-notes/test-notes docs
statusline.sh          → compact status line, symlinked to ~/.claude/
gitignore_global       → global git ignore patterns, symlinked to ~/.gitignore_global
setup.sh               → symlinks, hooks, output style, plugins, pre-commit provisioning
graphify-out/          → generated knowledge graph (gitignored; see CLAUDE.md's graphify section)
```

Non-trivial work in this repo follows a plan-first workflow: copy `template/plan.md` into
`plans/<date>-<slug>.md`, get it reviewed, then log implementation deviations and test notes into
`notes/<date>-<slug>-implementation.md` / `-test.md` (templates in `template/`) as work happens.
`plans/` and `notes/` are gitignored — local-only, not committed.

## Setup

```bash
git submodule update --init
./setup.sh
```

Symlinks `skills/`, `agents/`, `hooks/`, `output-styles/`, `rules/`, third-party skills, and `statusline.sh` into `~/.claude/`; `bin/` scripts into `~/bin/`; `lib/` subdirs into `~/lib/`; `gitignore_global` to `~/.gitignore_global` and registers it as `git config --global core.excludesFile`. Registers hooks and sets the `dotharness` output style in `~/.claude/settings.json` (requires `jq`), creating that file if it does not yet exist (fresh-machine safe). Installs plugins via the Claude CLI, and registers the `ck-profile` MCP server at user scope. Installs [`playwright-cli`](https://github.com/microsoft/playwright-cli) (npm) and [`graphify`](https://github.com/Graphify-Labs/graphify) (pipx) globally, both externally-managed and not sourced from `skills/`. Provisions a repo-local `.venv` with `pre-commit`, `anthropic`, and `mcp`, and installs the git pre-commit hook. If the `codex` CLI is present, mirrors skills/hooks/statusline/plugins into `~/.agents/` and `~/.codex/` and concatenates `rules/*.md` into a generated `~/.agents/AGENTS.md`. Existing files are backed up to `.bak`. Re-running is idempotent. Per-folder `README.md` files are skipped so they document the repo without being linked into the live `~/.claude/` tree.

Optional: desktop notifications work out of the box, but Teams notifications need a webhook URL you configure manually — see [hooks/README.md](hooks/README.md#teams-notifications).

## Documentation

Each component is documented next to its code:

- [Rules](rules/README.md) — always-loaded and path-scoped rule files
- [Skills](skills/README.md) — own skills, third-party submodule skills, and plugins
- [Agents](agents/README.md) — native subagents and how `dev-team` uses them
- [Hooks](hooks/README.md) — lifecycle hooks and Teams notification setup
- [Output styles](output-styles/README.md) — the `dotharness` voice
- [Binaries](bin/README.md) — `bin/` helper scripts on `PATH`
- [CK profile libs](lib/ck-profile/README.md) — internal Python libs and data for `ck*Profile` binaries
- [Tests](tests/README.md) — the bats hook/script suites and the pytest suite for the ck-profile helpers

## Pre-commit and CI

A `pre-commit` gate runs lint, format, and secret checks on every commit, and a GitHub Actions workflow enforces the same set on push and pull request.

**Hooks (`.pre-commit-config.yaml`), framework-managed:**

- `shellcheck` — shell linting (hooks, `bin/`, `statusline.sh`, `setup.sh`, skill scripts)
- `shfmt` — shell formatting at 4-space indent (`-i 4`), matching `auto-format.sh`
- `ruff` + `ruff-format` — Python lint and format for the ck-profile scripts
- `typos` — spell-checking for code and docs; `_typos.toml` allowlists GPU terms (`VALU`, `HSA`) that are not typos
- `actionlint` (docker) — GitHub Actions workflow linting, including the embedded `run:` shell via the image's bundled shellcheck
- `markdownlint` — Markdown style/structure checks (`.markdownlint.json`)
- `gitleaks` — secret scanning on staged diffs (regex + entropy)
- `pre-commit-hooks` — trailing whitespace, end-of-file, merge-conflict, large-file, JSON/YAML validity, shebang/executable consistency, case-conflict, mixed-line-ending (LF), and `detect-private-key` (excluding `security-scan.sh`, which greps for the key-header marker)

`setup.sh` provisions a repo-local `.venv`, installs `pre-commit` into it, and registers the git hook. Run the gate manually with `.venv/bin/pre-commit run --all-files`. The `actionlint` hook runs in a container, so it needs a running Docker daemon.

**CI (`.github/workflows/ci.yml`).** Four jobs on push and pull request: `pre-commit` (all hooks on all files), `bats` (installs `bats`/`jq`/`python3-yaml`, runs the shell [tests](tests/README.md) in `tests/bats/`), `pytest` (runs the Python [tests](tests/README.md) in `tests/python/`), and `gitleaks` (full-history secret scan with `fetch-depth: 0`, catching secrets the staged-only pre-commit hook cannot see).

## Statusline

`statusline.sh` renders a compact single line: directory, git branch, time, model, session name, context usage, effort level, output style, and thinking indicator.
