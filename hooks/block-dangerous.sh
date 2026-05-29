#!/bin/bash
# PreToolUse hook: block dangerous Bash commands and writes to sensitive files.

input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name // empty')

deny() {
    cat <<ENDJSON
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Blocked: $1"}}
ENDJSON
    exit 2
}

case "$tool" in
Bash)
    cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
    [ -z "$cmd" ] && exit 0

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

    # Sensitive file writes (shell redirection)
    echo "$cmd" | grep -qE '>\s*\.env\b' && blocked="writing to .env"
    echo "$cmd" | grep -qE '>\s*/etc/' && blocked="writing to /etc/"

    # Kill all
    echo "$cmd" | grep -qE '\bkillall\b|\bkill\s+-9\s+-1\b' && blocked="killall / kill -9 -1"

    [ -n "$blocked" ] && deny "dangerous command: $blocked"
    ;;

Write|Edit)
    file=$(echo "$input" | jq -r '.tool_input.file_path // empty')
    [ -z "$file" ] && exit 0
    base=$(basename "$file")

    # Sensitive locations
    case "$file" in
        /etc/*)               deny "write to /etc/ ($file)" ;;
        */.ssh/*)             deny "write inside .ssh ($file)" ;;
        */.aws/credentials)   deny "write to AWS credentials ($file)" ;;
    esac

    # Sensitive filenames (allow example/sample/template env files)
    case "$base" in
        .env.example|.env.sample|.env.template|.env.dist) : ;;
        .env|.env.*)                          deny "write to env file ($base)" ;;
        id_rsa|id_dsa|id_ecdsa|id_ed25519)    deny "write to private SSH key ($base)" ;;
        credentials)                          deny "write to credentials file ($file)" ;;
    esac
    ;;

*)
    exit 0
    ;;
esac

# Nothing matched: allow the tool call to proceed.
exit 0
