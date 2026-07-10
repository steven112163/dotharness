#!/usr/bin/env bats
# Behavioral checks on setup.sh's playwright-cli/graphify/gitignore wiring.
# setup.sh as a whole mutates real system state and can't be run end-to-end
# here, but each block below is self-contained enough to extract and run
# against stubbed tools / an isolated git config, exercising real control
# flow instead of just grepping for literal strings.

setup() {
    SETUP_SH="${BATS_TEST_DIRNAME}/../../setup.sh"
    STUB_BIN="$BATS_TEST_TMPDIR/bin"
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

stub() {
    local name="$1" exit_code="$2"
    # #!/bin/sh (an absolute path) so the shebang resolves without a PATH
    # lookup — STUB_BIN deliberately excludes bash/sh for isolation.
    printf '#!/bin/sh\nexit %s\n' "$exit_code" >"$STUB_BIN/$name"
    chmod +x "$STUB_BIN/$name"
}

@test "playwright-cli: skipped when npm is absent" {
    block=$(extract_block '^# --- playwright-cli' '^fi$')
    run env PATH="$STUB_BIN" "$BASH_BIN" -c "$block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped (npm not found)"* ]]
}

@test "playwright-cli: ok when npm/playwright-cli install succeed" {
    stub npm 0
    stub playwright-cli 0
    block=$(extract_block '^# --- playwright-cli' '^fi$')
    run env PATH="$STUB_BIN" "$BASH_BIN" -c "$block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok  playwright-cli"* ]]
}

@test "playwright-cli: warns instead of aborting when install fails" {
    stub npm 0
    stub playwright-cli 1
    block=$(extract_block '^# --- playwright-cli' '^fi$')
    run env PATH="$STUB_BIN" "$BASH_BIN" -c "set -euo pipefail; $block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"warn: playwright-cli install failed"* ]]
}

@test "graphify (Claude): skipped when pipx is absent" {
    block=$(extract_block '^# --- graphify \\(codebase' '^fi$')
    run env PATH="$STUB_BIN" HOME="$BATS_TEST_TMPDIR" "$BASH_BIN" -c "$block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped (pipx not found)"* ]]
}

@test "graphify (Claude): ok when pipx/graphify install succeed" {
    stub pipx 0
    stub graphify 0
    block=$(extract_block '^# --- graphify \\(codebase' '^fi$')
    run env PATH="$STUB_BIN" HOME="$BATS_TEST_TMPDIR" "$BASH_BIN" -c "$block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok  graphify"* ]]
}

@test "graphify (Claude): warns instead of aborting when install fails" {
    stub pipx 0
    stub graphify 1
    block=$(extract_block '^# --- graphify \\(codebase' '^fi$')
    run env PATH="$STUB_BIN" HOME="$BATS_TEST_TMPDIR" "$BASH_BIN" -c "set -euo pipefail; $block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"warn: graphify install failed"* ]]
}

@test "graphify (Codex): skipped when graphify is absent" {
    block=$(extract_block '^    # graphify: Codex needs' '^    fi$')
    run env PATH="$STUB_BIN" "$BASH_BIN" -c "$block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skipped (graphify not found)"* ]]
}

@test "graphify (Codex): warns instead of aborting when the codex install fails" {
    stub graphify 1
    block=$(extract_block '^    # graphify: Codex needs' '^    fi$')
    run env PATH="$STUB_BIN" "$BASH_BIN" -c "set -euo pipefail; $block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"warn: graphify install --platform codex failed"* ]]
}

@test "core.excludesFile: left alone when already pointed elsewhere" {
    local git_config_global="$BATS_TEST_TMPDIR/gitconfig"
    GIT_CONFIG_GLOBAL="$git_config_global" git config --global core.excludesFile "/some/other/path"
    block=$(extract_block '^existing_excludes_file=' '^fi$')
    run env GIT_CONFIG_GLOBAL="$git_config_global" target_excludes_file="$BATS_TEST_TMPDIR/.gitignore_global" bash -c "$block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"skip core.excludesFile (already set to /some/other/path)"* ]]
    [ "$(GIT_CONFIG_GLOBAL="$git_config_global" git config --global core.excludesFile)" = "/some/other/path" ]
}

@test "core.excludesFile: set when unconfigured" {
    local git_config_global="$BATS_TEST_TMPDIR/gitconfig"
    block=$(extract_block '^existing_excludes_file=' '^fi$')
    run env GIT_CONFIG_GLOBAL="$git_config_global" target_excludes_file="$BATS_TEST_TMPDIR/.gitignore_global" bash -c "$block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"set core.excludesFile"* ]]
    [ "$(GIT_CONFIG_GLOBAL="$git_config_global" git config --global core.excludesFile)" = "$BATS_TEST_TMPDIR/.gitignore_global" ]
}

@test "core.excludesFile: warns instead of aborting when git config write fails" {
    stub git 1
    block=$(extract_block '^existing_excludes_file=' '^fi$')
    run env PATH="$STUB_BIN:$PATH" target_excludes_file="/x" bash -c "set -euo pipefail; $block"
    [ "$status" -eq 0 ]
    [[ "$output" == *"warn: could not set core.excludesFile"* ]]
}

@test "global gitignore file is symlinked in setup.sh" {
    run [ -f "${BATS_TEST_DIRNAME}/../../gitignore_global" ]
    [ "$status" -eq 0 ]

    run grep -qF "link \"\$REPO_DIR/gitignore_global\" \"\$target_excludes_file\"" "$SETUP_SH"
    [ "$status" -eq 0 ]
}
