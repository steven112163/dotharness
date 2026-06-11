#!/usr/bin/env bash
# Gather review context for the multi-review skill.
# Usage: gather_context.sh [PR_NUMBER]
#   no arg  -> local mode: diff current branch against its merge-base.
#   PR num  -> PR mode: fetch PR diff, metadata, and existing reviews via gh.
# Writes diff.txt, per-file chunk-* files, and chunks.tsv (file<TAB>chunk) into
# REVIEW_DIR (created if unset). Prints REVIEW_DIR to stdout.
set -euo pipefail

PR_NUMBER="${1:-}"
REVIEW_DIR="${REVIEW_DIR:-$(mktemp -d "${TMPDIR:-/tmp}/multi-review-XXXXXX")}"
mkdir -p "$REVIEW_DIR"

split_chunks() {
    local diff="$1"
    [ -s "$diff" ] || return 0
    csplit -sz -f "$REVIEW_DIR/chunk-" -- "$diff" '/^diff --git/' '{*}'
    : >"$REVIEW_DIR/chunks.tsv"
    local c path
    for c in "$REVIEW_DIR"/chunk-*; do
        [ -e "$c" ] || continue
        path=$(sed -n 's#^diff --git a/.* b/##p' "$c" | head -1)
        [ -n "$path" ] && printf '%s\t%s\n' "$path" "$c" >>"$REVIEW_DIR/chunks.tsv"
    done
}

if [ -n "$PR_NUMBER" ]; then
    gh pr view "$PR_NUMBER" --json title,body,headRefName,headRefOid,url,files >"$REVIEW_DIR/pr.json"
    gh pr diff "$PR_NUMBER" >"$REVIEW_DIR/diff.txt"
    owner_repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    gh api "repos/$owner_repo/pulls/$PR_NUMBER/reviews" >"$REVIEW_DIR/reviews.json" 2>/dev/null || echo '[]' >"$REVIEW_DIR/reviews.json"
    gh api "repos/$owner_repo/pulls/$PR_NUMBER/comments" >"$REVIEW_DIR/review_comments.json" 2>/dev/null || echo '[]' >"$REVIEW_DIR/review_comments.json"
else
    upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo main)
    base=$(git merge-base HEAD "$upstream")
    git diff "$base"..HEAD >"$REVIEW_DIR/diff.txt"
fi

split_chunks "$REVIEW_DIR/diff.txt"
echo "$REVIEW_DIR"
