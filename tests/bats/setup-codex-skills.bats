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

@test "Codex skills section does not iterate over CLAUDE_DIR/skills" {
    # Isolate the Codex "Skills:" block (from its header to the next section's
    # header). $CLAUDE_DIR itself may legitimately appear here (stale-symlink
    # cleanup); the old bug specifically iterated "$CLAUDE_DIR/skills"/* as its
    # link source, so check for that exact pattern rather than the bare name.
    codex_block=$(awk '/^# --- Codex CLI/,0' "$SETUP_SH")
    skills_block=$(awk '/  # Skills: Codex reads/,/  # Rules: Codex reads/' <<<"$codex_block")
    [ -n "$skills_block" ]
    run grep -qF "\"\$CLAUDE_DIR/skills\"/*" <<<"$skills_block"
    [ "$status" -ne 0 ]
}

@test "ck-profile MCP check correctly requires both command and args to match" {
    # Pull the two-line condition verbatim out of setup.sh and run it against
    # synthetic `claude mcp get` output in a sandbox, rather than just asserting
    # the literal grep expressions exist in the source — this catches a
    # regression that weakens the && to || just as well as one that deletes a
    # line outright.
    condition=$(grep -A1 -F "if grep -qF \"\$venv_dir/bin/python3\"" "$SETUP_SH")
    [ -n "$condition" ]
    condition="${condition%; then}"

    run_condition() {
        bash -c "venv_dir=\$1; REPO_DIR=\$2; ckprofile_mcp_info=\$3
            $condition
            then echo MATCH; else echo NOMATCH; fi" _ "$1" "$2" "$3"
    }

    run run_condition /fake/venv /fake/repo $'Command: /fake/venv/bin/python3\nArgs: /fake/repo/lib/ck-profile-mcp/server.py'
    [ "$output" = MATCH ]

    run run_condition /fake/venv /fake/repo $'Command: /other/venv/bin/python3\nArgs: /fake/repo/lib/ck-profile-mcp/server.py'
    [ "$output" = NOMATCH ]

    run run_condition /fake/venv /fake/repo $'Command: /fake/venv/bin/python3\nArgs: /other/repo/lib/ck-profile-mcp/server.py'
    [ "$output" = NOMATCH ]
}
