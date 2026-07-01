# Hooks

Lifecycle hooks registered in `~/.claude/settings.json` by `setup.sh`. Scripts live in `hooks/`, symlinked to `~/.claude/hooks/`.

| Hook | Event | Trigger | Purpose |
|------|-------|---------|---------|
| `anti-sycophancy.sh` | UserPromptSubmit | Every prompt | Detects confirmatory language ("right?", "looks good"), injects critical-thinking reminder |
| `block-dangerous.sh` | PreToolUse | Bash / Write / Edit | Blocks `rm -rf`, `git push --force`, `DROP TABLE`, `killall`; denies Write/Edit to `.env`, SSH/AWS keys, `/etc/`, and system temp (`/tmp`, `/var/tmp`) — scratch goes in the repo's `tmp/` |
| `auto-approve.sh` | PreToolUse | Bash commands | Auto-approves known-safe read-only commands (linters, checkers, `ctest`) |
| `commit-lint.sh` | PreToolUse | Bash commands | Validates commit messages against conventional commits format, rejects non-conforming messages |
| `auto-format.sh` | PostToolUse | Write/Edit | Runs clang-format (.cpp/.hip/.cu), ruff/black (.py), jq (.json), shfmt (.sh) |
| `security-scan.sh` | PostToolUse | Write/Edit | Detects hardcoded AWS keys, API secrets, private keys, passwords, GitHub/GitLab tokens |
| `session-start.sh` | SessionStart | Start/resume/clear/compact | Injects git branch, status, recent commits; sets `PROJECT_ROOT`; re-injects saved state after compaction |
| `session-end.sh` | SessionEnd | Session end | Prunes `.claude/.dev-team/` scratch older than 7 days, clears stale state, logs |
| `context-save.sh` | PreCompact | Compaction | Saves git state to `.claude/.dotharness/session-state.md` (restored by `session-start.sh` on the next compact) |
| `notify-stop.sh` | Stop | End of each turn | Desktop notification via `notify-send` (includes the project dir). No Teams card — `Stop` fires every turn, so a per-turn ping would be noise |
| `notify-prompt.sh` | Notification | Permission / idle / elicitation prompts | Desktop notification plus a Teams card (includes the project dir) when Claude needs attention |
| `teams-notify.sh` | (helper) | Called by `notify-prompt.sh` | POSTs an Adaptive Card to a Teams webhook; no-op until a URL is configured |

Hook-generated runtime files (saved session state, session log) are written repo-locally under `.claude/.dotharness/` (git root, falling back to cwd), never to system-level `~/.claude/`. Add `.claude/.dotharness/` to a project's ignore rules to keep them out of git.

## Teams notifications

`teams-notify.sh` posts to a Microsoft Teams webhook so attention requests reach you when you are away from the machine. Only the `Notification` hook sends a Teams card (permission and idle prompts), so you get one ping when Claude actually needs you rather than one per turn. The webhook URL is never committed: set `TEAMS_WEBHOOK_URL`, or write it to `~/.claude/.dotharness/teams-webhook`. Without either, the helper is a silent no-op.

The legacy "Incoming Webhook" connector is retired, so the URL comes from a Power Automate Workflow:

1. In Teams, open the **Workflows** app → **Create** tab → **Create from blank**.
2. Add the trigger **"When a Teams webhook request is received"** and set **Who can trigger the flow** to **Anyone** (the helper posts with no auth token, so the URL itself is the secret).
3. Add the action **"Post card in a chat or channel"**: **Post as** = Flow bot, **Post in** = Chat with Flow bot, **Recipient** = yourself (a private DM to just you).
4. In the **Adaptive Card** field, paste the contents of `hooks/teams-adaptive-card.json` — it renders the flat `{title, text}` payload the helper sends.
5. **Save**, reopen the trigger box, and copy the **HTTP POST URL**.
6. Install the URL and send a test card:

```bash
mkdir -p ~/.claude/.dotharness
printf '%s\n' 'PASTE_URL_HERE' > ~/.claude/.dotharness/teams-webhook
chmod 600 ~/.claude/.dotharness/teams-webhook
bash ~/.claude/hooks/teams-notify.sh "Claude Code" "Test from dotharness"
```

The sender always shows as "Workflows" (the Flow bot's fixed name — Microsoft allows no alias); the card's bold title identifies it as Claude.
