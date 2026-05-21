#!/bin/bash
set -euo pipefail

readonly REPO_DIR="$(cd "$(dirname "$0")" && pwd)"
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
        link "$item" "$dst_dir/$(basename "$item")"
    done
}

echo "Linking dotharness -> $CLAUDE_DIR"

# --- Rules ---
echo "Rules:"
link "$REPO_DIR/rules" "$CLAUDE_DIR/rules"

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

# --- Statusline ---
echo "Statusline:"
link "$REPO_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh"

# --- Plugins (requires claude CLI) ---
echo "Plugins:"
if command -v claude &>/dev/null; then
    for plugin in "superpowers@claude-plugins-official"; do
        if grep -q "$plugin" "$CLAUDE_DIR/plugins/installed_plugins.json" 2>/dev/null; then
            echo "  ok  $plugin"
        else
            echo "  installing $plugin"
            claude /plugin install "$plugin"
        fi
    done
else
    echo "  skipped (claude CLI not found)"
fi

echo "Done."
