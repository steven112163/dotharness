# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

`AGENTS.md` is a symlink to this file, so Codex reads the same content.

## Purpose

dotharness is a **host-level configuration hub**: `setup.sh` symlinks everything into `~/.claude/`, `~/bin/`, and `~/lib/` so all skills, rules, hooks, agents, and CK tooling are available in **every repo on this machine** — not just this one. Changes here take effect immediately across all projects without reinstalling. Codex is a first-class second target: `setup.sh` mirrors skills, rules, hooks, statusline, and plugins into `~/.agents/` and `~/.codex/` whenever the `codex` CLI is present.

## Setup

```bash
git submodule update --init
./setup.sh
```

`setup.sh` symlinks `skills/`, `agents/`, `hooks/`, `rules/`, `output-styles/`, third-party skills, and `statusline.sh` into `~/.claude/`; symlinks `bin/` scripts into `~/bin/`; symlinks `lib/` subdirs into `~/lib/`; symlinks `gitignore_global` to `~/.gitignore_global` and registers it as `git config --global core.excludesFile`; registers lifecycle hooks in `~/.claude/settings.json`; installs Claude plugins; installs `playwright-cli` (npm) and `graphify` (pipx) globally; provisions a repo-local `.venv` with `pre-commit`, `anthropic`, and `mcp`; and registers the `ck-profile` MCP server at user scope (`claude mcp add -s user ck-profile`). If the `codex` CLI is present, it also mirrors skills/hooks/statusline into `~/.agents/` and `~/.codex/`, concatenates `rules/*.md` into `~/.agents/AGENTS.md`, and runs `graphify install --platform codex`. Re-running is idempotent. Requires `jq`.

`README.md` files inside linked directories are intentionally skipped — they document the repo without being parsed as active rules or skills.

## Commands

```bash
# Lint and format
.venv/bin/pre-commit run --all-files

# Shell tests
bats tests/bats/

# Python tests
pytest

# Single bats file
bats tests/bats/commit-lint.bats

# External LLM query (gateway required)
bin/llm -m gpt-5.5 --thinking "your question"
```

CI (`.github/workflows/ci.yml`) runs four jobs: `pre-commit`, `bats`, `pytest`, and `gitleaks`
(full-history secret scan). `.pre-commit-config.yaml` wires `shellcheck`, `shfmt`, `ruff`/
`ruff-format`, `typos`, `actionlint` (via docker), `markdownlint`, `gitleaks`, and the standard
`pre-commit-hooks` set — run `.venv/bin/pre-commit run --all-files` locally before pushing to
catch what CI will catch.

## Architecture

### Layers and how they reach the host

| Layer | Source | Symlink target | Effect |
|---|---|---|---|
| `rules/` | per-file | `~/.claude/rules/` | Always-loaded or path-scoped Claude behavior rules |
| `skills/` | per-dir | `~/.claude/skills/` | On-demand `/skill-name` invocations |
| `agents/` | per-file | `~/.claude/agents/` | Subagent worker role definitions |
| `hooks/` | per-file | `~/.claude/hooks/` | Lifecycle scripts (PreToolUse, PostToolUse, SessionStart, …) |
| `output-styles/` | per-file | `~/.claude/output-styles/` | Voice/format presets |
| `bin/` | per-file | `~/bin/` (on PATH) | User-facing CLI commands, accessible from any repo |
| `lib/` | per-dir | `~/lib/` | Internal libraries imported by `bin/` scripts, not on PATH |
| `gitignore_global` | single file | `~/.gitignore_global` | Git ignore patterns applied to every repo via `core.excludesFile` |

**Critical property:** Directly-executed `bin/` scripts use `readlink -f "$0"` to resolve their real path through symlinks and locate sibling files in `bin/` and `lib/`. Sourced helpers (like `ckExec`) use `readlink -f "${BASH_SOURCE[0]}"` instead — `$0` in a sourced script is the calling script's name, not the helper's. Python scripts use `os.path.abspath(__file__)` which stays at the symlink path — so `../lib/ck-profile/` resolves to `~/lib/ck-profile/` as intended.

### Rules (`rules/`)

Always-loaded: `writing-style.md`, `coding-standards.md`, `code-review.md`, `git.md`. Path-scoped (loaded only when touching matching files): `cpp-idioms.md`, `gpu-kernels.md`, `naming.md`, `security.md`, `error-handling.md`, `performance.md`, `testing.md`, `documentation.md`, `observability.md`.

### Skills (`skills/`)

