#!/bin/bash
# PostToolUse hook: auto-format code files after Write/Edit.
set -euo pipefail

input=$(cat || true)
file=$(echo "$input" | jq -r '.tool_input.file_path // .tool_response.filePath // empty' 2>/dev/null || true)

if [ -z "$file" ] || [ ! -f "$file" ]; then
    exit 0
fi

ext="${file##*.}"
base=$(basename "$file")

# Treat CMakeLists.txt as a cmake file so the formatter is wired in one place.
[ "$base" = "CMakeLists.txt" ] && ext="cmake"

case "$ext" in
cpp | hpp | h | c | cc | cxx | hip | cu | cuh)
    if command -v clang-format &>/dev/null; then
        clang-format -i "$file" 2>/dev/null || true
    fi
    ;;
py)
    if command -v ruff &>/dev/null; then
        ruff format "$file" 2>/dev/null || true
    elif command -v black &>/dev/null; then
        black --quiet "$file" 2>/dev/null || true
    fi
    ;;
json)
    if command -v jq &>/dev/null; then
        tmp=$(mktemp)
        if jq '.' "$file" >"$tmp" 2>/dev/null; then
            mv "$tmp" "$file"
        else
            rm -f "$tmp"
        fi
    fi
    ;;
sh | bash)
    if command -v shfmt &>/dev/null; then
        shfmt -w "$file" 2>/dev/null || true
    fi
    ;;
cmake)
    if command -v cmake-format &>/dev/null; then
        cmake-format -i "$file" 2>/dev/null || true
    fi
    ;;
esac
