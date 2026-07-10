#!/usr/bin/env bats
# Static checks on setup.sh's playwright-cli/graphify/gitignore wiring.
# setup.sh mutates real system state (global npm/pipx packages, git config),
# so it is not safe to execute in a test; these assert structure via grep.

setup() {
    SETUP_SH="${BATS_TEST_DIRNAME}/../../setup.sh"
}

@test "playwright-cli is installed and its skills/browser are provisioned" {
    run grep -qF 'npm install -g @playwright/cli' "$SETUP_SH"
    [ "$status" -eq 0 ]

    run grep -qF 'playwright-cli install --skills' "$SETUP_SH"
    [ "$status" -eq 0 ]

    run grep -qF 'playwright-cli install-browser' "$SETUP_SH"
    [ "$status" -eq 0 ]
}

@test "graphify is installed for Claude and explicitly for Codex" {
    run grep -qF 'pipx install --force graphifyy' "$SETUP_SH"
    [ "$status" -eq 0 ]

    run grep -qF 'graphify install --platform codex' "$SETUP_SH"
    [ "$status" -eq 0 ]

    # The Codex-specific install must live inside the `command -v codex` guard,
    # not the top-level Claude section.
    codex_block=$(awk '/^# --- Codex CLI/,0' "$SETUP_SH")
    run grep -qF 'graphify install --platform codex' <<<"$codex_block"
    [ "$status" -eq 0 ]
}

@test "global gitignore file is symlinked and core.excludesFile is registered" {
    [ -f "${BATS_TEST_DIRNAME}/../../gitignore_global" ]

    run grep -qF 'gitignore_global' "$SETUP_SH"
    [ "$status" -eq 0 ]

    run grep -qF 'core.excludesFile' "$SETUP_SH"
    [ "$status" -eq 0 ]
}
