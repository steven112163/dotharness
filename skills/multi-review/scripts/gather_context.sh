#!/usr/bin/env bash
# Gather review context for the multi-review skill.
# Usage: gather_context.sh [PR_NUMBER | PR_URL | repo]
#   no arg          -> local mode: diff the current branch (working tree included)
#                      against its merge-base with upstream (or main).
#   repo | all      -> repo mode: every tracked file as a synthetic new-file diff.
#   PR num or URL   -> PR mode: fetch PR diff, metadata, and existing reviews via gh.
# Writes diff.txt, per-file chunk-* files, and chunks.tsv (file<TAB>chunk) into
# REVIEW_DIR (created if unset). Prints REVIEW_DIR to stdout.
set -euo pipefail

ARG="${1:-}"
# Scratch dir under the repo's tmp/ (gitignored). Errors if not in a git repo.
if [ -z "${REVIEW_DIR:-}" ]; then
    repo_root=$(git rev-parse --show-toplevel 2>/dev/null) || {
        echo "ERROR: gather_context.sh must be run inside a git repo" >&2
        exit 1
    }
    tmp_root="$repo_root/tmp"
    mkdir -p "$tmp_root"
    REVIEW_DIR=$(mktemp -d "$tmp_root/multi-review-XXXXXX")
fi
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

# Append files as synthetic new-file diffs (--no-index is read-only; never
# touches the index), so untracked files and repo mode reuse the chunk pipeline.
append_as_new_files() {
    local f
    while IFS= read -r f; do
        [ -n "$f" ] || continue
        git diff --no-index -- /dev/null "$f" >>"$REVIEW_DIR/diff.txt" || true
    done
}

HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
BASE_SHA=$HEAD_SHA

case "$ARG" in
repo | all)
    # Whole-repo mode: every tracked file presented as newly added.
    # ponytail: no size cap; a large repo produces a large diff. Narrow with a
    # pathspec by running in a subdirectory if that becomes a problem.
    : >"$REVIEW_DIR/diff.txt"
    git ls-files | append_as_new_files
    ;;
"")
    # Local mode: current branch against its base, working tree included.
    untracked=$(git ls-files --others --exclude-standard)
    if ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
        # No commits yet: nothing to diff against. Empty diff -> "nothing to review".
        : >"$REVIEW_DIR/diff.txt"
    else
        upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo main)
        BASE_SHA=$(git merge-base HEAD "$upstream" 2>/dev/null || echo "$HEAD_SHA")
        git diff "$BASE_SHA" >"$REVIEW_DIR/diff.txt"
        printf '%s\n' "$untracked" | append_as_new_files
    fi
    ;;
*)
    # PR mode. ARG is a PR number or a PR URL; gh accepts either directly.
    pr_number=$(printf '%s\n' "$ARG" | sed -nE 's#.*/pull/([0-9]+).*#\1#p')
    [ -n "$pr_number" ] || pr_number="$ARG"
    case "$ARG" in
    *://*) owner_repo=$(printf '%s\n' "$ARG" | sed -nE 's#^[a-z]+://[^/]+/([^/]+/[^/]+)/pull/.*#\1#p') ;;
    *) owner_repo="" ;;
    esac
    [ -n "$owner_repo" ] || owner_repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    gh pr view "$ARG" --json title,body,headRefName,headRefOid,url,files >"$REVIEW_DIR/pr.json"
    gh pr diff "$ARG" >"$REVIEW_DIR/diff.txt"
    gh api "repos/$owner_repo/pulls/$pr_number/reviews" >"$REVIEW_DIR/reviews.json" 2>/dev/null || echo '[]' >"$REVIEW_DIR/reviews.json"
    gh api "repos/$owner_repo/pulls/$pr_number/comments" >"$REVIEW_DIR/review_comments.json" 2>/dev/null || echo '[]' >"$REVIEW_DIR/review_comments.json"
    ;;
esac

split_chunks "$REVIEW_DIR/diff.txt"

printf 'HEAD_SHA=%s\nBASE_SHA=%s\n' "$HEAD_SHA" "$BASE_SHA" >"$REVIEW_DIR/shas.env"

echo "$REVIEW_DIR"
