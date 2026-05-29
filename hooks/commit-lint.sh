#!/bin/bash
# PreToolUse hook: validate commit message format.
# Enforces conventional commits: <type>(<scope>): <subject>
# Blocks non-conforming git commit commands with exit 2.

input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name // empty')

if [ "$tool" != "Bash" ]; then
    exit 0
fi

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')

# Only intercept git commit commands
echo "$cmd" | grep -qE '\bgit\s+commit\b' || exit 0

# Skip amend without a new message (reuses previous message)
if echo "$cmd" | grep -qE '\b--amend\b' && ! echo "$cmd" | grep -qE '\s-m\s'; then
    exit 0
fi

# Skip --allow-empty-message
echo "$cmd" | grep -qE '\b--allow-empty-message\b' && exit 0

# Extract subject line from the message source.
# Handles: -F/--file <file>, HEREDOC, -m "msg", and -m 'msg'.
subject=""

# Try -F <file> / --file <file> / --file=<file>: read the message file.
msg_file=$(echo "$cmd" | grep -oP '(?<=\s-F\s)(\S+)' | head -1)
[ -z "$msg_file" ] && msg_file=$(echo "$cmd" | grep -oP '(?<=--file=)(\S+)' | head -1)
[ -z "$msg_file" ] && msg_file=$(echo "$cmd" | grep -oP '(?<=\s--file\s)(\S+)' | head -1)
if [ -n "$msg_file" ]; then
    # Message read from stdin (-F -) cannot be validated before execution.
    [ "$msg_file" = "-" ] && exit 0
    msg_file=${msg_file%\"}; msg_file=${msg_file#\"}
    msg_file=${msg_file%\'}; msg_file=${msg_file#\'}
    # First line that is neither blank nor a git comment.
    [ -f "$msg_file" ] && subject=$(grep -vE '^[[:space:]]*(#|$)' "$msg_file" | head -1)
fi

# Try HEREDOC before -m so `-m "$(cat <<'EOF' ... EOF)"` reads the real
# subject, not the command-substitution wrapper on the -m line.
if [ -z "$subject" ] && echo "$cmd" | grep -qE '<<.*EOF'; then
    subject=$(echo "$cmd" | sed -n "/<<.*EOF/,/EOF/p" | grep -vE '(EOF|<<)' | grep -v '^\s*$' | head -1)
fi

# Try -m "..." (double-quoted)
if [ -z "$subject" ]; then
    subject=$(echo "$cmd" | grep -oP '(?<=-m\s")([^"]*)' | head -1)
fi

# Try -m '...' (single-quoted)
if [ -z "$subject" ]; then
    subject=$(echo "$cmd" | grep -oP "(?<=-m\\s')([^']*)" | head -1)
fi

# No message found — nothing to validate
if [ -z "$subject" ]; then
    exit 0
fi

# Take only the first line (subject) and trim whitespace
subject=$(echo "$subject" | head -1 | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')

# Empty after trimming
if [ -z "$subject" ]; then
    exit 0
fi

# --- Validation ---

valid_types="feat|fix|docs|style|refactor|perf|test|example|chore"
pattern="^(${valid_types})(\(.+\))?: [a-z].*"

error=""

if ! echo "$subject" | grep -qE "^(${valid_types})(\(.+\))?: "; then
    error="Expected format: <type>(<scope>): <subject> where type is one of: feat, fix, docs, style, refactor, perf, test, example, chore."
elif ! echo "$subject" | grep -qE "$pattern"; then
    error="Subject must start lowercase after the colon-space separator."
fi

# Check trailing period
if [ -z "$error" ] && echo "$subject" | grep -qE '\.\s*$'; then
    error="Subject must not end with a period."
fi

# Check length (72 char limit)
if [ -z "$error" ] && [ ${#subject} -gt 72 ]; then
    error="Subject line is ${#subject} characters (max 72)."
fi

if [ -n "$error" ]; then
    cat <<ENDJSON
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "deny", "permissionDecisionReason": "Commit message rejected. ${error} Got: '${subject}'"}}
ENDJSON
    exit 2
fi
