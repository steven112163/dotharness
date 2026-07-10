#!/bin/bash
set -euo pipefail

REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
readonly REPO_DIR
readonly CLAUDE_DIR="${HOME:?HOME is not set}/.claude"
readonly AGENTS_DIR="${HOME:?HOME is not set}/.agents"
readonly CODEX_DIR="${HOME:?HOME is not set}/.codex"

link() {
    local src="$1" dst="$2" indent="${3:-  }"
    if [ -L "$dst" ]; then
        local cur
        cur=$(readlink "$dst")
        if [ "$cur" = "$src" ]; then
            echo "${indent}ok  $dst"
            return
        fi
        echo "${indent}upd $dst (was $cur)"
        ln -snf "$src" "$dst"
    elif [ -e "$dst" ]; then
        echo "${indent}bak $dst -> ${dst}.bak"
        mv "$dst" "${dst}.bak"
        ln -s "$src" "$dst"
    else
        echo "${indent}new $dst -> $src"
        ln -s "$src" "$dst"
    fi
}

link_items() {
    local src_dir="$1" dst_dir="$2" indent="${3:-  }"
    for item in "$src_dir"/*; do
        [ -e "$item" ] || continue
        # Folder docs live next to their code but must not be linked into the
        # live ~/.claude tree, where Claude would parse them as agents/styles/rules.
        [ "$(basename "$item")" = "README.md" ] && continue
        link "$item" "$dst_dir/$(basename "$item")" "$indent"
    done
}

# Remove dangling symlinks that point back into this repo. Links that still
# resolve, or links pointing outside REPO_DIR, are left untouched, so unrelated
# files in shared dirs like ~/bin are never deleted.
prune() {
    local dst_dir="$1" indent="${2:-  }"
    [ -d "$dst_dir" ] || return 0
    for item in "$dst_dir"/*; do
        [ -L "$item" ] || continue
        [ -e "$item" ] && continue
        local target
        target=$(readlink "$item")
        case "$target" in
        "$REPO_DIR"/*)
            echo "${indent}rm  $item (dangling -> $target)"
            rm "$item"
            ;;
        esac
    done
}

# Symlink own + third-party skills straight from their repo sources into
# dst_dir. Called once per agent (Claude, Codex) so each agent's skills dir
# points directly at the source, never at another agent's dir.
link_skills_to() {
    local dst_dir="$1" indent="${2:-  }" category_dir skill_dir name
    mkdir -p "$dst_dir"
    link_items "$REPO_DIR/skills" "$dst_dir" "$indent"
    for category_dir in "$REPO_DIR"/third-party/*/skills/{engineering,productivity}/; do
        [ -d "$category_dir" ] || continue
        for skill_dir in "$category_dir"*/; do
            [ -f "$skill_dir/SKILL.md" ] || continue
            name=$(basename "$skill_dir")
            # caveman is provided always-on by the JuliusBrussee/caveman plugin
            # (installed below); skip the on-demand mattpocock copy to avoid a duplicate.
            [ "$name" = caveman ] && continue
            link "$skill_dir" "$dst_dir/$name" "$indent"
        done
    done
    # Safe to prune here even though the caveman-cleanup block below runs after:
    # that block does a direct rm, not something prune would ever need to catch.
    prune "$dst_dir" "$indent"
}

echo "Claude:"

# --- Rules: per-file so the folder README is not linked as a rule ---
echo "  Rules:"
if [ -L "$CLAUDE_DIR/rules" ]; then
    echo "    converting $CLAUDE_DIR/rules from symlink to directory"
    rm "$CLAUDE_DIR/rules"
fi
mkdir -p "$CLAUDE_DIR/rules"
link_items "$REPO_DIR/rules" "$CLAUDE_DIR/rules" "    "
prune "$CLAUDE_DIR/rules" "    "

# --- Skills: merge own + third-party into commands/ ---
echo "  Skills:"
if [ -L "$CLAUDE_DIR/skills" ]; then
    echo "    converting $CLAUDE_DIR/skills from symlink to directory"
    rm "$CLAUDE_DIR/skills"
