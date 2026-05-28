#!/bin/bash
# Notification hook: desktop alert when Claude sends a notification.

if ! command -v notify-send &>/dev/null; then
    exit 0
fi

input=$(cat)
title=$(echo "$input" | jq -r '.title // "Claude Code"')
body=$(echo "$input" | jq -r '.message // .body // "Needs your attention"')

notify-send -u normal -t 5000 "$title" "$body"
