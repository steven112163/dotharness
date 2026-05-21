# dotharness

Personal monorepo for Claude Code skills, rules, and configuration.

## Structure

```
skills/          → symlinked to ~/.claude/commands/
rules/           → symlinked to ~/.claude/rules/
statusline.sh    → symlinked to ~/.claude/statusline.sh
setup.sh         → creates the symlinks above
```

## Setup

```bash
./setup.sh
```

Symlinks `skills/`, `rules/`, and `statusline.sh` into `~/.claude/`. Existing files are backed up to `.bak`.

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

## Statusline

Compact single-line status showing: directory, git branch, time, model, session name, context usage, effort level, output style, and thinking indicator.