#!/bin/bash
# Helper: POST a title + body to a Microsoft Teams webhook as an Adaptive Card.
# Called by notify-stop.sh and notify-prompt.sh; not registered as a hook itself.
#
# No-op (exit 0) when no webhook URL is configured, so a fresh machine without
# Teams set up is never broken. URL resolution order:
#   1. $TEAMS_WEBHOOK_URL
#   2. ~/.claude/.dotharness/teams-webhook   (one line: the Workflow POST URL)
#
# Usage: teams-notify.sh "<title>" "<body>"

title=${1:-Claude Code}
body=${2:-Needs your attention}

webhook=${TEAMS_WEBHOOK_URL:-}
[ -z "$webhook" ] && webhook=$(cat "$HOME/.claude/.dotharness/teams-webhook" 2>/dev/null)
[ -z "$webhook" ] && exit 0
command -v curl &>/dev/null || exit 0
command -v jq   &>/dev/null || exit 0

# Flat payload; the Teams Workflow's "Post card" action builds the card from
# these two fields (referenced as triggerBody()?['title'] / ['text']).
payload=$(jq -n --arg t "$title" --arg b "$body" '{title: $t, text: $b}')

curl -sS --max-time 5 -H "Content-Type: application/json" \
  -d "$payload" "$webhook" >/dev/null 2>&1 || true
