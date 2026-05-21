# dotharness

Personal monorepo for Claude Code skills, rules, and configuration.

## Structure

```
skills/                          → own skills, symlinked to ~/.claude/skills/
rules/                           → symlinked to ~/.claude/rules/
third-party/
  mattpocock-skills/             → git submodule (engineering + productivity skills)
statusline.sh                    → symlinked to ~/.claude/statusline.sh
setup.sh                         → creates symlinks + installs plugins
```

## Setup

```bash
git submodule update --init
./setup.sh
```

Symlinks `skills/`, `rules/`, third-party skills, and `statusline.sh` into `~/.claude/`. Installs plugins via the Claude CLI. Existing files are backed up to `.bak`.

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

## Statusline

Compact single-line status showing: directory, git branch, time, model, session name, context usage, effort level, output style, and thinking indicator.