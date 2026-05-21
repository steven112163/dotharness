#!/bin/bash
# Claude Code status line script — compact edition
# Format: dir branch [HH:MM MM/DD] model [name] ctx effort style thinking

input=$(cat)

cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // empty')
cwd="${cwd:-$(pwd)}"

# Colors (ANSI escape codes)
txtred='\e[0;31m'
txtylw='\e[0;33m'
txtgrn='\e[0;32m'
txtpur='\e[0;35m'
txtwht='\e[0;37m'
txtcyn='\e[0;36m'
txtblu='\e[0;34m'
txtrst='\e[0m'

# --- Directory: basename only ---
dir_str=$(basename "$cwd")

# --- Git: branch + dirty indicator ---
git_str=""
branch_name=$(git -C "$cwd" branch --show-current 2>/dev/null)
if [ -n "$branch_name" ]; then
    dirty=""
    if ! git -C "$cwd" diff --no-optional-locks --quiet 2>/dev/null || \
       ! git -C "$cwd" diff --no-optional-locks --cached --quiet 2>/dev/null; then
        dirty="*"
    fi
    git_str=" ${branch_name}${dirty}"
fi

# --- Time/date: HH:MM MM/DD ---
datetime_str="$(date '+%H:%M %m/%d')"

# --- Model: shorten display name ---
model_raw=$(echo "$input" | jq -r '.model.display_name // empty')
model_str=""
if [ -n "$model_raw" ]; then
    # Strip leading "Claude " then abbreviate first word
    short="${model_raw#Claude }"
    # Map known names to compact labels
    case "$short" in
        "Opus 4"*)    short="O${short#Opus }" ;;
        "Sonnet 4"*)  short="S${short#Sonnet }" ;;
        "Haiku 4"*)   short="H${short#Haiku }" ;;
        "Opus 3"*)    short="O${short#Opus }" ;;
        "Sonnet 3"*)  short="S${short#Sonnet }" ;;
        "Haiku 3"*)   short="H${short#Haiku }" ;;
        *)            short=$(echo "$short" | sed 's/[Cc]laude //g') ;;
    esac
    model_str=" $short"
fi

# --- Session name (only when set) ---
session_str=""
session_name=$(echo "$input" | jq -r '.session_name // empty')
if [ -n "$session_name" ]; then
    session_str=" \"${session_name}\""
fi

# --- Context: used% + raw in/out tokens ---
ctx_str=""
used_pct=$(echo "$input" | jq -r '.context_window.used_percentage // empty')
in_tok=$(echo "$input" | jq -r '.context_window.current_usage.input_tokens // empty')
out_tok=$(echo "$input" | jq -r '.context_window.current_usage.output_tokens // empty')
if [ -n "$used_pct" ]; then
    pct_val=$(printf '%.0f' "$used_pct")
    tok_part=""
    if [ -n "$in_tok" ] && [ -n "$out_tok" ]; then
        # Format as compact: 1234 -> 1.2k, 12345 -> 12k
        fmt_tok() {
            local n=$1
            if [ "$n" -ge 1000 ]; then
                printf '%.0fk' "$(echo "scale=1; $n/1000" | bc)"
            else
                printf '%d' "$n"
            fi
        }
        in_fmt=$(fmt_tok "$in_tok")
        out_fmt=$(fmt_tok "$out_tok")
        tok_part=" ${in_fmt}/${out_fmt}"
    fi
    ctx_str=" ${pct_val}%${tok_part}"
fi

# --- Effort level ---
effort_str=""
effort_raw=$(echo "$input" | jq -r '.effort.level // empty')
if [ -n "$effort_raw" ]; then
    case "$effort_raw" in
        low)    effort_str=" lo" ;;
        medium) effort_str=" md" ;;
        high)   effort_str=" hi" ;;
        xhigh)  effort_str=" xhi" ;;
        max)    effort_str=" max" ;;
        *)      effort_str=" ${effort_raw}" ;;
    esac
fi

# --- Output style (skip "default") ---
style_str=""
style_raw=$(echo "$input" | jq -r '.output_style.name // empty')
if [ -n "$style_raw" ] && [ "${style_raw,,}" != "default" ]; then
    style_str=" ${style_raw}"
fi

# --- Thinking indicator ---
thinking_str=""
thinking=$(echo "$input" | jq -r '.thinking.enabled // false')
if [ "$thinking" = "true" ]; then
    thinking_str=" Th"
fi

# Assemble:
# green: dir
# cyan:  git branch (+ dirty *)
# purple:[time date]
# blue:  model
# white: session name, ctx, effort, style
# cyan:  thinking
printf "${txtgrn}%s${txtrst}${txtcyn}%s${txtrst} ${txtpur}[%s]${txtrst}${txtblu}%s${txtrst}${txtwht}%s%s%s%s${txtrst}${txtcyn}%s${txtrst}\n" \
    "$dir_str" \
    "$git_str" \
    "$datetime_str" \
    "$model_str" \
    "$session_str" \
    "$ctx_str" \
    "$effort_str" \
    "$style_str" \
    "$thinking_str"