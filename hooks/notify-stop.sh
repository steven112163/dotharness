#!/bin/bash
# Stop hook: desktop notification when Claude finishes (main session only).

if command -v notify-send &>/dev/null; then
    notify-send -u normal -t 5000 "Claude Code" "Finished — waiting for input"
fi
