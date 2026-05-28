#!/bin/bash
# Anti-sycophancy hook: detect confirmatory language in user prompts
# and inject a system reminder to respond critically.
# Based on ArXiv 2602.23971 "Ask Don't Tell" principle.

input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt // empty')

if [ -z "$prompt" ]; then
    exit 0
fi

prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')

confirmatory=false

# Confirmation-seeking patterns
for pattern in \
    "right?" \
    "correct?" \
    "isn't it?" \
    "aren't they?" \
    "don't you think?" \
    "wouldn't you agree?" \
    "should be fine" \
    "no problem" \
    "no issues" \
    "looks good" \
    "makes sense" \
    "am i right" \
    "is that right" \
    "is that correct" \
    "that's correct" \
    "that works" \
    "good enough"; do
    if echo "$prompt_lower" | grep -qF "$pattern"; then
        confirmatory=true
        break
    fi
done

if [ "$confirmatory" = true ]; then
    cat <<'ENDJSON'
{"systemMessage": "The user's message contains confirmatory language seeking validation. Do NOT default to agreement. Instead: (1) identify potential problems, edge cases, or incorrect assumptions, (2) present counterarguments before agreeing, (3) only confirm if you have evidence the claim is correct. Cite sources for any factual claims."}
ENDJSON
fi
