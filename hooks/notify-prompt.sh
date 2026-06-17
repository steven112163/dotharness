#!/bin/bash
# Notification hook: Teams card + desktop pop-up when Claude needs attention
# (permission prompt, idle prompt, elicitation dialog, etc.).
set -euo pipefail

input=$(cat || true)
title=$(echo "$input" | jq -r '.title // "Claude Code"' 2>/dev/null || echo "Claude Code")
body=$(echo "$input" | jq -r '.message // .body // "Needs your attention"' 2>/dev/null || echo "Needs your attention")
dir=$(echo "$input" | jq -r '.cwd // ""' 2>/dev/null || true)
dir=${dir##*/}
[ -n "$dir" ] && body="$body  ($dir)"

# Teams first: it is the remote alert that matters when away and finishes in
# under a second. The desktop pop-up is time-bounded because on a host with no
# notification daemon, notify-send blocks ~50s on D-Bus — which would trip the
# hook's 5s timeout and the Teams POST would never run.
bash "$(dirname "$0")/teams-notify.sh" "$title" "$body" || true

if command -v notify-send &>/dev/null; then
    timeout 3 notify-send -u normal -t 5000 "$title" "$body" 2>/dev/null || true
fi
