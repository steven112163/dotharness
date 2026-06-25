# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Setup

```bash
git submodule update --init
./setup.sh
```

`setup.sh` symlinks `skills/`, `agents/`, `hooks/`, `rules/`, `output-styles/`, third-party skills, and `statusline.sh` into `~/.claude/`; symlinks `bin/` scripts into `~/bin/`; registers lifecycle hooks in `~/.claude/settings.json`; installs Claude plugins; and provisions a repo-local `.venv` with `pre-commit` and `anthropic`. Re-running is idempotent. Requires `jq` for settings mutation.

## Commands

```bash
# Lint and format (all hooks)
.venv/bin/pre-commit run --all-files

# Shell tests
bats tests/bats/

# Python tests
pytest

# Run a single bats file
bats tests/bats/commit-lint.bats

# Query an external LLM (gateway required)
bin/llm -m gpt-5.5 --thinking "your question"
bin/llm --help
```

## Architecture

### Layers

**`rules/`** — always-loaded rule files that govern Claude's behavior in every session (coding standards, git conventions, code-review checklist, naming, writing style, etc.). Symlinked per-file into `~/.claude/rules/`; the folder's `README.md` is deliberately skipped so it does not become an active rule.

**`skills/`** — on-demand skills invoked with `/skill-name`. Each skill is a directory with a `SKILL.md` (YAML frontmatter: `name`, `description`, optional `argument-hint`). Symlinked individually into `~/.claude/skills/`. Key own skills:

- `council` — fans out to GPT-5.5, DeepSeek-V4-Flash, and Gemini in parallel as background Bash calls; Claude forms an independent position first; a synthesizer subagent resolves by argument quality, not vote count.
- `dev-team` — eight-phase candidate workflow: lead spawns native worker agents (researcher, implementer, reviewer, tester, builder, profiler) as teammates; runs 2–3 candidate implementations in parallel git worktrees; picks the winner on profiling evidence.
- `llm` — thin shell + Python wrapper around the Anthropic SDK with a custom `base_url` for routing to external providers. Requires `ANTHROPIC_BASE_URL`, `LLM_GATEWAY_KEY`, `LLM_GATEWAY_KEY_HEADER`.
- `multi-review` — 8 parallel reviewers (4 Claude subagents by lens + 3 background `codex exec` calls for GPT/Gemini + 1 `bin/llm` call for DeepSeek); consolidator subagent; validation subagent; dedup against existing PR reviews.
- `research` — four modes (socratic, direct, deep, adversarial) with anti-sycophancy safeguards. Deep mode fans out per-sub-question to multiple external models.
- `ck-profile` — static (register/LDS analysis from build logs) + dynamic (rocprofv3 runtime) profiling of Composable Kernel targets.

Third-party skills from the `mattpocock-skills` submodule (`third-party/`) are linked alongside own skills. Plugin-provided skills (`superpowers`, `example-skills`, `caveman`, `ponytail`) are installed via the Claude CLI.

**`agents/`** — native subagent definitions. Each file is a worker role (researcher, implementer, reviewer, tester, builder, profiler). Usable as one-shot delegated subagents or as teammates in a `dev-team` session. They never spawn other agents.

**`hooks/`** — lifecycle scripts registered in `~/.claude/settings.json`. Critical behaviors:

- `block-dangerous.sh` (PreToolUse) — blocks `rm -rf`, force-push, `DROP TABLE`, writes to `.env`/`/etc`/`/tmp`. Scratch goes in the repo's `.claude/tmp/`.
- `commit-lint.sh` (PreToolUse) — rejects commit messages that do not conform to conventional commits (`type(scope): subject`, subject starts lowercase, max 72 chars, no trailing period).
- `auto-format.sh` (PostToolUse) — runs clang-format, ruff, jq, shfmt after Write/Edit.
- `security-scan.sh` (PostToolUse) — detects hardcoded secrets after Write/Edit.
- `session-start.sh` (SessionStart) — injects git branch/status/recent commits; restores saved state after compaction.
- `context-save.sh` (PreCompact) — saves git state to `.claude/.dotharness/session-state.md` before compaction so it can be restored.

**`bin/`** — helper scripts symlinked into `~/bin/`:

- `ckBuild` / `ckRun` / `ckHold` — Composable Kernel build/run inside the CK Docker image, with auto-detected backend (`direct` / `docker` / `srun`). Use `scontrol ping` (not `command -v srun`) to detect an active Slurm daemon.
- `ckRemote` — drives build/run on a remote server; walks a priority-ordered list in `~/.config/ckremote`, rsyncs source (excluding `build/` and `.git/`), runs `ck*` over SSH.
- `llm` / `llm.py` — LLM gateway binary. `llm.py` maps `--effort` to per-family API parameters: `budget_tokens` for Claude ≤4.6, `output_config.effort` for Claude ≥4.7, `reasoning_effort` for o-series/gpt-5/DeepSeek, `thinkingBudget` for Gemini.

**`tests/`** — `tests/bats/` for shell hook/script tests; `tests/python/` for the ck-profile Python helpers (gpu_specs, parse_resource_usage, aggregate).

### Key conventions

- Temporary files go under `.claude/tmp/` (never `/tmp/`); delete them after the task.
- Skill temp dirs use `mktemp -d .claude/tmp/<skill>-XXXXXX` and are cleaned up after delivering results.
- Every `SKILL.md` frontmatter `name` must match its directory name (enforced by `skills-frontmatter.bats`).
- `README.md` files inside linked directories are intentionally not symlinked into `~/.claude/` to prevent them from being parsed as active skills/rules.
- The `caveman` plugin (always-on) suppresses the mattpocock `caveman` skill link; `setup.sh` prunes any pre-existing link.