Each skill is a directory with a `SKILL.md` (YAML frontmatter: `name`, `description`, optional `argument-hint`). Key own skills:

- `council` — adversarial Claude + GPT-5.5 debate, up to 3 rounds, converges by argument quality.
- `dev-team` — 8-phase candidate workflow: lead spawns native worker agents (researcher, implementer, reviewer, tester, builder, profiler) as teammates; runs 2–3 candidate implementations in parallel git worktrees; picks winner on profiling evidence.
- `ck-profile` — six profiling modes for Composable Kernel targets (static, dynamic, trace, cfg, depgraph, compute). Backed by `bin/ck*Profile` binaries.
- `multi-review` — up to 8 parallel reviewers (Claude subagents + GPT-5.5 codex calls per lens); consolidator; dedup against existing PR reviews.
- `research` — four modes (socratic, direct, deep, adversarial) with anti-sycophancy safeguards.
- `llm` — external LLM gateway wrapper.
- `create-pr` — creates a pull request following the CK team's PR template.
- `survey` — academic literature survey, discover/curated modes.

Third-party skills from `third-party/mattpocock-skills/` are linked alongside own skills. Plugins (`superpowers`, `example-skills`, `caveman`, `ponytail`, `claude-api`) are installed via the Claude CLI by `setup.sh`.

