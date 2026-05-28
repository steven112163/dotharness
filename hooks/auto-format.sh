#!/bin/bash
# PostToolUse hook: auto-format code files after Write/Edit.

input=$(cat)
file=$(echo "$input" | jq -r '.tool_input.file_path // .tool_response.filePath // empty')

if [ -z "$file" ] || [ ! -f "$file" ]; then
    exit 0
fi

ext="${file##*.}"
base=$(basename "$file")

case "$ext" in
    cpp|hpp|h|c|cc|cxx|hip|cu|cuh)
        if command -v clang-format &>/dev/null; then
            clang-format -i "$file" 2>/dev/null
        fi
        ;;
    py)
        if command -v ruff &>/dev/null; then
            ruff format "$file" 2>/dev/null
        elif command -v black &>/dev/null; then
            black --quiet "$file" 2>/dev/null
        fi
        ;;
    json)
        if command -v jq &>/dev/null; then
            tmp=$(mktemp)
            if jq '.' "$file" > "$tmp" 2>/dev/null; then
                mv "$tmp" "$file"
            else
                rm -f "$tmp"
            fi
        fi
        ;;
    sh|bash)
        if command -v shfmt &>/dev/null; then
            shfmt -w "$file" 2>/dev/null
        fi
        ;;
    cmake)
        if command -v cmake-format &>/dev/null; then
            cmake-format -i "$file" 2>/dev/null
        fi
        ;;
esac

# Handle CMakeLists.txt by basename
if [ "$base" = "CMakeLists.txt" ]; then
    if command -v cmake-format &>/dev/null; then
        cmake-format -i "$file" 2>/dev/null
    fi
fi
