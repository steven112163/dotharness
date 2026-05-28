#!/bin/bash
# PreToolUse hook: auto-approve known-safe read-only commands.
# Runs before the permission prompt; emits permissionDecision=allow to skip it.

input=$(cat)
tool=$(echo "$input" | jq -r '.tool_name // empty')

if [ "$tool" != "Bash" ]; then
    exit 0
fi

cmd=$(echo "$input" | jq -r '.tool_input.command // empty')
if [ -z "$cmd" ]; then
    exit 0
fi

approve() {
    cat <<ENDJSON
{"hookSpecificOutput": {"hookEventName": "PreToolUse", "permissionDecision": "allow", "permissionDecisionReason": "Auto-approved: $1"}}
ENDJSON
    exit 0
}

# Linters and type checkers (read-only)
echo "$cmd" | grep -qE '^(npm|npx|yarn|pnpm|bun|bunx) run (lint|check|typecheck|format:check)\b' && approve "JS/TS lint/check"
echo "$cmd" | grep -qE '^cargo (check|clippy|fmt -- --check|test)\b' && approve "cargo check/test"
echo "$cmd" | grep -qE '^(ruff check|black --check|flake8|mypy|pylint|isort --check)\b' && approve "Python linter"
echo "$cmd" | grep -qE '^clang-format --dry-run\b' && approve "clang-format dry run"
echo "$cmd" | grep -qE '^clang-tidy\b' && approve "clang-tidy"
echo "$cmd" | grep -qE '^ctest\b' && approve "ctest"
echo "$cmd" | grep -qE '^cmake --build .+ --target (check|test)\b' && approve "cmake check/test"
echo "$cmd" | grep -qE '^make (check|lint|test)\b' && approve "make check/lint/test"
echo "$cmd" | grep -qE '^(shellcheck|shfmt -d)\b' && approve "shell linter"
