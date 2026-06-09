#!/usr/bin/env bats
# Behavior tests for hooks/block-dangerous.sh.
# The hook reads a tool-call JSON on stdin and exits 2 to block, 0 to allow.

setup() {
    HOOK="${BATS_TEST_DIRNAME}/../hooks/block-dangerous.sh"
}

# check <tool> <value>: feed the hook a tool-call payload and return its exit code.
# For Bash, <value> is the command; otherwise it is the file_path.
check() {
    local json
    if [ "$1" = "Bash" ]; then
        json=$(jq -nc --arg c "$2" '{tool_name:"Bash",tool_input:{command:$c}}')
    else
        json=$(jq -nc --arg t "$1" --arg f "$2" '{tool_name:$t,tool_input:{file_path:$f}}')
    fi
    printf '%s' "$json" | bash "$HOOK"
}

# --- Bash: dangerous commands are blocked (exit 2) ---

@test "blocks rm -rf with an absolute path" {
    run check Bash "rm -rf /home/styuan/foo"
    [ "$status" -eq 2 ]
}

@test "blocks rm -rf with a glob" {
    run check Bash "rm -rf *"
    [ "$status" -eq 2 ]
}

@test "blocks rm -rf on home" {
    run check Bash "rm -rf ~"
    [ "$status" -eq 2 ]
}

@test "blocks rm -rf on cwd" {
    run check Bash "rm -rf ."
    [ "$status" -eq 2 ]
}

@test "blocks rm with split -r -f flags and a path" {
    run check Bash "rm -r -f /home/x"
    [ "$status" -eq 2 ]
}

@test "blocks git push --force" {
    run check Bash "git push --force origin main"
    [ "$status" -eq 2 ]
}

@test "blocks git push -f" {
    run check Bash "git push -f"
    [ "$status" -eq 2 ]
}

@test "blocks git push --force-with-lease" {
    run check Bash "git push --force-with-lease"
    [ "$status" -eq 2 ]
}

@test "blocks git reset --hard" {
    run check Bash "git reset --hard HEAD~1"
    [ "$status" -eq 2 ]
}

@test "blocks git clean -fd" {
    run check Bash "git clean -fd"
    [ "$status" -eq 2 ]
}

@test "blocks DROP TABLE" {
    run check Bash 'psql -c "DROP TABLE users"'
    [ "$status" -eq 2 ]
}

@test "blocks redirect into .env" {
    run check Bash "echo x > .env"
    [ "$status" -eq 2 ]
}

@test "blocks redirect into /etc" {
    run check Bash "echo x > /etc/hosts"
    [ "$status" -eq 2 ]
}

@test "blocks redirect into /tmp" {
    run check Bash "echo x > /tmp/foo"
    [ "$status" -eq 2 ]
}

@test "blocks append into /var/tmp" {
    run check Bash "echo x >> /var/tmp/foo"
    [ "$status" -eq 2 ]
}

@test "blocks mkdir under /tmp" {
    run check Bash "mkdir /tmp/foo"
    [ "$status" -eq 2 ]
}

@test "blocks killall" {
    run check Bash "killall node"
    [ "$status" -eq 2 ]
}

# --- Bash: safe commands are allowed (exit 0) ---

@test "allows rm -rf of a bare relative target" {
    run check Bash "rm -rf build"
    [ "$status" -eq 0 ]
}

@test "allows a plain echo" {
    run check Bash "echo hello"
    [ "$status" -eq 0 ]
}

@test "allows a non-force git push" {
    run check Bash "git push origin main"
    [ "$status" -eq 0 ]
}

@test "allows redirect into the repo .claude/tmp" {
    run check Bash "echo x > .claude/tmp/foo"
    [ "$status" -eq 0 ]
}

@test "allows mkdir under the repo .claude/tmp" {
    run check Bash "mkdir .claude/tmp/foo"
    [ "$status" -eq 0 ]
}

@test "allows cat" {
    run check Bash "cat README.md"
    [ "$status" -eq 0 ]
}

# --- Write/Edit: sensitive destinations are blocked (exit 2) ---

@test "blocks Write to /tmp" {
    run check Write "/tmp/x.txt"
    [ "$status" -eq 2 ]
}

@test "blocks Write to /var/tmp" {
    run check Write "/var/tmp/x.txt"
    [ "$status" -eq 2 ]
}

@test "blocks Write to /etc" {
    run check Write "/etc/hosts"
    [ "$status" -eq 2 ]
}

@test "blocks Write inside .ssh" {
    run check Write "/home/styuan/.ssh/config"
    [ "$status" -eq 2 ]
}

@test "blocks Write to AWS credentials" {
    run check Write "/home/styuan/.aws/credentials"
    [ "$status" -eq 2 ]
}

@test "blocks Write to .env" {
    run check Write "/proj/.env"
    [ "$status" -eq 2 ]
}

@test "blocks Write to .env.local" {
    run check Write "/proj/.env.local"
    [ "$status" -eq 2 ]
}

@test "blocks Edit of a private SSH key" {
    run check Edit "/proj/id_rsa"
    [ "$status" -eq 2 ]
}

# --- Write/Edit: ordinary and example files are allowed (exit 0) ---

@test "allows Write to a normal source file" {
    run check Write "/proj/src/foo.cpp"
    [ "$status" -eq 0 ]
}

@test "allows Write to .env.example" {
    run check Write "/proj/.env.example"
    [ "$status" -eq 0 ]
}

@test "allows Write to .env.sample" {
    run check Write "/proj/.env.sample"
    [ "$status" -eq 0 ]
}