fi
link_skills_to "$CLAUDE_DIR/skills" "    "
# Drop a caveman link from an earlier run, now that the plugin owns it.
if [ -L "$CLAUDE_DIR/skills/caveman" ]; then
    case "$(readlink "$CLAUDE_DIR/skills/caveman")" in
    "$REPO_DIR"/third-party/*)
        echo "    rm  $CLAUDE_DIR/skills/caveman (superseded by caveman plugin)"
        rm "$CLAUDE_DIR/skills/caveman"
        ;;
    esac
fi

# --- Agents (native subagents, reusable as delegated subagents or team teammates) ---
echo "  Agents:"
mkdir -p "$CLAUDE_DIR/agents"
link_items "$REPO_DIR/agents" "$CLAUDE_DIR/agents" "    "
prune "$CLAUDE_DIR/agents" "    "

# --- Hooks ---
echo "  Hooks:"
mkdir -p "$CLAUDE_DIR/hooks"
link_items "$REPO_DIR/hooks" "$CLAUDE_DIR/hooks" "    "
prune "$CLAUDE_DIR/hooks" "    "

# Register hooks in global settings.json
readonly SETTINGS="$CLAUDE_DIR/settings.json"
register_hook() {
    local event="$1" command="$2" name="$3" timeout="${4:-10}"
    local matcher="${5:-}" async_rewake="${6:-0}"
    if jq -e ".hooks.${event}[]? | .hooks[]? | select(.command == \"$command\")" "$SETTINGS" >/dev/null 2>&1; then
        echo "    ok  $name"
    else
        echo "    add $name"
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
    echo "    created $SETTINGS"
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

    # Allow codex commands without a per-call prompt (used by multi-review skill).
    if jq -e '.permissions.allow | index("Bash(codex exec *)")' "$SETTINGS" >/dev/null 2>&1; then
        echo "    ok  permissions.allow codex"
    else
        jq '.permissions.allow += ["Bash(codex exec *)"]' "$SETTINGS" >"${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
        echo "    set permissions.allow codex"
    fi

    # Activate the dotharness output style unless the user already set one.
    if jq -e '.outputStyle' "$SETTINGS" >/dev/null 2>&1; then
        echo "    ok  outputStyle"
    else
        jq '.outputStyle = "dotharness"' "$SETTINGS" >"${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
        echo "    set outputStyle=dotharness"
    fi
elif [ ! -f "$SETTINGS" ]; then
    echo "    skipped (no settings.json found)"
elif ! command -v jq &>/dev/null; then
    echo "    skipped (jq not found, cannot update settings.json)"
fi

# --- Output styles ---
echo "  Output styles:"
mkdir -p "$CLAUDE_DIR/output-styles"
link_items "$REPO_DIR/output-styles" "$CLAUDE_DIR/output-styles" "    "
prune "$CLAUDE_DIR/output-styles" "    "

# --- Binaries (linked into ~/bin, which is on PATH) ---
echo "  Binaries:"
readonly BIN_DIR="${HOME}/bin"
mkdir -p "$BIN_DIR"
link_items "$REPO_DIR/bin" "$BIN_DIR" "    "
prune "$BIN_DIR" "    "

# --- Libraries (linked into ~/lib, importable by ck* scripts) ---
echo "  Libraries:"
readonly _SETUP_LIB_DIR="${HOME}/lib"
mkdir -p "$_SETUP_LIB_DIR"
link_items "$REPO_DIR/lib" "$_SETUP_LIB_DIR" "    "
prune "$_SETUP_LIB_DIR" "    "

# --- Statusline ---
echo "  Statusline:"
link "$REPO_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh" "    "
if [ -f "$SETTINGS" ] && command -v jq &>/dev/null; then
    if jq -e '.statusLine.command == "bash ~/.claude/statusline.sh"' "$SETTINGS" >/dev/null 2>&1; then
        echo "    ok  statusLine"
    else
        jq '.statusLine = {"type": "command", "command": "bash ~/.claude/statusline.sh"}' \
            "$SETTINGS" >"${SETTINGS}.tmp" && mv "${SETTINGS}.tmp" "$SETTINGS"
        echo "    set statusLine"
    fi
fi

# --- Global gitignore (excludesFile applies to every repo on the machine) ---
echo "  Global gitignore:"
link "$REPO_DIR/gitignore_global" "${HOME:?HOME is not set}/.gitignore_global" "    "
if git config --global core.excludesFile &>/dev/null; then
    echo "    ok  core.excludesFile"
else
    git config --global core.excludesFile "${HOME:?HOME is not set}/.gitignore_global"
    echo "    set core.excludesFile"
fi

# --- Pre-commit (repo-local lint/format gate in a venv; tools managed by pre-commit) ---
echo "  Pre-commit:"
venv_dir="$REPO_DIR/.venv"
if [ ! -x "$venv_dir/bin/pre-commit" ]; then
    if command -v python3 &>/dev/null; then
        echo "    creating .venv and installing pre-commit, anthropic, mcp"
        python3 -m venv "$venv_dir"
        "$venv_dir/bin/pip" install --quiet --upgrade pip pre-commit anthropic "mcp>=1.27,<2"
    else
        echo "    skipped (python3 not found)"
    fi
else
    if ! "$venv_dir/bin/python3" -c "import anthropic" 2>/dev/null; then
        echo "    installing anthropic into existing .venv"
        "$venv_dir/bin/pip" install --quiet anthropic
    fi
    if ! "$venv_dir/bin/python3" -c "import mcp" 2>/dev/null; then
        echo "    installing mcp into existing .venv"
        "$venv_dir/bin/pip" install --quiet "mcp>=1.27,<2"
    fi
fi
if [ -x "$venv_dir/bin/pre-commit" ]; then
    if grep -q 'pre-commit.com' "$REPO_DIR/.git/hooks/pre-commit" 2>/dev/null; then
        echo "    ok  git hook (already installed)"
    elif (cd "$REPO_DIR" && "$venv_dir/bin/pre-commit" install >/dev/null); then
        echo "    installed git hook"
    else
        echo "    warn: pre-commit install failed"
    fi
else
    echo "    skipped git hook (pre-commit not available)"
fi

# --- playwright-cli (browser automation skill, available in every repo) ---
echo "  playwright-cli:"
if command -v npm &>/dev/null; then
    npm install -g @playwright/cli >/dev/null
    playwright-cli install --skills >/dev/null
    playwright-cli install-browser >/dev/null
    echo "    ok  playwright-cli"
else
    echo "    skipped (npm not found)"
fi

# --- graphify (codebase knowledge-graph skill, available in every repo) ---
echo "  graphify:"
if command -v pipx &>/dev/null; then
    pipx install --force graphifyy >/dev/null
    graphify install >/dev/null
    echo "    ok  graphify"
else
    echo "    skipped (pipx not found)"
fi

# --- Plugins (requires claude CLI) ---
echo "  Plugins:"
# Register a marketplace by name from a GitHub <owner/repo>, idempotently.
add_marketplace() {
    local name="$1" repo="$2"
    if grep -q "\"$name\"" "$CLAUDE_DIR/plugins/known_marketplaces.json" 2>/dev/null; then
        echo "    ok  marketplace $name"
    else
        echo "    adding marketplace $name ($repo)"
        claude plugin marketplace add "$repo"
    fi
}
if command -v claude &>/dev/null; then
    # claude-plugins-official is registered by default; add the rest.
    add_marketplace anthropic-agent-skills anthropics/skills
    # caveman and ponytail are always-on token-reduction plugins: caveman compresses
    # output prose via SessionStart/UserPromptSubmit hooks (needs node on PATH),
    # ponytail steers generated code toward YAGNI/minimal each session.
    add_marketplace caveman JuliusBrussee/caveman
    add_marketplace ponytail DietrichGebert/ponytail
    command -v node &>/dev/null || echo "    warn: node not on PATH; caveman hooks will not run until it is"
    for plugin in \
        "superpowers@claude-plugins-official" \
        "explanatory-output-style@claude-plugins-official" \
        "example-skills@anthropic-agent-skills" \
        "claude-api@anthropic-agent-skills" \
        "caveman@caveman" \
        "ponytail@ponytail"; do
        if grep -q "$plugin" "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null; then
            echo "    ok  $plugin"
        else
            echo "    installing $plugin"
            claude plugin install "$plugin"
        fi
    done
else
    echo "    skipped (claude CLI not found)"
fi

# --- ck-profile MCP server (user-level, available in every repo) ---
echo "  ck-profile MCP server:"
if command -v claude &>/dev/null && [ -x "$venv_dir/bin/python3" ]; then
    # `claude mcp get` prints Command and Args on separate lines, so both must
    # be checked individually rather than as one combined string.
    ckprofile_mcp_info=$(claude mcp get ck-profile 2>/dev/null || true)
    if grep -qF "$venv_dir/bin/python3" <<<"$ckprofile_mcp_info" &&
        grep -qF "$REPO_DIR/lib/ck-profile-mcp/server.py" <<<"$ckprofile_mcp_info"; then
        echo "    ok  ck-profile"
    else
        echo "    registering ck-profile"
        # Remove first in case a mismatched entry already exists (e.g. repo
        # moved or .venv recreated elsewhere) — `mcp add` fails if the name is
        # already registered, which would abort the script under set -e.
        claude mcp remove ck-profile -s user 2>/dev/null || true
        claude mcp add -s user ck-profile -- "$venv_dir/bin/python3" "$REPO_DIR/lib/ck-profile-mcp/server.py"
    fi
else
    echo "    skipped (claude CLI or .venv not found)"
fi

# --- Codex CLI (optional: wire up shared assets when codex is present) ---
echo "Codex:"
if command -v codex &>/dev/null; then
    # Skills: Codex reads ~/.agents/skills/<name>/SKILL.md — same format as Claude.
    echo "  Skills:"
    # One-time cleanup: drop symlinks left over from an earlier setup.sh that
    # pointed here through $CLAUDE_DIR instead of straight at the repo (e.g. a
    # skill excluded from link_skills_to, like caveman, never gets relinked and
    # would otherwise dangle forever once its $CLAUDE_DIR counterpart is removed).
    if [ -d "$AGENTS_DIR/skills" ]; then
        for item in "$AGENTS_DIR/skills"/*; do
            [ -L "$item" ] || continue
            case "$(readlink "$item")" in
            "$CLAUDE_DIR"/*)
                echo "    rm  $item (was linked through \$CLAUDE_DIR)"
                rm "$item"
                ;;
            esac
        done
    fi
    link_skills_to "$AGENTS_DIR/skills" "    "

    # Rules: Codex reads a single AGENTS.md at ~/.agents/AGENTS.md.
    # Concatenate all rule files into one file (generated, not symlinked).
    echo "  Rules -> AGENTS.md:"
    mkdir -p "$AGENTS_DIR"
    agents_md="$AGENTS_DIR/AGENTS.md"
    agents_md_tmp="${agents_md}.tmp"
    {
        echo "# dotharness rules (generated by setup.sh — do not edit)"
        echo ""
        for rule in "$REPO_DIR/rules"/*.md; do
            [ -f "$rule" ] || continue
            [ "$(basename "$rule")" = "README.md" ] && continue
            echo "<!-- $(basename "$rule") -->"
            cat "$rule"
            echo ""
        done
    } >"$agents_md_tmp"
    if [ -f "$agents_md" ] && diff -q "$agents_md" "$agents_md_tmp" >/dev/null 2>&1; then
        echo "    ok  $agents_md"
        rm "$agents_md_tmp"
    else
        mv "$agents_md_tmp" "$agents_md"
        echo "    upd $agents_md"
    fi

    # Hooks: register in ~/.codex/config.toml using Codex's [[hooks.*]] TOML format.
    # The same .sh scripts are reused; the JSON stdin schema is compatible.
    echo "  Hooks:"
    mkdir -p "$CODEX_DIR"
    chmod 700 "$CODEX_DIR"
    readonly CODEX_CONFIG="$CODEX_DIR/config.toml"
    if [ -e "$CODEX_CONFIG" ] && [ ! -f "$CODEX_CONFIG" ]; then
        echo "error: $CODEX_CONFIG exists but is not a regular file" >&2
        exit 1
    fi
    [ -f "$CODEX_CONFIG" ] || touch "$CODEX_CONFIG"
    register_codex_hook() {
        local event="$1" command="$2" name="$3" timeout="${4:-10}" matcher="${5:-}"
        # Check idempotently: grep for the command string in the config.
        if grep -qF "$command" "$CODEX_CONFIG" 2>/dev/null; then
            echo "    ok  $name"
            return
        fi
        echo "    add $name"
        if [ -n "$matcher" ]; then
            printf '\n[[hooks.%s]]\nmatcher = "%s"\n[[hooks.%s.hooks]]\ntype = "command"\ncommand = "%s"\ntimeout = %d\n' \
                "$event" "$matcher" "$event" "$command" "$timeout" >>"$CODEX_CONFIG"
        else
            printf '\n[[hooks.%s]]\n[[hooks.%s.hooks]]\ntype = "command"\ncommand = "%s"\ntimeout = %d\n' \
                "$event" "$event" "$command" "$timeout" >>"$CODEX_CONFIG"
        fi
    }
    register_codex_hook "UserPromptSubmit" "bash ~/.claude/hooks/anti-sycophancy.sh" "anti-sycophancy" 5
    register_codex_hook "PreToolUse" "bash ~/.claude/hooks/block-dangerous.sh" "block-dangerous" 5 "Bash"
    register_codex_hook "PostToolUse" "bash ~/.claude/hooks/auto-format.sh" "auto-format" 10 "Write|Edit"
    register_codex_hook "PostToolUse" "bash ~/.claude/hooks/security-scan.sh" "security-scan" 5 "Write|Edit"
    register_codex_hook "PreToolUse" "bash ~/.claude/hooks/commit-lint.sh" "commit-lint" 5 "Bash"
    register_codex_hook "SessionStart" "bash ~/.claude/hooks/session-start.sh" "session-start" 10

    # Statusline: Codex tui.status_line takes a fixed enum list (no shell-backed custom scripts).
    echo "  Statusline:"
    if grep -q 'status_line' "$CODEX_CONFIG" 2>/dev/null; then
        echo "    ok  tui.status_line"
    elif grep -q '^\[tui\]' "$CODEX_CONFIG" 2>/dev/null; then
        # [tui] exists but lacks status_line — insert below the header, not at EOF,
        # so the key lands in the right section regardless of what follows [tui].
        awk '/^\[tui\]/{print; print "status_line = [\"model-with-reasoning\", \"git-branch\", \"context-usage\", \"used-tokens\", \"five-hour-limit\"]"; next}1' \
            "$CODEX_CONFIG" >"${CODEX_CONFIG}.tmp" && mv "${CODEX_CONFIG}.tmp" "$CODEX_CONFIG"
        echo "    set tui.status_line"
    else
        printf '\n[tui]\nstatus_line = ["model-with-reasoning", "git-branch", "context-usage", "used-tokens", "five-hour-limit"]\n' \
            >>"$CODEX_CONFIG"
        echo "    set tui.status_line"
    fi

    # Plugins: caveman, ponytail, and superpowers all ship .codex-plugin manifests
    # and are installable via codex plugin marketplace add.
    echo "  Plugins:"
    add_codex_marketplace() {
        local name="$1" repo="$2"
        local marketplaces_dir="$CODEX_DIR/plugins/known_marketplaces.json"
        if [ -f "$marketplaces_dir" ] && grep -q "\"$repo\"" "$marketplaces_dir" 2>/dev/null; then
            echo "    ok  marketplace $name"
            return
        fi
        echo "    adding marketplace $name ($repo)"
        if ! codex plugin marketplace add "$repo" 2>/dev/null; then
            echo "    warn: marketplace add failed (fork build restriction?); install manually:"
            echo "          codex plugin marketplace add $repo"
        fi
    }
    command -v node &>/dev/null || echo "    warn: node not on PATH; caveman/ponytail hooks need node"
    add_codex_marketplace caveman JuliusBrussee/caveman
    add_codex_marketplace ponytail DietrichGebert/ponytail
    # superpowers: Codex has a built-in official marketplace; add the anthropic skills source too.
    add_codex_marketplace anthropic-agent-skills anthropics/skills

    # graphify: Codex needs its own explicit platform install.
    echo "  graphify:"
    if command -v graphify &>/dev/null; then
        graphify install --platform codex >/dev/null
        echo "    ok  graphify"
    else
        echo "    skipped (graphify not found)"
    fi
else
    echo "  skipped (codex not found)"
fi

echo "Done."
