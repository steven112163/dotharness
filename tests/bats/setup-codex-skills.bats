#!/usr/bin/env bats
# Static checks on setup.sh's Codex skills wiring. setup.sh mutates real
# system state (plugins, hooks), so it is not safe to execute in a test;
# these assert the script's structure via grep instead.

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
