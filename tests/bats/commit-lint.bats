#!/usr/bin/env bats
# Behavior tests for hooks/commit-lint.sh.
# The hook reads a tool-call JSON on stdin and exits 2 to deny a malformed
# commit message, 0 to allow or skip (non-commit, amend-reuse, no message).

setup() {
    HOOK="${BATS_TEST_DIRNAME}/../../hooks/commit-lint.sh"
}

# commit <command>: feed the hook a Bash tool-call with the given command.
commit() {
    jq -nc --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}' | bash "$HOOK"
}

# --- Conforming messages are allowed (exit 0) ---

@test "allows feat without scope" {
    run commit 'git commit -m "feat: add survey skill"'
    [ "$status" -eq 0 ]
}

@test "allows fix with scope" {
    run commit 'git commit -m "fix(setup): correct symlink path"'
    [ "$status" -eq 0 ]
}

@test "allows a single-quoted message" {
    run commit "git commit -m 'docs: update readme'"
    [ "$status" -eq 0 ]
}

@test "allows a conforming heredoc message" {
    # The literal $(cat <<'EOF' ...) is the command string the hook parses, not
    # something this test expands.
    # shellcheck disable=SC2016
    cmd=$(printf 'git commit -m "$(cat <<%sEOF%s\nfeat(web): add login\nEOF\n)"' "'" "'")
    run commit "$cmd"
    [ "$status" -eq 0 ]
}

# --- Malformed messages are denied (exit 2) ---

@test "denies a message with no type" {
    run commit 'git commit -m "Update files"'
    [ "$status" -eq 2 ]
}

@test "denies a wrong separator" {
    run commit 'git commit -m "feat - add login"'
    [ "$status" -eq 2 ]
}

@test "denies an unknown/uppercase type" {
    run commit 'git commit -m "Feat(web): add login"'
    [ "$status" -eq 2 ]
}

@test "denies uppercase subject after the colon" {
    run commit 'git commit -m "feat(web): Add login"'
    [ "$status" -eq 2 ]
}

@test "denies a trailing period" {
    run commit 'git commit -m "feat(web): add login."'
    [ "$status" -eq 2 ]
}

@test "denies a subject over 72 characters" {
    long=$(printf 'feat: %0.sx' $(seq 1 80))
    run commit "git commit -m \"$long\""
    [ "$status" -eq 2 ]
}

# --- Non-validating cases are skipped (exit 0) ---

@test "skips a non-commit git command" {
    run commit 'git status'
    [ "$status" -eq 0 ]
}

@test "skips amend that reuses the previous message" {
    run commit 'git commit --amend --no-edit'
    [ "$status" -eq 0 ]
}

@test "skips --allow-empty-message" {
    run commit 'git commit --allow-empty-message -m ""'
    [ "$status" -eq 0 ]
}

@test "skips a non-Bash tool call" {
    run bash -c 'jq -nc "{tool_name:\"Write\",tool_input:{file_path:\"/tmp/x\"}}" | bash "$1"' _ "$HOOK"
    [ "$status" -eq 0 ]
}
