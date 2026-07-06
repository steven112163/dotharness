#!/usr/bin/env bash
# Gather git context for the create-pr skill.
# Usage: gather_pr_context.sh [BASE_BRANCH]
#   BASE_BRANCH defaults to "develop" in a detected Composable Kernel (CK)
#   repo, otherwise the repo's default branch (origin/HEAD), falling back to
#   "main".
# Outputs a human-readable summary to stdout covering:
#   - repo type (CK or generic)
#   - current branch name
#   - base branch
#   - uncommitted changes (warning if any)
#   - commits ahead of base (git log --oneline)
#   - diff stat vs base
set -euo pipefail

default_branch() {
    git symbolic-ref refs/remotes/origin/HEAD 2>/dev/null | sed 's@^refs/remotes/origin/@@'
}

is_ck_repo() {
    local remote_url
    remote_url=$(git remote get-url origin 2>/dev/null || true)
    [[ "$remote_url" =~ [Cc]omposable[_-]?[Kk]ernel ]]
}

CK_REPO=0
if is_ck_repo; then
    CK_REPO=1
fi

echo "=== Repo type ==="
if [ "$CK_REPO" -eq 1 ]; then
    echo "Composable Kernel (CK) — apply CK-specific PR conventions"
else
    echo "Generic"
fi
echo ""

if [ "$CK_REPO" -eq 1 ]; then
    BASE="${1:-develop}"
else
    BASE="${1:-$(default_branch)}"
    BASE="${BASE:-main}"
fi
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
