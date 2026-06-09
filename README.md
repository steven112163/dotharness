# dotharness

Personal monorepo for Claude Code skills, rules, and configuration.

## Structure

```
skills/                          → own skills, symlinked to ~/.claude/skills/
  dev-team/                      → agent team orchestration (lead spawns native agents as teammates)
    SKILL.md                     → 8-phase candidate workflow (clarify → startup → draft/plan → candidate loop → QA → verify → report → post-mortem)
    roles/                       → coordinator role prompts (principal-researcher, software-architect, test-architect)
  research/                      → multi-mode research with anti-sycophancy safeguards
    SKILL.md                     → 4 modes (socratic, direct, deep, adversarial)
  create-pr/                     → PR creation with CK team template
    SKILL.md                     → 5-step workflow (gather → collect → test → format → push)
  ck-profile/                    → static + runtime GPU profiling of a CK target
    SKILL.md                     → static (resource usage) + dynamic (rocprofv3) modes, roofline-lite verdict
    REFERENCE.md                 → counters, CSV layout, roofline thresholds, per-arch device specs
    scripts/                     → per-mode drivers (run_profile, static_profile, trace_profile, compute_profile, cfg_dump, depgraph) plus reporting/util helpers (aggregate, html_report, gpu_specs, parse_resource_usage, counters.txt, …)
agents/                          → native subagents (worker roles), symlinked to ~/.claude/agents/
  researcher, implementer, reviewer, tester, builder, profiler
hooks/                           → hook scripts, symlinked to ~/.claude/hooks/
output-styles/                   → output styles, symlinked to ~/.claude/output-styles/
bin/                             → helper scripts, symlinked to ~/bin/ (on PATH)
  dockerRun                      → create/attach a named dev container from an image
rules/                           → symlinked to ~/.claude/rules/
third-party/
  mattpocock-skills/             → git submodule (engineering + productivity skills)
statusline.sh                    → symlinked to ~/.claude/statusline.sh
tests/                           → bats tests for hooks (block-dangerous.bats)
.pre-commit-config.yaml          → lint/format/secret gate (shellcheck, shfmt, ruff, typos, actionlint, gitleaks, pre-commit-hooks)
.github/workflows/ci.yml         → CI: pre-commit on all files + bats hook tests + full-history gitleaks
setup.sh                         → symlinks, hooks, output style, plugins, and pre-commit provisioning
```

## Setup

```bash
git submodule update --init
./setup.sh
```

Symlinks `skills/`, `hooks/`, `output-styles/`, `rules/`, third-party skills, and `statusline.sh` into `~/.claude/`, and `bin/` scripts into `~/bin/`. Registers hooks and sets the `dotharness` output style in `~/.claude/settings.json` (requires `jq`), creating that file if it does not yet exist (fresh-machine safe). Installs plugins via the Claude CLI. Provisions a repo-local `.venv` with `pre-commit` and installs the git pre-commit hook. Existing files are backed up to `.bak`. Re-running is idempotent.

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
- **dev-team** — evidence-driven agent team. The lead (the only spawner) spawns native worker agents (researcher, implementer, reviewer, tester, builder, profiler) and synthesis coordinators (principal-researcher, software-architect, test-architect) as teammates, on demand, and stops them once they deliver. 8-phase candidate workflow: clarify a task contract, draft/plan, fan out 2–3 candidate implementations in worktrees, refine on profiling evidence, QA, verify, and report the best candidate plus alternatives.
- **research** — four-mode research skill (socratic, direct, deep, adversarial) with anti-sycophancy safeguards. Usable by both humans and agents. Integrated into dev-team role prompts.
- **create-pr** — create a pull request following the CK team's PR template (motivation, technical details, test plan, test result, submission checklist).
- **ck-profile** — profile a Composable Kernel target two ways: static compile-time resource analysis (VGPR/AGPR/SGPR, occupancy ceiling, spills, scratch, LDS) and dynamic runtime profiling with rocprofv3 (kernel timing, HBM traffic, L2 hit ratio, occupancy, VALU). Per-arch hardware specs (`gpu_specs.py`) drive a device-spec block and an occupancy-util ratio, with a roofline-lite compute/memory/latency bottleneck verdict.

`research` and `ck-profile` carry an `argument-hint` to guide `/`-invocation autocomplete.

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
Installed by `setup.sh` via the Claude CLI. The `claude-plugins-official` marketplace is registered by default; `setup.sh` adds the `anthropic-agent-skills` marketplace (`anthropics/skills`) before installing from it.

- **superpowers** (`claude-plugins-official`) — disciplined workflows (brainstorming, TDD, debugging).
- **example-skills** (`anthropic-agent-skills`) — bundle of 12 Anthropic example skills. Used here for **skill-creator** (author/eval/optimize skills), **frontend-design** and **theme-factory** (styling the ck-profile HTML reports), **webapp-testing** (Playwright — screenshot-verify the reports), and **mcp-builder**. The rest of the bundle stays inert unless its trigger fires.
- **claude-api** (`anthropic-agent-skills`) — Claude API / Anthropic SDK reference for building LLM-powered tooling.

Plugin granularity is per-plugin: `example-skills` is all-or-nothing, so the wanted skills arrive bundled with others. Skills are description-triggered and lazy, so unused ones cost nothing at runtime.

## Agents

