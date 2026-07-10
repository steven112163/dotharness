#!/usr/bin/env bats
# Static checks on setup.sh's Codex skills wiring. setup.sh mutates real
# system state (plugins, MCP registration, hooks), so it is not safe to
# execute in a test; these assert the script's structure via grep instead.

setup() {
    SETUP_SH="${BATS_TEST_DIRNAME}/../../setup.sh"
}

@test "link_skills_to is defined once and used by both Claude and Codex sections" {
    run grep -c '^link_skills_to()' "$SETUP_SH"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]

    run grep -c "link_skills_to \"\$CLAUDE_DIR/skills\"" "$SETUP_SH"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]

    run grep -c "link_skills_to \"\$AGENTS_DIR/skills\"" "$SETUP_SH"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}

@test "Codex skills section does not symlink from CLAUDE_DIR" {
    # Isolate the Codex block (from its header to the next top-level '# ---' section).
    codex_block=$(awk '/^# --- Codex CLI/,0' "$SETUP_SH")
    skills_block=$(awk '/  # Skills: Codex reads/,/^$/' <<<"$codex_block")
    run grep -qF 'CLAUDE_DIR' <<<"$skills_block"
    [ "$status" -ne 0 ]
}

@test "ck-profile MCP check inspects claude mcp get output for both command and args" {
    run grep -c "grep -qF \"\$venv_dir/bin/python3\" <<<\"\$ckprofile_mcp_info\"" "$SETUP_SH"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]

    run grep -c "grep -qF \"\$REPO_DIR/lib/ck-profile-mcp/server.py\" <<<\"\$ckprofile_mcp_info\"" "$SETUP_SH"
    [ "$status" -eq 0 ]
    [ "$output" -eq 1 ]
}
