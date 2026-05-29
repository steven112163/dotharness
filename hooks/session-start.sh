#!/bin/bash
# SessionStart hook: inject working context at session start/resume/clear, and
# re-inject saved state after compaction (source=compact). This consolidates the
# former PostCompact context-restore hook. The PreCompact context-save hook still
# writes the state file that the compact branch reads.
# stdout (via additionalContext) is added to Claude's context.

input=$(cat 2>/dev/null)
source=$(echo "$input" | jq -r '.source // "startup"' 2>/dev/null)

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
state_file="$root/.claude/.dotharness/session-state.md"

emit() {
    local json
    json=$(printf '%s' "$1" | jq -Rs .)
    cat <<ENDJSON
{"hookSpecificOutput": {"hookEventName": "SessionStart", "additionalContext": $json}}
ENDJSON
}

# Compaction: re-inject the state captured by the PreCompact hook, if present.
if [ "$source" = "compact" ]; then
    [ -f "$state_file" ] && emit "$(cat "$state_file")"
    exit 0
fi

# startup | resume | clear: inject fresh git context.
git rev-parse --is-inside-work-tree >/dev/null 2>&1 || exit 0

if [ -n "${CLAUDE_ENV_FILE:-}" ] && [ -n "$root" ]; then
    echo "PROJECT_ROOT=$root" >> "$CLAUDE_ENV_FILE"
fi

ctx=$(
    echo "## Session context (auto-loaded at ${source})"
    echo "**Branch:** $(git branch --show-current 2>/dev/null || echo detached)"
    changed=$(git status --short 2>/dev/null | head -20)
    if [ -n "$changed" ]; then
        echo "**Uncommitted changes:**"
        echo '```'
        echo "$changed"
        echo '```'
    else
        echo "**Working tree:** clean"
    fi
    echo "**Recent commits:**"
    echo '```'
    git log --oneline -5 2>/dev/null
    echo '```'
)
emit "$ctx"
