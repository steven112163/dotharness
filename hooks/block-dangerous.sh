#!/bin/bash
# PreToolUse hook: block dangerous bash commands before execution.

input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name // empty')

if [ "$tool" != "Bash" ]; then
    exit 0
fi

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
if [ -z "$cmd" ]; then
    exit 0
fi

blocked=""

# Destructive filesystem operations
echo "$cmd" | grep -qE '\brm\s+(-[a-zA-Z]*r[a-zA-Z]*f|--force|-[a-zA-Z]*f[a-zA-Z]*r)\b.*/' && blocked="rm -rf with path"
echo "$cmd" | grep -qE '\brm\s+(-[a-zA-Z]*r[a-zA-Z]*f|--force)\s+(\.|/|~|\$HOME)\b' && blocked="rm -rf on root/home/cwd"

# Dangerous git operations
echo "$cmd" | grep -qE '\bgit\s+push\s+.*--force\b' && blocked="git push --force"
echo "$cmd" | grep -qE '\bgit\s+push\s+.*-f\b' && blocked="git push -f"
echo "$cmd" | grep -qE '\bgit\s+reset\s+--hard\b' && blocked="git reset --hard"
echo "$cmd" | grep -qE '\bgit\s+clean\s+.*-f' && blocked="git clean -f"

# Database destruction
echo "$cmd" | grep -qiE '\bDROP\s+(TABLE|DATABASE)\b' && blocked="DROP TABLE/DATABASE"
echo "$cmd" | grep -qiE '\bTRUNCATE\b' && blocked="TRUNCATE"

# Sensitive file writes
echo "$cmd" | grep -qE '>\s*\.env\b' && blocked="writing to .env"
echo "$cmd" | grep -qE '>\s*/etc/' && blocked="writing to /etc/"

# Kill all
echo "$cmd" | grep -qE '\bkillall\b|\bkill\s+-9\s+-1\b' && blocked="killall / kill -9 -1"

if [ -n "$blocked" ]; then
    cat <<ENDJSON
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Blocked dangerous command: $blocked"}}
ENDJSON
    exit 2
fi
