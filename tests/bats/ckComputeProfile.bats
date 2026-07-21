#!/usr/bin/env bats
# Behavior tests for _venv_basename_ok in bin/ckComputeProfile: the allowlist
# that rejects a VENV= override before its rm -rf reinstall path can run.
# Pure string logic, so the function is extracted from the script (sourcing
# the whole script would run its top-level dispatch) rather than needing a
# fake REPO/GPU/backend.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../../bin/ckComputeProfile"
}

ok() {
    bash -c "$(awk '/^_venv_basename_ok\(\)/,/^}/' "$SCRIPT"); _venv_basename_ok '$1'"
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
