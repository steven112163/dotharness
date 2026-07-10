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

    # The Codex-specific install must live inside the `command -v codex` guard,
    # bounded to the guard body so a move outside it would fail this test.
    codex_guard=$(awk '/if command -v codex &>\/dev\/null; then/,/echo "  skipped \(codex not found\)"/' "$SETUP_SH")
    run grep -qF 'graphify install --platform codex' <<<"$codex_guard"
    [ "$status" -eq 0 ]
}

@test "playwright-cli and graphify installs degrade to a warning on failure" {
    run grep -qF 'warn: playwright-cli install failed' "$SETUP_SH"
    [ "$status" -eq 0 ]

    run grep -qF 'warn: graphify install failed' "$SETUP_SH"
    [ "$status" -eq 0 ]

    run grep -qF 'warn: graphify install --platform codex failed' "$SETUP_SH"
    [ "$status" -eq 0 ]
}

@test "global gitignore file is symlinked and core.excludesFile is registered" {
    run [ -f "${BATS_TEST_DIRNAME}/../../gitignore_global" ]
    [ "$status" -eq 0 ]

    run grep -qF "link \"\$REPO_DIR/gitignore_global\" \"\$target_excludes_file\"" "$SETUP_SH"
    [ "$status" -eq 0 ]

    run grep -qF "git config --global core.excludesFile \"\$target_excludes_file\"" "$SETUP_SH"
    [ "$status" -eq 0 ]
}
