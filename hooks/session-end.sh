#!/bin/bash
# SessionEnd hook: conservative cleanup of coordination scratch and stale state.
# Non-blocking. SessionEnd cannot inject context, so this only cleans and logs.
# All runtime files live repo-locally under .claude/.dotharness (not $HOME).
set -euo pipefail

input=$(cat 2>/dev/null || true)
reason=$(echo "$input" | jq -r '.reason // "unknown"' 2>/dev/null || echo unknown)

root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
run_dir="$root/.claude/.dotharness"

removed=""

# Prune dev-team coordination scratch older than 7 days. These are declared
# non-git scratch files (see dev-team skill). Adjust -mtime to change retention.
scratch="$root/.claude/.dev-team"
if [ -d "$scratch" ]; then
    while IFS= read -r d; do
        [ -n "$d" ] || continue
        rm -rf "$d" && removed="${removed}${d} "
    done < <(find "$scratch" -mindepth 1 -maxdepth 1 -type d -mtime +7 2>/dev/null)
fi

# Drop the pre-compaction state file; the next session's PreCompact rewrites it.
rm -f "$run_dir/session-state.md" 2>/dev/null || true

mkdir -p "$run_dir" 2>/dev/null || true
echo "$(date -Iseconds) end reason=${reason} cwd=$(pwd) pruned=[${removed% }]" >> "$run_dir/session.log" 2>/dev/null || true
exit 0
