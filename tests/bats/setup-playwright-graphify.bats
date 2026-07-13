#!/usr/bin/env bats
# Behavioral checks on setup.sh's playwright-cli/graphify/gitignore wiring.
# setup.sh as a whole mutates real system state and can't be run end-to-end
# here, but each block below is self-contained enough to extract and run
# against stubbed tools / an isolated git config, exercising real control
# flow instead of just grepping for literal strings.

setup() {
    SETUP_SH="${BATS_TEST_DIRNAME}/../../setup.sh"
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
    LOG_FILE="$BATS_TEST_TMPDIR/invocations.log"
    mkdir -p "$STUB_BIN"
    # Resolved once via the real PATH so exec still finds bash after PATH
    # is pinned to STUB_BIN alone (which deliberately excludes real tools).
    BASH_BIN="$(command -v bash)"
}

# Prints the lines of setup.sh from the first line matching $1 through the
# first subsequent line matching $2 (both inclusive).
extract_block() {
    awk -v start="$1" -v end="$2" '$0 ~ start {f=1} f {print} f && $0 ~ end {exit}' "$SETUP_SH"
}

# Stub $1 to exit $2, logging "$1 $*" to LOG_FILE so tests can assert on the
# exact invocation, not just that some command ran.
stub() {
    local name="$1" exit_code="$2"
    printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit %s\n' "$name" "$LOG_FILE" "$exit_code" \
        >"$STUB_BIN/$name"
    chmod +x "$STUB_BIN/$name"
}

# Simulates $1 (npm or pipx) reporting a fresh install location and
# pre-creates a working $3 binary there, so setup.sh's own PATH-prepend
# logic is what makes it resolvable — no cp/chmod needed under a PATH
# that's deliberately isolated from real coreutils.
stub_installer() {
    local name="$1" exit_code="$2" tool_bin="$3"
    local fresh_dir="$BATS_TEST_TMPDIR/fresh-$tool_bin"
    mkdir -p "$fresh_dir/bin"
    printf '#!/bin/sh\necho "%s $*" >> "%s"\nexit 0\n' "$tool_bin" "$LOG_FILE" \
        >"$fresh_dir/bin/$tool_bin"
    chmod +x "$fresh_dir/bin/$tool_bin"

    local locate_arg locate_output
    case "$name" in
    npm)
        locate_arg="prefix"
        locate_output="$fresh_dir"
        ;;
    pipx)
        locate_arg="environment"
        locate_output="$fresh_dir/bin"
        ;;
    *)
        echo "stub_installer: unknown installer '$name'" >&2
        return 1
        ;;
    esac
    {
        printf '#!/bin/sh\n'
        printf 'echo "%s $*" >> "%s"\n' "$name" "$LOG_FILE"
        # shellcheck disable=SC2016 # $1 expands in the generated /bin/sh script, not here
        printf 'if [ "$1" = "%s" ]; then echo "%s"; exit 0; fi\n' "$locate_arg" "$locate_output"
        printf 'exit %s\n' "$exit_code"
    } >"$STUB_BIN/$name"
    chmod +x "$STUB_BIN/$name"
}

@test "playwright-cli: skipped when npm is absent" {
    block=$(extract_block '^# --- playwright-cli' '^fi$')
    run env PATH="$STUB_BIN" "$BASH_BIN" -c "$block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped (npm not found)"* ]]
}

@test "playwright-cli: skips reinstall when already present" {
    stub npm 0
    stub playwright-cli 0
    block=$(extract_block '^# --- playwright-cli' '^fi$')
    run env PATH="$STUB_BIN" "$BASH_BIN" -c "$block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok  playwright-cli"* ]]
    [[ "$(cat "$LOG_FILE" 2>/dev/null)" != *"npm"* ]]
}

@test "playwright-cli: installs when missing and succeeds" {
    stub_installer npm 0 playwright-cli
    block=$(extract_block '^# --- playwright-cli' '^fi$')
    run env PATH="$STUB_BIN" "$BASH_BIN" -c "$block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok  playwright-cli"* ]]
    grep -qF "npm install -g @playwright/cli" "$LOG_FILE"
    grep -qF "playwright-cli install --skills" "$LOG_FILE"
    grep -qF "playwright-cli install-browser" "$LOG_FILE"
}

@test "playwright-cli: warns instead of aborting when install fails" {
    stub npm 1
    block=$(extract_block '^# --- playwright-cli' '^fi$')
    run env PATH="$STUB_BIN" "$BASH_BIN" -c "set -euo pipefail; $block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"warn: playwright-cli install failed"* ]]
    grep -qF "npm install -g @playwright/cli" "$LOG_FILE"
}