[`playwright-cli`](https://github.com/microsoft/playwright-cli) (browser automation) and [`graphify`](https://github.com/Graphify-Labs/graphify) (codebase knowledge-graph generation) are externally-managed skills: `setup.sh` installs them globally (npm, pipx) and runs their own installers rather than sourcing them from `skills/`.

`caveman` and `ponytail` are always-on plugins activated every session via their own hooks. `setup.sh` prunes the mattpocock `caveman` link to avoid conflict.

### Agents (`agents/`)

Worker roles: researcher, implementer, reviewer, tester, builder, profiler. Usable as one-shot delegated subagents (isolated context, returns result to caller) or as teammates in a `dev-team` session. They never spawn other agents.

### Hooks (`hooks/`)

- `block-dangerous.sh` (PreToolUse) — blocks `rm -rf`, force-push, `DROP TABLE`, writes to `.env`/`/etc`/`/tmp`. Scratch goes in `tmp/` (repo root, gitignored).
- `commit-lint.sh` (PreToolUse) — enforces conventional commits (`type(scope): subject`, lowercase, ≤72 chars, no trailing period).
- `auto-approve.sh` (PreToolUse) — auto-approves a configured allowlist of low-risk tool calls.
- `anti-sycophancy.sh` (PreToolUse/UserPromptSubmit) — nudges against reflexive agreement.
- `auto-format.sh` (PostToolUse) — runs clang-format, ruff, jq, shfmt after Write/Edit.
- `security-scan.sh` (PostToolUse) — detects hardcoded secrets after Write/Edit.
- `session-start.sh` (SessionStart) — injects git branch/status/recent commits; restores saved state after compaction.
- `session-end.sh` (SessionEnd) — end-of-session cleanup/summary.
- `context-save.sh` (PreCompact) — saves git state to `.claude/.dotharness/session-state.md`.
- `notify-stop.sh` / `notify-prompt.sh` (Stop/Notification) — desktop/system notifications on stop or when input is needed.
- `teams-notify.sh` — posts a Microsoft Teams adaptive card (`teams-adaptive-card.json`) via an incoming webhook; see `hooks/README.md` for setup.

### Codex integration

`setup.sh` treats Codex as a second target when the `codex` CLI is on `PATH`, reusing the same source files as Claude rather than a separate config:

- **Skills** — `link_skills_to` (the same function used for Claude) also symlinks `skills/` + third-party engineering/productivity skills into `~/.agents/skills/`.
- **Rules → `AGENTS.md`** — Codex has no per-file rules directory, so `rules/*.md` are concatenated (in filename order, `README.md` excluded) into a generated `~/.agents/AGENTS.md`, rewritten only when the content changes.
- **Hooks** — the same `hooks/*.sh` scripts are registered in `~/.codex/config.toml` under Codex's `[[hooks.<event>]]` TOML format (`register_codex_hook`), since the JSON-stdin schema is compatible with Claude Code's.
- **Statusline** — sets `[tui] status_line` in `config.toml` to a fixed enum list (Codex has no shell-backed custom statusline).
- **Plugins / graphify** — registers the `caveman`/`ponytail`/`anthropic-agent-skills` marketplaces via `codex plugin marketplace add`, and runs `graphify install --platform codex` separately from the Claude-side `graphify install`.

### Binaries (`bin/`)

All files symlinked into `~/bin/` and available on PATH from any repo.

**CK build/run:** `ckBuild`, `ckRun`, `ckHold`, `ckRemote`, `ckCommon`, `ckExec`, `dockerRun`. Always invoke via `ckRemote` from a local dev machine (no local GPU/Docker). `ckRemote pull` rsyncs `ck_profile_out/` back locally after profiling.

**CK profiling:** `ckStaticProfile`, `ckRunProfile`, `ckTraceProfile`, `ckCfgProfile`, `ckComputeProfile`. Same CLI style as `ckBuild`/`ckRun`: `REPO` auto-detected from git, `--arch gfx942`, positional binary/target. `ckExec` (sourced internally) auto-detects `srun`/`docker` backend and sets `LIB_DIR` pointing at `lib/ck-profile/`.

**CK post-processing:** `ckAggregate` (aggregate rocprofv3 raw output into summary), `ckDepgraph` (kernel dependency graphs as Graphviz DOT). Run locally after `ckRemote pull`.

**Other:** `llm` / `llm.py` — LLM gateway. Requires `ANTHROPIC_BASE_URL`, `LLM_GATEWAY_KEY`, `LLM_GATEWAY_KEY_HEADER`.

### Libraries (`lib/`)

Symlinked into `~/lib/` by `setup.sh`. Not on PATH — imported programmatically.

`lib/ck-profile/` → `~/lib/ck-profile/`: internal Python libs for the profiling binaries: `gpu_specs.py`, `html_report.py`, `ck_profile_utils.py` (shared `classify`/`msd`/`short`), `parse_resource_usage.py`, `compute_report.py`, `trace_timeline.py`, `cfg_to_dot.py`, plus `counters.txt`, `git_exclude_outdir.sh`, `profile_readme.md`.

`lib/ck-profile-mcp/` → `~/lib/ck-profile-mcp/`: the ck-profile MCP server (`server.py`, `job_store.py`, `validation.py`), exposing `run_profile`/`get_job_status`/`get_summary` as agent-callable tools over `ckRemote`. Registered at user scope by `setup.sh` via `claude mcp add -s user ck-profile ...`; see `skills/ck-profile/REFERENCE.md`'s "MCP server" section for the tool surface.

### Tests (`tests/`)

`tests/bats/` — shell tests for hooks and scripts (enforced by CI): `block-dangerous.bats`, `ckCommon.bats`, `commit-lint.bats`, `multi-review.bats`, `skills-frontmatter.bats`, `setup-codex-skills.bats`, `setup-playwright-graphify.bats`. `tests/python/` — pytest for ck-profile Python helpers (`test_gpu_specs.py`, `test_parse_resource_usage.py`, `test_ck_profile_utils.py`, `test_compute_report.py`, `test_html_report.py`, `test_ckaggregate.py`) and the ck-profile MCP server (`test_ckprofile_mcp_*.py`); `conftest.py` puts `bin/`, `lib/ck-profile/`, and `lib/ck-profile-mcp/` on `sys.path`. Every `SKILL.md` frontmatter `name` must match its directory name — enforced by `skills-frontmatter.bats`.

### Key conventions

- Temporary files go under `tmp/` at the repo root (gitignored, never `/tmp/`); delete after the task.
- Skill temp dirs: `mktemp -d "$_repo_root/tmp/<skill>-XXXXXX"` where `_repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)` (council/research use `|| pwd` fallback; multi-review errors if not in a git repo), cleaned up after delivering results.
- Hook-generated runtime files go under `.claude/.dotharness/` (git root, falling back to cwd).
- The `caveman` plugin suppresses the mattpocock `caveman` skill link; `setup.sh` prunes any pre-existing link.
- Non-trivial work follows a plan-first workflow: templates in `template/` (git-tracked) —
  `plan.md`, `implementation-notes.md`, `test-notes.md`. Real, per-task files go in `plans/` and
  `notes/` (both gitignored, local-only) as `<date>-<slug>.md`. Plan first and get it reviewed,
  then log implementation deviations and test notes as work happens, not retroactively.

## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships. When the user types `/graphify`, use the installed graphify skill or instructions before doing anything else.

Rules:

- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- Dirty graphify-out/ files are expected after hooks or incremental updates; dirty graph files are not a reason to skip graphify. Only skip graphify if the task is about stale or incorrect graph output, or the user explicitly says not to use it.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
