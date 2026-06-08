#!/bin/bash
# Stop hook: local desktop pop-up at the end of each turn.
# No Teams card here — Stop fires every turn; "waiting on you" reaches Teams via
# the Notification hook's idle_prompt instead.
# notify-send is time-bounded: on a host with no notification daemon it blocks
# ~50s on D-Bus, which would otherwise trip the hook's 5s timeout.
set -euo pipefail

if command -v notify-send &>/dev/null; then
    input=$(cat || true)
    dir=$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null || true)
    dir=${dir##*/}
    body="Finished — waiting for input"
    [ -n "$dir" ] && body="$body  ($dir)"
    timeout 3 notify-send -u normal -t 5000 "Claude Code" "$body" 2>/dev/null || true
fi