Native subagents in `agents/`, symlinked individually to `~/.claude/agents/`. Each is reusable two ways: as a one-shot **delegated subagent** (returns a result to the caller, keeping its work out of the main context) or as an **agent-team teammate** (spawned into a team, where it also gains the coordination tools). They are worker roles — they never spawn other agents.

- **researcher** — web + codebase research; returns a short, source-cited report. Preloads the `research` skill.
- **implementer** — writes or modifies code to a spec in an isolated context.
- **reviewer** — reviews a diff against the code-review checklist; returns severity-prefixed findings.
- **tester** — authors and runs tests; reports pass/fail and benchmark-vs-target.
- **builder** — builds a CK target via `ckBuild`; reports errors and warnings.
- **profiler** — profiles a built target via the `ck-profile` skill; returns ranked optimization directions.

Each definition also carries a task-list `color`: researcher cyan, implementer green, reviewer purple, tester yellow, builder blue, profiler orange.

Each agent also references external skills where useful — for example `implementer` uses `superpowers:test-driven-development`, `superpowers:systematic-debugging`, and `superpowers:verification-before-completion`; `reviewer` uses the built-in `/review` and `/security-review`; `profiler` pairs `ck-profile` with `superpowers:systematic-debugging`.

The `dev-team` skill spawns these as teammates and pairs the research/review/QA workers with coordinators (principal-researcher, software-architect, test-architect) that synthesize their output. Because a subagent definition's `tools`/`model` apply in both modes (its `skills` preload only in delegated-subagent mode), the same six files serve solo delegation and team roles. The lead drives the workflow with orchestration skills — `superpowers:writing-plans`/`executing-plans`, `using-git-worktrees`, `dispatching-parallel-agents`, `requesting-code-review`, `verification-before-completion`, and `finishing-a-development-branch`.

## Hooks

Lifecycle hooks registered in `~/.claude/settings.json` by `setup.sh`. Scripts live in `hooks/`, symlinked to `~/.claude/hooks/`.

| Hook | Event | Trigger | Purpose |
|------|-------|---------|---------|
| `anti-sycophancy.sh` | UserPromptSubmit | Every prompt | Detects confirmatory language ("right?", "looks good"), injects critical-thinking reminder |
| `block-dangerous.sh` | PreToolUse | Bash / Write / Edit | Blocks `rm -rf`, `git push --force`, `DROP TABLE`, `killall`; denies Write/Edit to `.env`, SSH/AWS keys, `/etc/`, and system temp (`/tmp`, `/var/tmp`) — scratch goes in the repo's `.claude/tmp` |
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

## Pre-commit and CI

A `pre-commit` gate runs lint and format checks on every commit, and a GitHub Actions workflow enforces the same set on push and pull request.

**Hooks (`.pre-commit-config.yaml`), framework-managed:**
- `shellcheck` — shell linting (hooks, `bin/`, `statusline.sh`, `setup.sh`, skill scripts)
- `shfmt` — shell formatting at 4-space indent (`-i 4`), matching `auto-format.sh`
- `ruff` + `ruff-format` — Python lint and format for the ck-profile scripts
- `typos` — spell-checking for code and docs; `_typos.toml` allowlists GPU terms (`VALU`, `HSA`) that are not typos
- `actionlint` (docker) — GitHub Actions workflow linting, including the embedded `run:` shell via the image's bundled shellcheck
- `gitleaks` — secret scanning on staged diffs (regex + entropy)
- `pre-commit-hooks` — trailing whitespace, end-of-file, merge-conflict, large-file, JSON/YAML validity, shebang/executable consistency, case-conflict, mixed-line-ending (LF), and `detect-private-key` (excluding `security-scan.sh`, which greps for the key-header marker)

`setup.sh` provisions a repo-local `.venv`, installs `pre-commit` into it, and registers the git hook. Run the gate manually with `.venv/bin/pre-commit run --all-files`. The `actionlint` hook runs in a container, so it needs a running Docker daemon.

**Tests (`tests/`).** `block-dangerous.bats` exercises the `block-dangerous.sh` guard with 34 cases: `rm -rf` (path, glob, home, split flags), force-push variants, `reset --hard`, `git clean`, `DROP TABLE`, `.env`/`/etc`/`/tmp` writes, and `killall`, plus the allow cases (bare relative `rm`, the repo's `.claude/tmp`, ordinary source files, `.env.example`). Run with `bats tests/`.

**CI (`.github/workflows/ci.yml`).** Three jobs on push and pull request: `pre-commit` (all hooks on all files), `bats` (installs `bats`/`jq`, runs the hook tests), and `gitleaks` (full-history secret scan with `fetch-depth: 0`, catching secrets the staged-only pre-commit hook cannot see).

## Output styles

Output styles in `output-styles/`, symlinked to `~/.claude/output-styles/`. An output style modifies the system prompt directly (persistent, not re-injected per turn). `setup.sh` activates `dotharness` unless you have already set `outputStyle`.

- **dotharness** — concise, direct, evidence-driven voice (`keep-coding-instructions: true`, so coding behavior is preserved). Switch via `/config` → Output style (the `/output-style` command has been removed).

## Binaries

Helper scripts in `bin/`, symlinked individually into `~/bin/` (already on `PATH`).

- **dockerRun** — create a named dev container from an image, or print the attach command if it already exists. Used by the `ck-profile` skill to spin up its profiling container.

## Statusline

Compact single-line status showing: directory, git branch, time, model, session name, context usage, effort level, output style, and thinking indicator.
