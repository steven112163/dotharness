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
  ck-profile/                    → static + runtime GPU profiling of a CK target
    SKILL.md                     → static (resource usage) + dynamic (rocprofv3) modes, roofline-lite verdict
    REFERENCE.md                 → counters, CSV layout, roofline thresholds, per-arch device specs
    scripts/                     → run_profile.sh, static_profile.sh, aggregate.py, parse_resource_usage.py, gpu_specs.py, counters.txt
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
- **ck-profile** — profile a Composable Kernel target two ways: static compile-time resource analysis (VGPR/AGPR/SGPR, occupancy ceiling, spills, scratch, LDS) and dynamic runtime profiling with rocprofv3 (kernel timing, HBM traffic, L2 hit ratio, occupancy, VALU). Per-arch hardware specs (`gpu_specs.py`) drive a device-spec block and an occupancy-util ratio, with a roofline-lite compute/memory/latency bottleneck verdict.

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
| `notify-stop.sh` | Stop | End of each turn | Desktop notification via `notify-send` (includes the project dir). No Teams card — `Stop` fires every turn, so a per-turn ping would be noise |
| `notify-prompt.sh` | Notification | Permission / idle / elicitation prompts | Desktop notification plus a Teams card (includes the project dir) when Claude needs attention |
| `teams-notify.sh` | (helper) | Called by `notify-prompt.sh` | POSTs an Adaptive Card to a Teams webhook; no-op until a URL is configured |

Hook-generated runtime files (saved session state, session log) are written repo-locally under `.claude/.dotharness/` (git root, falling back to cwd), never to system-level `~/.claude/`. Add `.claude/.dotharness/` to a project's ignore rules to keep them out of git.

**Teams notifications.** `teams-notify.sh` posts to a Microsoft Teams webhook so attention requests reach you when you are away from the machine. Only the `Notification` hook sends a Teams card (permission and idle prompts), so you get one ping when Claude actually needs you rather than one per turn. The webhook URL is never committed: set `TEAMS_WEBHOOK_URL`, or write it to `~/.claude/.dotharness/teams-webhook`. Without either, the helper is a silent no-op.

The legacy "Incoming Webhook" connector is retired, so the URL comes from a Power Automate Workflow:

1. In Teams, open the **Workflows** app → **Create** tab → **Create from blank**.
2. Add the trigger **"When a Teams webhook request is received"** and set **Who can trigger the flow** to **Anyone** (the helper posts with no auth token, so the URL itself is the secret).
3. Add the action **"Post card in a chat or channel"**: **Post as** = Flow bot, **Post in** = Chat with Flow bot, **Recipient** = yourself (a private DM to just you).
4. In the **Adaptive Card** field, paste the contents of `hooks/teams-adaptive-card.json` — it renders the flat `{title, text}` payload the helper sends.
5. **Save**, reopen the trigger box, and copy the **HTTP POST URL**.
6. Install the URL and send a test card:

```bash
mkdir -p ~/.claude/.dotharness
printf '%s\n' 'PASTE_URL_HERE' > ~/.claude/.dotharness/teams-webhook
chmod 600 ~/.claude/.dotharness/teams-webhook
bash ~/.claude/hooks/teams-notify.sh "Claude Code" "Test from dotharness"
```

The sender always shows as "Workflows" (the Flow bot's fixed name — Microsoft allows no alias); the card's bold title identifies it as Claude.

## Output styles

Output styles in `output-styles/`, symlinked to `~/.claude/output-styles/`. An output style modifies the system prompt directly (persistent, not re-injected per turn). `setup.sh` activates `dotharness` unless you have already set `outputStyle`.

- **dotharness** — concise, direct, evidence-driven voice (`keep-coding-instructions: true`, so coding behavior is preserved). Switch with `/output-style`.

## Binaries

Helper scripts in `bin/`, symlinked individually into `~/bin/` (already on `PATH`).

- **dockerRun** — create a named dev container from an image, or print the attach command if it already exists. Used by the `ck-profile` skill to spin up its profiling container.

## Statusline

Compact single-line status showing: directory, git branch, time, model, session name, context usage, effort level, output style, and thinking indicator.