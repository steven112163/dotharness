# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Purpose

dotharness is a **host-level configuration hub**: `setup.sh` symlinks everything into `~/.claude/`, `~/bin/`, and `~/lib/` so all skills, rules, hooks, agents, and CK tooling are available in **every repo on this machine** — not just this one. Changes here take effect immediately across all projects without reinstalling.

## Setup

```bash
git submodule update --init
./setup.sh
```

`setup.sh` symlinks `skills/`, `agents/`, `hooks/`, `rules/`, `output-styles/`, third-party skills, and `statusline.sh` into `~/.claude/`; symlinks `bin/` scripts into `~/bin/`; symlinks `lib/` subdirs into `~/lib/`; registers lifecycle hooks in `~/.claude/settings.json`; installs Claude plugins; and provisions a repo-local `.venv` with `pre-commit` and `anthropic`. Re-running is idempotent. Requires `jq`.

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

Third-party skills from `third-party/mattpocock-skills/` are linked alongside own skills. Plugins (`superpowers`, `example-skills`, `caveman`, `ponytail`) are installed via the Claude CLI by `setup.sh`.

`caveman` and `ponytail` are always-on plugins activated every session via their own hooks. `setup.sh` prunes the mattpocock `caveman` link to avoid conflict.

### Agents (`agents/`)

Worker roles: researcher, implementer, reviewer, tester, builder, profiler. Usable as one-shot delegated subagents (isolated context, returns result to caller) or as teammates in a `dev-team` session. They never spawn other agents.

### Hooks (`hooks/`)

Critical hooks:

- `block-dangerous.sh` (PreToolUse) — blocks `rm -rf`, force-push, `DROP TABLE`, writes to `.env`/`/etc`/`/tmp`. Scratch goes in `tmp/` (repo root, gitignored).
- `commit-lint.sh` (PreToolUse) — enforces conventional commits (`type(scope): subject`, lowercase, ≤72 chars, no trailing period).
- `auto-format.sh` (PostToolUse) — runs clang-format, ruff, jq, shfmt after Write/Edit.
- `security-scan.sh` (PostToolUse) — detects hardcoded secrets after Write/Edit.
- `session-start.sh` (SessionStart) — injects git branch/status/recent commits; restores saved state after compaction.
- `context-save.sh` (PreCompact) — saves git state to `.claude/.dotharness/session-state.md`.

### Binaries (`bin/`)

All files symlinked into `~/bin/` and available on PATH from any repo.

**CK build/run:** `ckBuild`, `ckRun`, `ckHold`, `ckRemote`, `ckCommon`, `ckExec`, `dockerRun`. Always invoke via `ckRemote` from a local dev machine (no local GPU/Docker). `ckRemote pull` rsyncs `ck_profile_out/` back locally after profiling.

**CK profiling:** `ckStaticProfile`, `ckRunProfile`, `ckTraceProfile`, `ckCfgProfile`, `ckComputeProfile`. Same CLI style as `ckBuild`/`ckRun`: `REPO` auto-detected from git, `--arch gfx942`, positional binary/target. `ckExec` (sourced internally) auto-detects `srun`/`docker` backend and sets `LIB_DIR` pointing at `lib/ck-profile/`.

**CK post-processing:** `ckAggregate` (aggregate rocprofv3 raw output into summary), `ckDepgraph` (kernel dependency graphs as Graphviz DOT). Run locally after `ckRemote pull`.

**Other:** `llm` / `llm.py` — LLM gateway. Requires `ANTHROPIC_BASE_URL`, `LLM_GATEWAY_KEY`, `LLM_GATEWAY_KEY_HEADER`.

### Libraries (`lib/`)

Symlinked into `~/lib/` by `setup.sh`. Not on PATH — imported programmatically.

`lib/ck-profile/` → `~/lib/ck-profile/`: internal Python libs for the profiling binaries: `gpu_specs.py`, `html_report.py`, `ck_profile_utils.py` (shared `classify`/`msd`/`short`), `parse_resource_usage.py`, `compute_report.py`, `trace_timeline.py`, `cfg_to_dot.py`, plus `counters.txt`, `git_exclude_outdir.sh`, `profile_readme.md`.

### Tests (`tests/`)

`tests/bats/` — shell tests for hooks and scripts (enforced by CI). `tests/python/` — pytest for ck-profile Python helpers; `conftest.py` puts both `bin/` and `lib/ck-profile/` on `sys.path`. Every `SKILL.md` frontmatter `name` must match its directory name — enforced by `skills-frontmatter.bats`.

### Key conventions

- Temporary files go under `tmp/` at the repo root (gitignored, never `/tmp/`); delete after the task.
- Skill temp dirs: `mktemp -d "$_repo_root/tmp/<skill>-XXXXXX"` where `_repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)` (council/research use `|| pwd` fallback; multi-review errors if not in a git repo), cleaned up after delivering results.
- Hook-generated runtime files go under `.claude/.dotharness/` (git root, falling back to cwd).
- The `caveman` plugin suppresses the mattpocock `caveman` skill link; `setup.sh` prunes any pre-existing link.
