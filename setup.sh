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

echo "Linking dotharness -> $CLAUDE_DIR"

link "$REPO_DIR/skills" "$CLAUDE_DIR/commands"
link "$REPO_DIR/rules"  "$CLAUDE_DIR/rules"
link "$REPO_DIR/statusline.sh" "$CLAUDE_DIR/statusline.sh"

echo "Done."
