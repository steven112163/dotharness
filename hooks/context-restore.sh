#!/bin/bash
# PostCompact hook: re-inject saved session state after compaction.

state_file="${HOME}/.claude/.session-state.md"

if [ -f "$state_file" ]; then
    context=$(cat "$state_file")
    context_json=$(printf '%s' "$context" | jq -Rs .)
    cat <<ENDJSON
{"hookSpecificOutput": {"hookEventName": "PostCompact", "additionalContext": $context_json}}
ENDJSON
fi
