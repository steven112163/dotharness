# Output styles

Output styles in `output-styles/`, symlinked to `~/.claude/output-styles/`. An output style modifies the system prompt directly (persistent, not re-injected per turn). `setup.sh` activates `dotharness` unless you have already set `outputStyle`.

- **dotharness** — concise, direct, evidence-driven voice (`keep-coding-instructions: true`, so coding behavior is preserved). Switch via `/config` → Output style (the `/output-style` command has been removed).
