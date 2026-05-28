# dotharness

Personal monorepo for Claude Code skills, rules, and configuration.

## Structure

```
skills/                          → own skills, symlinked to ~/.claude/skills/
  dev-team/                      → hierarchical agent team orchestration
    SKILL.md                     → 6-phase workflow (startup → impl loop → test → verify → report → post-mortem)
    roles/                       → per-agent role prompts (8 files)
  research/                      → multi-mode research with anti-sycophancy safeguards
    SKILL.md                     → 4 modes (socratic, direct, deep, adversarial)
hooks/                           → hook scripts, symlinked to ~/.claude/hooks/
rules/                           → symlinked to ~/.claude/rules/
third-party/
  mattpocock-skills/             → git submodule (engineering + productivity skills)
statusline.sh                    → symlinked to ~/.claude/statusline.sh
setup.sh                         → creates symlinks, registers hooks, installs plugins
```

## Setup

```bash
git submodule update --init
./setup.sh
```

Symlinks `skills/`, `hooks/`, `rules/`, third-party skills, and `statusline.sh` into `~/.claude/`. Registers hooks in `~/.claude/settings.json` (requires `jq`). Installs plugins via the Claude CLI. Existing files are backed up to `.bak`.

## Rules

User-level rules loaded automatically by Claude Code. Tailored for C++ / HIP / GPU kernel development.

**Always loaded:**
- `writing-style.md` — prose clarity and LLM anti-patterns
- `coding-standards.md` — size limits, naming, architecture, error handling
- `code-review.md` — review checklist, approval criteria, author/reviewer guidelines
- `git.md` — conventional commits format

**Path-scoped** (loaded only when touching matching files):
- `naming.md` — C++, Python, CMake naming conventions
- `security.md` — memory safety, input validation, secrets
- `error-handling.md` — fail-fast principles, RAII, HIP error checking
- `performance.md` — algorithmic, memory, GPU/HIP optimization
- `testing.md` — test design, organization, anti-patterns
- `observability.md` — logging, metrics, CI observability

## Skills

### Own skills
Located in `skills/`, symlinked individually to `~/.claude/skills/`.
- **dev-team** — hierarchical agent team (lead, implementer, professor + 3 PHDs, staff engineer + 3 seniors, builder, QA head + N testers). 6-phase workflow with verification gate, weighted code review, context checkpoints, and optional post-mortem.
- **research** — four-mode research skill (socratic, direct, deep, adversarial) with anti-sycophancy safeguards. Usable by both humans and agents. Integrated into dev-team role prompts.

### Third-party (mattpocock/skills, MIT)
Engineering and productivity skills, linked from the submodule:
- **diagnose** — disciplined diagnosis loop for hard bugs
- **grill-with-docs** — grilling session with domain model and ADR updates
- **grill-me** — relentless interview about a plan or design
- **tdd** — red-green-refactor loop
- **to-prd** — synthesize conversation into a PRD
- **to-issues** — break a plan into independent GitHub issues
- **triage** — issue triage through role-based state machine
- **improve-codebase-architecture** — find deepening opportunities in a codebase
- **zoom-out** — higher-level perspective on unfamiliar code
- **prototype** — build throwaway prototypes to flesh out a design
- **caveman** — ultra-compressed communication, ~75% token reduction
- **handoff** — compact conversation into a handoff doc
- **write-a-skill** — create new skills with proper structure

### Plugins
- **superpowers** — installed via `claude-plugins-official` marketplace

## Hooks

Lifecycle hooks registered in `~/.claude/settings.json` by `setup.sh`. Scripts live in `hooks/`, symlinked to `~/.claude/hooks/`.

| Hook | Event | Trigger | Purpose |
|------|-------|---------|---------|
| `anti-sycophancy.sh` | UserPromptSubmit | Every prompt | Detects confirmatory language ("right?", "looks good"), injects critical-thinking reminder |
| `block-dangerous.sh` | PreToolUse | Bash commands | Blocks `rm -rf`, `git push --force`, `DROP TABLE`, `.env` writes, `killall` |
| `commit-lint.sh` | PreToolUse | Bash commands | Validates commit messages against conventional commits format, rejects non-conforming messages |
| `auto-approve.sh` | PreToolUse | Bash commands | Auto-approves known-safe read-only commands (linters, checkers, `ctest`) |
| `auto-format.sh` | PostToolUse | Write/Edit | Runs clang-format (.cpp/.hip/.cu), ruff/black (.py), jq (.json), shfmt (.sh) |
| `security-scan.sh` | PostToolUse | Write/Edit | Detects hardcoded AWS keys, API secrets, private keys, passwords, GitHub/GitLab tokens |
| `context-save.sh` | PreCompact | Compaction | Saves git state and working context to `~/.claude/.session-state.md` |
| `context-restore.sh` | PostCompact | Compaction | Re-injects saved session state as additional context after compaction |
| `notify-stop.sh` | Stop | Session stop | Desktop notification via `notify-send` (main session only, not sub-agents) |
| `notify-prompt.sh` | Notification | Notifications | Desktop notification when Claude sends a notification |

## Statusline

Compact single-line status showing: directory, git branch, time, model, session name, context usage, effort level, output style, and thinking indicator.