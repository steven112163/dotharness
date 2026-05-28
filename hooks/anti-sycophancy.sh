#!/bin/bash
# Anti-sycophancy hook: rewrite confirmatory prompts into open-ended questions.
# Based on ArXiv 2602.23971 "Ask Don't Tell" principle.
#
# Instead of appending "think critically" to a biased prompt, this hook
# rewrites the prompt so the model never sees the leading framing.
# Uses stdout-based rewriting: whatever this hook prints to stdout
# becomes additional context that Claude sees.

input=$(cat)
prompt=$(echo "$input" | jq -r '.prompt // empty')

if [ -z "$prompt" ]; then
    exit 0
fi

prompt_lower=$(echo "$prompt" | tr '[:upper:]' '[:lower:]')

matched_pattern=""

# Detect confirmatory patterns (most specific first)
for pattern in \
    "wouldn't you agree" \
    "don't you think" \
    "is that correct" \
    "is that right" \
    "that's correct" \
    "am i right" \
    "should be fine" \
    "good enough" \
    "looks good" \
    "makes sense" \
    "no problem" \
    "no issues" \
    "that works" \
    "aren't they?" \
    "isn't it?" \
    "correct?" \
    "right?"; do
    if echo "$prompt_lower" | grep -qF "$pattern"; then
        matched_pattern="$pattern"
        break
    fi
done

if [ -z "$matched_pattern" ]; then
    exit 0
fi

# Strip the confirmatory tail from the prompt to extract the core claim.
# Use case-insensitive sed to remove the matched pattern and surrounding punctuation.
core=$(echo "$prompt" | sed -E "s/[,;. ]*${matched_pattern}[?.!]*\s*$//Ii" | sed 's/[[:space:]]*$//')

# If stripping left nothing useful, fall back to the original prompt.
if [ ${#core} -lt 5 ]; then
    core="$prompt"
fi

# Rewrite: present the core claim as an open-ended question.
# The model sees the rewritten version, not the original leading framing.
cat <<EOF
The user's original message was rewritten by an anti-sycophancy hook because it contained confirmatory language ("${matched_pattern}"). The original claim was:

"${core}"

Respond to this claim by:
1. First, identify what problems, risks, or incorrect assumptions exist.
2. Present counterarguments or edge cases before considering agreement.
3. Only confirm correctness if you have concrete evidence.
4. Cite sources for any factual claims.

Do NOT default to agreement. The user benefits more from honest criticism than from validation.
EOF
