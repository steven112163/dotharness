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
  create-pr/                     → PR creation with CK team template
    SKILL.md                     → 5-step workflow (gather → collect → test → format → push)
  ck-profile/                    → runtime GPU profiling of a CK target with rocprofv3
    SKILL.md                     → kernel-trace + PMC multipass, roofline-lite verdict
    REFERENCE.md                 → counters, CSV layout, roofline thresholds
    scripts/                     → run_profile.sh, aggregate.py, counters.txt
hooks/                           → hook scripts, symlinked to ~/.claude/hooks/
output-styles/                   → output styles, symlinked to ~/.claude/output-styles/
bin/                             → helper scripts, symlinked to ~/bin/ (on PATH)
  dockerRun                      → create/attach a named dev container from an image
rules/                           → symlinked to ~/.claude/rules/
third-party/
  mattpocock-skills/             → git submodule (engineering + productivity skills)
statusline.sh                    → symlinked to ~/.claude/statusline.sh
setup.sh                         → creates symlinks, registers hooks, sets output style, installs plugins
```

## Setup

```bash
git submodule update --init
./setup.sh
```

Symlinks `skills/`, `hooks/`, `output-styles/`, `rules/`, third-party skills, and `statusline.sh` into `~/.claude/`, and `bin/` scripts into `~/bin/`. Registers hooks and sets the `dotharness` output style in `~/.claude/settings.json` (requires `jq`), creating that file if it does not yet exist (fresh-machine safe). Installs plugins via the Claude CLI. Existing files are backed up to `.bak`. Re-running is idempotent.

## Rules

User-level rules loaded automatically by Claude Code. Tailored for C++ / HIP / GPU kernel development.

**Always loaded:**
- `writing-style.md` — prose clarity and LLM anti-patterns
- `coding-standards.md` — size limits, naming, architecture, error handling
- `code-review.md` — review checklist, approval criteria, author/reviewer guidelines
- `git.md` — conventional commits format

**Path-scoped** (loaded only when touching matching files):
- `naming.md` — C++, Python, CMake naming conventions
- `cpp-idioms.md` — language standard, type usage, include discipline
- `gpu-kernels.md` — annotation discipline, occupancy, LDS, wavefront rules
- `security.md` — memory safety, input validation, secrets
- `error-handling.md` — fail-fast principles, RAII, HIP error checking
- `performance.md` — algorithmic, memory, GPU/HIP optimization
- `testing.md` — test design, organization, anti-patterns
- `documentation.md` — comment policy, project docs, doc anti-patterns
- `observability.md` — logging, metrics, CI observability

## Skills

### Own skills
Located in `skills/`, symlinked individually to `~/.claude/skills/`.
- **dev-team** — hierarchical agent team (lead, implementer, professor + 3 PHDs, staff engineer + 3 seniors, builder, QA head + N testers). 6-phase workflow with verification gate, weighted code review, context checkpoints, and optional post-mortem.
- **research** — four-mode research skill (socratic, direct, deep, adversarial) with anti-sycophancy safeguards. Usable by both humans and agents. Integrated into dev-team role prompts.
- **create-pr** — create a pull request following the CK team's PR template (motivation, technical details, test plan, test result, submission checklist).
- **ck-profile** — runtime GPU profiling of a Composable Kernel target with rocprofv3: kernel timing, HBM traffic, L2 hit ratio, occupancy, and VALU utilization across an argument sweep, with a roofline-lite compute/memory/latency bottleneck verdict.

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
| `block-dangerous.sh` | PreToolUse | Bash / Write / Edit | Blocks `rm -rf`, `git push --force`, `DROP TABLE`, `killall`; denies Write/Edit to `.env`, SSH/AWS keys, `/etc/` |
| `auto-approve.sh` | PreToolUse | Bash commands | Auto-approves known-safe read-only commands (linters, checkers, `ctest`) |
| `commit-lint.sh` | PreToolUse | Bash commands | Validates commit messages against conventional commits format, rejects non-conforming messages |
| `auto-format.sh` | PostToolUse | Write/Edit | Runs clang-format (.cpp/.hip/.cu), ruff/black (.py), jq (.json), shfmt (.sh) |
| `security-scan.sh` | PostToolUse | Write/Edit | Detects hardcoded AWS keys, API secrets, private keys, passwords, GitHub/GitLab tokens |
| `session-start.sh` | SessionStart | Start/resume/clear/compact | Injects git branch, status, recent commits; sets `PROJECT_ROOT`; re-injects saved state after compaction |
| `session-end.sh` | SessionEnd | Session end | Prunes `.claude/.dev-team/` scratch older than 7 days, clears stale state, logs |
| `context-save.sh` | PreCompact | Compaction | Saves git state to `.claude/.dotharness/session-state.md` (restored by `session-start.sh` on the next compact) |
| `notify-stop.sh` | Stop | Session stop | Desktop notification via `notify-send` (main session only) |
| `notify-prompt.sh` | Notification | Notifications | Desktop notification when Claude sends a notification |

Hook-generated runtime files (saved session state, session log) are written repo-locally under `.claude/.dotharness/` (git root, falling back to cwd), never to system-level `~/.claude/`. Add `.claude/.dotharness/` to a project's ignore rules to keep them out of git.

## Output styles

Output styles in `output-styles/`, symlinked to `~/.claude/output-styles/`. An output style modifies the system prompt directly (persistent, not re-injected per turn). `setup.sh` activates `dotharness` unless you have already set `outputStyle`.

- **dotharness** — concise, direct, evidence-driven voice (`keep-coding-instructions: true`, so coding behavior is preserved). Switch with `/output-style`.

## Binaries

Helper scripts in `bin/`, symlinked individually into `~/bin/` (already on `PATH`).

- **dockerRun** — create a named dev container from an image, or print the attach command if it already exists. Used by the `ck-profile` skill to spin up its profiling container.

## Statusline

Compact single-line status showing: directory, git branch, time, model, session name, context usage, effort level, output style, and thinking indicator.