#!/bin/bash
# PreToolUse hook: block dangerous Bash commands and writes to sensitive files.
#
# The Bash command patterns below are best-effort heuristics over a raw command
# string, not a parser. They catch the common shapes (rm -rf, force pushes, DROP
# TABLE) but can be evaded by obfuscation and can false-positive on a literal
# string like `echo "DROP TABLE"`. Treat them as a speed bump, not a sandbox.
set -euo pipefail

input=$(cat || true)
tool=$(jq -r '.tool_name // empty' <<<"$input" 2>/dev/null || true)

deny() {
    # Emit the structured deny (advanced PreToolUse protocol) on stdout, and the
    # same reason on stderr. exit 2 keeps the block fail-closed if a client does
    # not honor the JSON; the stderr line is what that exit-2 path surfaces to
    # Claude, so the reason reaches it on either channel. jq builds the JSON so a
    # reason containing quotes/backslashes cannot corrupt the payload.
    jq -nc --arg reason "Blocked: $1" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: $reason}}'
    echo "Blocked: $1" >&2
    exit 2
}

case "$tool" in
Bash)
    cmd=$(jq -r '.tool_input.command // empty' <<<"$input" 2>/dev/null || true)
    [ -z "$cmd" ] && exit 0

    blocked=""

    # Destructive filesystem operations. Detect recursive AND force flags
    # independently within one command segment ([^|;&]* stops at ; | &), so split
    # forms (-rf, -r -f, --recursive --force) are all caught. Then block only when
    # the target is dangerous: a path, a glob, or home/cwd. A bare relative target
    # (rm -rf build) is left alone.
    if echo "$cmd" | grep -qE '\brm\b[^|;&]*[[:space:]](-[a-zA-Z]*r[a-zA-Z]*|--recursive)\b' &&
        echo "$cmd" | grep -qE '\brm\b[^|;&]*[[:space:]](-[a-zA-Z]*f[a-zA-Z]*|--force)\b'; then
        echo "$cmd" | grep -qE '\brm\b[^|;&]*/' && blocked="rm -rf with path"
        echo "$cmd" | grep -qE '\brm\b[^|;&]*\*' && blocked="rm -rf with glob"
        # shellcheck disable=SC2016  # $HOME is a literal in the regex, not a shell expansion
        echo "$cmd" | grep -qE '\brm\b[^|;&]*[[:space:]](\.|~|\$HOME)([[:space:]]|/|$)' && blocked="rm -rf on home/cwd"
    fi

    # Dangerous git operations (handles `git -C <dir> push -f` and force-with-lease).
    echo "$cmd" | grep -qE '\bgit\b[^|;&]*\bpush\b[^|;&]*(--force|--force-with-lease|-f)\b' && blocked="git push (force)"
    echo "$cmd" | grep -qE '\bgit\b[^|;&]*\breset\b[^|;&]*--hard\b' && blocked="git reset --hard"
    echo "$cmd" | grep -qE '\bgit\b[^|;&]*\bclean\b[^|;&]*-[a-zA-Z]*f' && blocked="git clean -f"

    # Database destruction (best-effort; matches inside strings too).
    echo "$cmd" | grep -qiE '\bDROP\s+(TABLE|DATABASE)\b' && blocked="DROP TABLE/DATABASE"
    echo "$cmd" | grep -qiE '\bTRUNCATE\b' && blocked="TRUNCATE"

    # Sensitive file writes (shell redirection)
    echo "$cmd" | grep -qE '>\s*\.env\b' && blocked="writing to .env"
    echo "$cmd" | grep -qE '>\s*/etc/' && blocked="writing to /etc/"

    # Scratch files belong in the repo's .claude/tmp, never system temp (/tmp,
    # /var/tmp). Match only an absolute system-temp path at a token boundary so a
    # repo path like .../.claude/tmp/ or .../proj/tmp/ is not caught.
    echo "$cmd" | grep -qE '(>>?|&>)[[:space:]]*/(var/)?tmp/' && blocked="writing to /tmp (use the repo .claude/tmp)"
    echo "$cmd" | grep -qE '\b(tee|touch|cp|mv|install|mkdir)\b[^|;&]*[[:space:]]/(var/)?tmp/' && blocked="creating files in /tmp (use the repo .claude/tmp)"

    # Kill all
    echo "$cmd" | grep -qE '\bkillall\b|\bkill\s+-9\s+-1\b' && blocked="killall / kill -9 -1"

    [ -n "$blocked" ] && deny "dangerous command: $blocked"
    ;;

Write | Edit)
    file=$(jq -r '.tool_input.file_path // empty' <<<"$input" 2>/dev/null || true)
    [ -z "$file" ] && exit 0
    base=$(basename "$file")

    # Sensitive locations
    case "$file" in
    /tmp/* | /var/tmp/*) deny "write to system temp ($file); use the repo's .claude/tmp instead" ;;
    /etc/*) deny "write to /etc/ ($file)" ;;
    */.ssh/*) deny "write inside .ssh ($file)" ;;
    */.aws/credentials) deny "write to AWS credentials ($file)" ;;
    esac

    # Sensitive filenames (allow example/sample/template env files)
    case "$base" in
    .env.example | .env.sample | .env.template | .env.dist) : ;;
    .env | .env.*) deny "write to env file ($base)" ;;
    id_rsa | id_dsa | id_ecdsa | id_ed25519) deny "write to private SSH key ($base)" ;;
    credentials) deny "write to credentials file ($file)" ;;
    esac
    ;;

*)
    exit 0
    ;;
esac

# Nothing matched: allow the tool call to proceed.
exit 0
