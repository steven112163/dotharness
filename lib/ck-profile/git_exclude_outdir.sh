#!/usr/bin/env bash
# Make git ignore the profiling output WITHOUT touching the tracked .gitignore:
# append `ck_profile_out/` to the repo's .git/info/exclude (repo-local, never
# committed). Idempotent, and a silent no-op outside a git repo. Uses the *common*
# git dir so it is correct inside linked worktrees too (info/exclude lives there).
#
#   $1  any path inside the repo (default: $PWD)
repo="${1:-$PWD}"
gdir=$(git -C "$repo" rev-parse --git-common-dir 2>/dev/null) || exit 0
case "$gdir" in /*) ;; *) gdir="$repo/$gdir" ;; esac # resolve relative common-dir
mkdir -p "$gdir/info" 2>/dev/null || exit 0
excl="$gdir/info/exclude"
grep -qxF 'ck_profile_out/' "$excl" 2>/dev/null || printf 'ck_profile_out/\n' >>"$excl"