@test "graphify (Claude): skipped when pipx is absent" {
    block=$(extract_block '^# --- graphify \\(codebase' '^fi$')
    run env PATH="$STUB_BIN" HOME="$BATS_TEST_TMPDIR" "$BASH_BIN" -c "$block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped (pipx not found)"* ]]
}

@test "graphify (Claude): skips reinstall when already present" {
    stub pipx 0
    stub graphify 0
    block=$(extract_block '^# --- graphify \\(codebase' '^fi$')
    run env PATH="$STUB_BIN" HOME="$BATS_TEST_TMPDIR" "$BASH_BIN" -c "$block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok  graphify"* ]]
    [[ "$(cat "$LOG_FILE" 2>/dev/null)" != *"pipx"* ]]
}

@test "graphify (Claude): installs when missing and succeeds" {
    stub_installer pipx 0 graphify
    block=$(extract_block '^# --- graphify \\(codebase' '^fi$')
    run env PATH="$STUB_BIN" HOME="$BATS_TEST_TMPDIR" "$BASH_BIN" -c "$block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok  graphify"* ]]
    grep -qF "pipx install --force graphifyy" "$LOG_FILE"
    grep -qF "graphify install" "$LOG_FILE"
}

@test "graphify (Claude): warns instead of aborting when install fails" {
    stub pipx 1
    block=$(extract_block '^# --- graphify \\(codebase' '^fi$')
    run env PATH="$STUB_BIN" HOME="$BATS_TEST_TMPDIR" "$BASH_BIN" -c "set -euo pipefail; $block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"warn: graphify install failed"* ]]
    grep -qF "pipx install --force graphifyy" "$LOG_FILE"
}

@test "graphify (Codex): skipped when graphify is absent" {
    block=$(extract_block '^    # graphify: Codex needs' '^    fi$')
    run env PATH="$STUB_BIN" "$BASH_BIN" -c "$block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped (graphify not found)"* ]]
}

@test "graphify (Codex): installs and succeeds" {
    stub graphify 0
    block=$(extract_block '^    # graphify: Codex needs' '^    fi$')
    run env PATH="$STUB_BIN" "$BASH_BIN" -c "$block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok  graphify"* ]]
    grep -qF "graphify install --platform codex" "$LOG_FILE"
}

@test "graphify (Codex): warns instead of aborting when the codex install fails" {
    stub graphify 1
    block=$(extract_block '^    # graphify: Codex needs' '^    fi$')
    run env PATH="$STUB_BIN" "$BASH_BIN" -c "set -euo pipefail; $block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"warn: graphify install --platform codex failed"* ]]
    grep -qF "graphify install --platform codex" "$LOG_FILE"
}

@test "core.excludesFile: left alone when already pointed elsewhere" {
    local git_config_global="$BATS_TEST_TMPDIR/gitconfig"
    GIT_CONFIG_GLOBAL="$git_config_global" git config --global core.excludesFile "/some/other/path"
    block=$(extract_block '^existing_excludes_file=' '^fi$')
    run env GIT_CONFIG_GLOBAL="$git_config_global" target_excludes_file="$BATS_TEST_TMPDIR/.gitignore_global" \
        "$BASH_BIN" -c "link() { :; }; $block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skip core.excludesFile (already set to /some/other/path)"* ]]
    [ "$(GIT_CONFIG_GLOBAL="$git_config_global" git config --global core.excludesFile)" = "/some/other/path" ]
}

@test "core.excludesFile: set when unconfigured" {
    local git_config_global="$BATS_TEST_TMPDIR/gitconfig"
    block=$(extract_block '^existing_excludes_file=' '^fi$')
    run env GIT_CONFIG_GLOBAL="$git_config_global" target_excludes_file="$BATS_TEST_TMPDIR/.gitignore_global" \
        "$BASH_BIN" -c "link() { :; }; $block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"set core.excludesFile"* ]]
    [ "$(GIT_CONFIG_GLOBAL="$git_config_global" git config --global core.excludesFile)" = "$BATS_TEST_TMPDIR/.gitignore_global" ]
}

@test "core.excludesFile: warns instead of aborting when git config write fails" {
    stub git 1
    block=$(extract_block '^existing_excludes_file=' '^fi$')
    run env PATH="$STUB_BIN:$PATH" REPO_DIR="/repo" target_excludes_file="/x" \
        "$BASH_BIN" -c "link() { :; }; set -euo pipefail; $block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"warn: could not set core.excludesFile"* ]]
}

@test "global gitignore file is symlinked in setup.sh" {
    run [ -f "${BATS_TEST_DIRNAME}/../../gitignore_global" ]
    [ "$status" -eq 0 ]

    run grep -qF "link \"\$REPO_DIR/gitignore_global\" \"\$target_excludes_file\"" "$SETUP_SH"
    [ "$status" -eq 0 ]
}
