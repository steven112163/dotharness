#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly REPO_DIR
readonly CLAUDE_DIR="${HOME:?HOME is not set}/.claude"

link() {
    local src="$1" dst="$2"
    if [ -L "$dst" ]; then
        local cur
        cur=$(readlink "$dst")
        if [ "$cur" = "$src" ]; then
            echo "  ok  $dst"
            return
        fi
        echo "  upd $dst (was $cur)"
        ln -snf "$src" "$dst"
    elif [ -e "$dst" ]; then
        echo "  bak $dst -> ${dst}.bak"
        mv "$dst" "${dst}.bak"
        ln -s "$src" "$dst"
    else
        echo "  new $dst -> $src"
        ln -s "$src" "$dst"
    fi
}

link_items() {
    local src_dir="$1" dst_dir="$2"
    for item in "$src_dir"/*; do
        [ -e "$item" ] || continue
        # Folder docs live next to their code but must not be linked into the
        # live ~/.claude tree, where Claude would parse them as agents/styles/rules.
        [ "$(basename "$item")" = "README.md" ] && continue
        link "$item" "$dst_dir/$(basename "$item")"
    done
}

echo "Linking dotharness -> $CLAUDE_DIR"

# --- Rules: per-file so the folder README is not linked as a rule ---
echo "Rules:"
if [ -L "$CLAUDE_DIR/rules" ]; then
    echo "  converting $CLAUDE_DIR/rules from symlink to directory"
    rm "$CLAUDE_DIR/rules"
fi
mkdir -p "$CLAUDE_DIR/rules"
link_items "$REPO_DIR/rules" "$CLAUDE_DIR/rules"

# --- Skills: merge own + third-party into commands/ ---
echo "Skills:"
if [ -L "$CLAUDE_DIR/skills" ]; then
    echo "  converting $CLAUDE_DIR/skills from symlink to directory"
    rm "$CLAUDE_DIR/skills"
fi
mkdir -p "$CLAUDE_DIR/skills"
link_items "$REPO_DIR/skills" "$CLAUDE_DIR/skills"
for category_dir in "$REPO_DIR"/third-party/*/skills/{engineering,productivity}/; do
    [ -d "$category_dir" ] || continue
    for skill_dir in "$category_dir"*/; do
        [ -f "$skill_dir/SKILL.md" ] || continue
        link "$skill_dir" "$CLAUDE_DIR/skills/$(basename "$skill_dir")"
    done
done

# --- Agents (native subagents, reusable as delegated subagents or team teammates) ---
echo "Agents:"
mkdir -p "$CLAUDE_DIR/agents"
link_items "$REPO_DIR/agents" "$CLAUDE_DIR/agents"

# --- Hooks ---
echo "Hooks:"
mkdir -p "$CLAUDE_DIR/hooks"
link_items "$REPO_DIR/hooks" "$CLAUDE_DIR/hooks"

# Register hooks in global settings.json
readonly SETTINGS="$CLAUDE_DIR/settings.json"
register_hook() {
    local event="$1" command="$2" name="$3" timeout="${4:-10}"
    local matcher="${5:-}" async_rewake="${6:-0}"
    if jq -e ".hooks.${event}[]? | .hooks[]? | select(.command == \"$command\")" "$SETTINGS" >/dev/null 2>&1; then
        echo "  ok  $name"
    else
        echo "  add $name"
        local aw=false
        [ "$async_rewake" = "1" ] && aw=true
        if [ -n "$matcher" ]; then
            jq --arg evt "$event" --arg cmd "$command" --argjson to "$timeout" --arg mat "$matcher" --argjson aw "$aw" \
                '.hooks = (.hooks // {}) | .hooks[$evt] = ((.hooks[$evt] // []) + [{"matcher": $mat, "hooks": [({"type": "command", "command": $cmd, "timeout": $to} + (if $aw then {"asyncRewake": true} else {} end))]}])' \
                "$SETTINGS" >"${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
        else
            jq --arg evt "$event" --arg cmd "$command" --argjson to "$timeout" --argjson aw "$aw" \
                '.hooks = (.hooks // {}) | .hooks[$evt] = ((.hooks[$evt] // []) + [{"hooks": [({"type": "command", "command": $cmd, "timeout": $to} + (if $aw then {"asyncRewake": true} else {} end))]}])' \
                "$SETTINGS" >"${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
        fi
    fi
}

# Ensure settings.json exists so hooks/outputStyle can be set on a fresh machine.
if command -v jq &>/dev/null && [ ! -f "$SETTINGS" ]; then
    echo '{}' >"$SETTINGS"
    echo "  created $SETTINGS"
fi

if [ -f "$SETTINGS" ] && command -v jq &>/dev/null; then
    register_hook "UserPromptSubmit" "bash ~/.claude/hooks/anti-sycophancy.sh" "anti-sycophancy hook" 5
    register_hook "PreToolUse" "bash ~/.claude/hooks/block-dangerous.sh" "block-dangerous hook" 5 "Bash|Write|Edit"
    register_hook "PostToolUse" "bash ~/.claude/hooks/auto-format.sh" "auto-format hook" 10 "Write|Edit"
    register_hook "PostToolUse" "bash ~/.claude/hooks/security-scan.sh" "security-scan hook" 5 "Write|Edit" 1
    register_hook "Stop" "bash ~/.claude/hooks/notify-stop.sh" "notify-stop hook" 5
    register_hook "PreCompact" "bash ~/.claude/hooks/context-save.sh" "context-save hook" 10
    register_hook "Notification" "bash ~/.claude/hooks/notify-prompt.sh" "notify-prompt hook" 5
    register_hook "PreToolUse" "bash ~/.claude/hooks/auto-approve.sh" "auto-approve hook" 5 "Bash"
    register_hook "PreToolUse" "bash ~/.claude/hooks/commit-lint.sh" "commit-lint hook" 5 "Bash"
    register_hook "SessionStart" "bash ~/.claude/hooks/session-start.sh" "session-start hook" 10
    register_hook "SessionEnd" "bash ~/.claude/hooks/session-end.sh" "session-end hook" 10

    # Activate the dotharness output style unless the user already set one.
    if jq -e '.outputStyle' "$SETTINGS" >/dev/null 2>&1; then
        echo "  ok  outputStyle"
    else
        jq '.outputStyle = "dotharness"' "$SETTINGS" >"${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
        echo "  set outputStyle=dotharness"
    fi
elif [ ! -f "$SETTINGS" ]; then
    echo "  skipped (no settings.json found)"
elif ! command -v jq &>/dev/null; then
    echo "  skipped (jq not found, cannot update settings.json)"
fi

# --- Output styles ---
echo "Output styles:"
mkdir -p "$CLAUDE_DIR/output-styles"
link_items "$REPO_DIR/output-styles" "$CLAUDE_DIR/output-styles"

# --- Binaries (linked into ~/bin, which is on PATH) ---
echo "Binaries:"
readonly BIN_DIR="${HOME}/bin"
mkdir -p "$BIN_DIR"
link_items "$REPO_DIR/bin" "$BIN_DIR"

# --- Statusline ---
echo "Statusline:"
link "$REPO_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh"
if [ -f "$SETTINGS" ] && command -v jq &>/dev/null; then
    if jq -e '.statusLine.command == "bash ~/.claude/statusline.sh"' "$SETTINGS" >/dev/null 2>&1; then
        echo "  ok  statusLine"
    else
        jq '.statusLine = {"type": "command", "command": "bash ~/.claude/statusline.sh"}' \
            "$SETTINGS" >"${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
        echo "  set statusLine"
    fi
fi

# --- Pre-commit (repo-local lint/format gate in a venv; tools managed by pre-commit) ---
echo "Pre-commit:"
venv_dir="$REPO_DIR/.venv"
if [ ! -x "$venv_dir/bin/pre-commit" ]; then
    if command -v python3 &>/dev/null; then
        echo "  creating .venv and installing pre-commit"
        python3 -m venv "$venv_dir"
        "$venv_dir/bin/pip" install --quiet --upgrade pip pre-commit
    else
        echo "  skipped (python3 not found)"
    fi
fi
if [ -x "$venv_dir/bin/pre-commit" ]; then
    if (cd "$REPO_DIR" && "$venv_dir/bin/pre-commit" install >/dev/null); then
        echo "  installed git hook"
    else
        echo "  warn: pre-commit install failed"
    fi
else
    echo "  skipped git hook (pre-commit not available)"
fi

# --- Plugins (requires claude CLI) ---
echo "Plugins:"
if command -v claude &>/dev/null; then
    # claude-plugins-official is registered by default; add the Anthropic skills marketplace.
    if grep -q '"anthropic-agent-skills"' "$CLAUDE_DIR/plugins/known_marketplaces.json" 2>/dev/null; then
        echo "  ok  marketplace anthropic-agent-skills"
    else
        echo "  adding marketplace anthropic-agent-skills (anthropics/skills)"
        claude plugin marketplace add anthropics/skills
    fi
    for plugin in \
        "superpowers@claude-plugins-official" \
        "example-skills@anthropic-agent-skills" \
        "claude-api@anthropic-agent-skills"; do
        if grep -q "$plugin" "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null; then
            echo "  ok  $plugin"
        else
            echo "  installing $plugin"
            claude plugin install "$plugin"
        fi
    done
else
    echo "  skipped (claude CLI not found)"
fi

echo "Done."
