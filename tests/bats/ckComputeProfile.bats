#!/usr/bin/env bats
# Behavior tests for _venv_basename_ok and _venv_under_root_ok in
# bin/ckComputeProfile: the two checks that gate a VENV= override before its
# rm -rf reinstall path can run. Pure string logic, so each function is
# extracted from the script (sourcing the whole script would run its
# top-level dispatch) rather than needing a fake REPO/GPU/backend.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../../bin/ckComputeProfile"
}

ok() {
    bash -c "$(awk '/^_venv_basename_ok\(\)/,/^}/' "$SCRIPT"); _venv_basename_ok '$1'"
}

under() {
    bash -c "$(awk '/^_venv_under_root_ok\(\)/,/^}/' "$SCRIPT"); _venv_under_root_ok '$1' '$2' '$3'"
}

@test "accepts the default venv path" {
    run ok "$HOME/rocprof-compute-venv"
    [ "$status" -eq 0 ]
}

@test "accepts a suffixed override" {
    run ok "$HOME/rocprof-compute-venv-gfx942"
    [ "$status" -eq 0 ]
}

@test "rejects an empty path" {
    run ok ""
    [ "$status" -eq 1 ]
}

@test "rejects root" {
    run ok "/"
    [ "$status" -eq 1 ]
}

@test "rejects a bare HOME typo" {
    run ok "$HOME"
    [ "$status" -eq 1 ]
}

@test "rejects a differently named directory" {
    run ok "$HOME/some-other-dir"
    [ "$status" -eq 1 ]
}

@test "rejects a path whose basename escapes via .." {
    run ok "$HOME/rocprof-compute-venv/../etc"
    [ "$status" -eq 1 ]
}

@test "accepts a venv under HOME" {
    run under "$HOME/rocprof-compute-venv" "$HOME" "/some/repo"
    [ "$status" -eq 0 ]
}

@test "accepts a venv under REPO" {
    run under "/some/repo/rocprof-compute-venv" "$HOME" "/some/repo"
    [ "$status" -eq 0 ]
}

@test "rejects a venv outside both HOME and REPO" {
    run under "/other/rocprof-compute-venv" "$HOME" "/some/repo"
    [ "$status" -eq 1 ]
}

@test "rejects a lookalike sibling of HOME" {
    run under "${HOME}-evil/rocprof-compute-venv" "$HOME" "/some/repo"
    [ "$status" -eq 1 ]
}

@test "opens the shared venv lock fd read-write, not write-only" {
    # Regression guard: over NFS, flock -s (LOCK_SH) on a write-only fd fails
    # with "Bad file descriptor" (NFS emulates flock via POSIX locks, which
    # require read access for a shared lock). `<>` avoids that; `>` does not.
    # shellcheck disable=SC2016 # the $LOCK below is a literal regex match, not an expansion
    run grep -qE '^exec \{venv_lock_fd\}<>"\$LOCK"' "$SCRIPT"
    [ "$status" -eq 0 ]
}
