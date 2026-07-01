#!/bin/bash
# PreToolUse hook: auto-approve known-safe read-only commands.
# Runs before the permission prompt; emits permissionDecision=allow to skip it.
set -euo pipefail

input=$(cat || true)
tool=$(echo "$input" | jq -r '.tool_name // empty' 2>/dev/null || true)

if [ "$tool" != "Bash" ]; then
    exit 0
fi

cmd=$(echo "$input" | jq -r '.tool_input.command // empty' 2>/dev/null || true)
if [ -z "$cmd" ]; then
    exit 0
fi

approve() {
    jq -nc --arg reason "Auto-approved: $1" \
        '{hookSpecificOutput: {hookEventName: "PreToolUse", permissionDecision: "allow", permissionDecisionReason: $reason}}'
    exit 0
}

# Auto-approve only a single, simple invocation. A command that chains or
# substitutes (; && || | & redirection $(...) backticks) can hide a destructive
# tail behind a read-only prefix, so defer those to the normal permission prompt.
echo "$cmd" | grep -qE '[;&|<>`]|\$\(' && exit 0

# Writes to the repo-local scratch dir are safe. Require explicit ./tmp/ prefix
# (repo-relative) so bare tmp/ tokens in arbitrary commands don't match.
# Exclude rm/find-delete so plain destructive commands don't get auto-approved.
if ! echo "$cmd" | grep -qE '^\s*(rm\b|find\b.*-delete)'; then
    echo "$cmd" | grep -qE '(^|[[:space:]])\./tmp/' && approve "write to ./tmp/"
fi

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

# No pattern matched: defer to the normal permission flow without erroring.
exit 0
