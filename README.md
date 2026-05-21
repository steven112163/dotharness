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

## Statusline

Compact single-line status showing: directory, git branch, time, model, session name, context usage, effort level, output style, and thinking indicator.