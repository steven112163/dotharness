#!/usr/bin/env bash
# Gather git context for the create-pr skill.
# Usage: gather_pr_context.sh [BASE_BRANCH]
#   BASE_BRANCH defaults to "develop".
# Outputs a human-readable summary to stdout covering:
#   - current branch name
#   - base branch
#   - uncommitted changes (warning if any)
#   - commits ahead of base (git log --oneline)
#   - diff stat vs base
set -euo pipefail

BASE="${1:-develop}"
BRANCH=$(git rev-parse --abbrev-ref HEAD)

echo "=== Branch ==="
echo "Current: $BRANCH"
echo "Base:    $BASE"
echo ""

# Check for uncommitted changes (tracked edits + untracked files).
DIRTY=0
if ! git diff --quiet HEAD 2>/dev/null; then
    DIRTY=1
fi
UNTRACKED=$(git ls-files --others --exclude-standard)
if [ -n "$UNTRACKED" ]; then
    DIRTY=1
fi

if [ "$DIRTY" -eq 1 ]; then
    echo "=== WARNING: Uncommitted changes ==="
    git status --short
    echo ""
fi

echo "=== Commits ahead of $BASE ==="
if git rev-parse --verify "$BASE" >/dev/null 2>&1; then
    BASE_REF="$BASE"
elif git rev-parse --verify "origin/$BASE" >/dev/null 2>&1; then
    BASE_REF="origin/$BASE"
else
    echo "(base branch '$BASE' not found locally or in origin)"
    BASE_REF=""
fi

if [ -n "$BASE_REF" ]; then
    git log "${BASE_REF}..HEAD" --oneline
    echo ""
    echo "=== Diff stat vs $BASE ==="
    git diff --stat "${BASE_REF}..HEAD"
else
    echo "(skipped — base not resolvable)"
fi
