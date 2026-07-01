#!/usr/bin/env bash
# Gather review context for the multi-review skill.
# Usage: gather_context.sh [PR_NUMBER]
#   no arg  -> local mode: diff uncommitted changes (tracked edits + new files)
#              against HEAD when the tree is dirty, else the branch's commits
#              against their merge-base with upstream.
#   PR num  -> PR mode: fetch PR diff, metadata, and existing reviews via gh.
# Writes diff.txt, per-file chunk-* files, and chunks.tsv (file<TAB>chunk) into
# REVIEW_DIR (created if unset). Prints REVIEW_DIR to stdout.
set -euo pipefail

PR_NUMBER="${1:-}"
# Default the scratch dir under the repo's .claude/tmp (gitignored). Inside a repo
# this keeps scratch out of /tmp; outside a repo fall back to $TMPDIR rather than
# writing .claude/tmp into an arbitrary cwd.
if [ -z "${REVIEW_DIR:-}" ]; then
    if repo_root=$(git rev-parse --show-toplevel 2>/dev/null); then
        tmp_root="$repo_root/.claude/tmp"
        mkdir -p "$tmp_root"
        REVIEW_DIR=$(mktemp -d "$tmp_root/multi-review-XXXXXX")
    else
        REVIEW_DIR=$(mktemp -d "${TMPDIR:-/tmp}/multi-review-XXXXXX")
    fi
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

if [ -n "$PR_NUMBER" ]; then
    gh pr view "$PR_NUMBER" --json title,body,headRefName,headRefOid,url,files >"$REVIEW_DIR/pr.json"
    gh pr diff "$PR_NUMBER" >"$REVIEW_DIR/diff.txt"
    owner_repo=$(gh repo view --json nameWithOwner -q .nameWithOwner)
    gh api "repos/$owner_repo/pulls/$PR_NUMBER/reviews" >"$REVIEW_DIR/reviews.json" 2>/dev/null || echo '[]' >"$REVIEW_DIR/reviews.json"
    gh api "repos/$owner_repo/pulls/$PR_NUMBER/comments" >"$REVIEW_DIR/review_comments.json" 2>/dev/null || echo '[]' >"$REVIEW_DIR/review_comments.json"
else
    # Prefer uncommitted changes when the working tree is dirty: the current work
    # is not committed yet, so diff it against HEAD. "Dirty" includes tracked
    # edits (staged or not) and new untracked files. Otherwise diff the branch's
    # commits against their merge-base with upstream.
    untracked=$(git ls-files --others --exclude-standard)
    if ! git rev-parse --verify -q HEAD >/dev/null 2>&1; then
        # No commits yet: nothing to diff against. Empty diff -> "nothing to review".
        : >"$REVIEW_DIR/diff.txt"
    elif ! git diff --quiet HEAD 2>/dev/null || [ -n "$untracked" ]; then
        # Tracked edits first. git diff omits untracked files, so append each as a
        # synthetic new-file diff via --no-index (read-only; never touches the index).
        git diff HEAD >"$REVIEW_DIR/diff.txt"
        while IFS= read -r f; do
            [ -n "$f" ] || continue
            git diff --no-index -- /dev/null "$f" >>"$REVIEW_DIR/diff.txt" || true
        done <<<"$untracked"
    else
        upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo main)
        base=$(git merge-base HEAD "$upstream")
        git diff "$base"..HEAD >"$REVIEW_DIR/diff.txt"
    fi
fi

split_chunks "$REVIEW_DIR/diff.txt"

# Compute SHAs. BASE_SHA matches the base the diff was actually taken against:
# HEAD when we diffed a dirty working tree (or PR mode), merge-base otherwise.
HEAD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
CODEX_REVIEW_FLAGS=""
if [ -n "$PR_NUMBER" ]; then
    # PR mode: diff is the PR's full patch set; SHA context is HEAD of the PR head.
    BASE_SHA=$HEAD_SHA
    CODEX_REVIEW_FLAGS="--base $BASE_SHA"
elif [ -n "${untracked:-}" ] || ! git diff --quiet HEAD 2>/dev/null; then
    # Dirty working tree was diffed against HEAD — use --uncommitted so codex review
    # sees the same changes as the diff (not a commit range, which would be empty).
    BASE_SHA=$HEAD_SHA
    CODEX_REVIEW_FLAGS="--uncommitted"
else
    upstream=$(git rev-parse --abbrev-ref '@{upstream}' 2>/dev/null || echo main)
    BASE_SHA=$(git merge-base HEAD "$upstream" 2>/dev/null || echo "$HEAD_SHA")
    CODEX_REVIEW_FLAGS="--base $BASE_SHA"
fi
printf 'HEAD_SHA=%s\nBASE_SHA=%s\nCODEX_REVIEW_FLAGS=%s\n' "$HEAD_SHA" "$BASE_SHA" "$CODEX_REVIEW_FLAGS" >"$REVIEW_DIR/shas.env"

echo "$REVIEW_DIR"
