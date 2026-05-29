#!/bin/bash
# PreCompact hook: capture session state before compaction.
# Saves git state and working context so PostCompact can restore it.
# Stored repo-locally (not $HOME) since the captured state is repo-specific.

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
state_dir="$root/.claude/.dotharness"
mkdir -p "$state_dir" 2>/dev/null
state_file="$state_dir/session-state.md"

{
    echo "# Session state (pre-compaction)"
    echo "**Saved:** $(date -Iseconds)"
    echo "**Directory:** $(pwd)"
    echo ""
    echo "## Git state"
    branch=$(git branch --show-current 2>/dev/null || echo "N/A")
    echo "**Branch:** $branch"
    echo '```'
    git status --short 2>/dev/null || echo "Not a git repo"
    echo '```'
    echo ""
    echo "## Uncommitted diff summary"
    echo '```'
    git diff --stat 2>/dev/null
    git diff --cached --stat 2>/dev/null
    echo '```'
    echo ""
    echo "## Recent commits (last 5)"
    echo '```'
    git log --oneline -5 2>/dev/null || echo "No commits"
    echo '```'
} > "$state_file" 2>/dev/null

cat <<ENDJSON
{"systemMessage": "Session state saved to $state_file before compaction."}
ENDJSON
