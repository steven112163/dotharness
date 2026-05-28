#!/bin/bash
# PostToolUse hook: scan edited files for hardcoded secrets.

input=$(cat)
file=$(echo "$input" | jq -r '.tool_input.file_path // .tool_response.filePath // empty')

if [ -z "$file" ] || [ ! -f "$file" ]; then
    exit 0
fi

# Skip binary files and non-code files
case "${file##*.}" in
    png|jpg|jpeg|gif|bmp|ico|svg|woff|woff2|ttf|eot|pdf|zip|tar|gz|o|so|a|pyc)
        exit 0
        ;;
esac

findings=""

# AWS keys
if grep -qE 'AKIA[0-9A-Z]{16}' "$file" 2>/dev/null; then
    findings="${findings}AWS access key detected. "
fi

# Generic API keys / secrets in assignment patterns
if grep -qEi '(api_key|api_secret|secret_key|private_key|access_token|auth_token)\s*=\s*["\x27][A-Za-z0-9+/=_-]{16,}["\x27]' "$file" 2>/dev/null; then
    findings="${findings}Possible hardcoded API key/secret. "
fi

# Private keys
if grep -qF 'BEGIN RSA PRIVATE KEY' "$file" 2>/dev/null || grep -qF 'BEGIN PRIVATE KEY' "$file" 2>/dev/null; then
    findings="${findings}Private key detected. "
fi

# Passwords in assignment patterns
if grep -qEi '(password|passwd|pwd)\s*=\s*["\x27][^"\x27]{4,}["\x27]' "$file" 2>/dev/null; then
    findings="${findings}Possible hardcoded password. "
fi

# GitHub/GitLab tokens
if grep -qE '(ghp_|gho_|ghu_|ghs_|ghr_)[A-Za-z0-9_]{36,}' "$file" 2>/dev/null; then
    findings="${findings}GitHub token detected. "
fi
if grep -qE 'glpat-[A-Za-z0-9_-]{20,}' "$file" 2>/dev/null; then
    findings="${findings}GitLab token detected. "
fi

if [ -n "$findings" ]; then
    cat <<ENDJSON
{"systemMessage": "Security scan warning for $file: $findings Review the file and remove any hardcoded secrets before committing."}
ENDJSON
fi
