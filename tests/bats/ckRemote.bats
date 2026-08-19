#!/usr/bin/env bats
# Unit tests for _split_pull_spec in bin/ckRemote: the "<src>[:<dest>]" split
# that lets `ckRemote pull` land a path under a different local name (e.g.
# pulling ck_profile_out from more than one server without one overwriting the
# other locally). Pure string logic, so the function is extracted from the
# script (sourcing the whole script would run its top-level dispatch) rather
# than needing a fake server/SSH setup — same pattern as
# tests/bats/ckComputeProfile.bats's _venv_basename_ok tests.

setup() {
    SCRIPT="${BATS_TEST_DIRNAME}/../../bin/ckRemote"
}

split() {
    bash -c "$(awk '/^_split_pull_spec\(\)/,/^}/' "$SCRIPT"); _split_pull_spec \"\$1\"" _ "$1"
}

@test "plain path with no colon: dest equals src" {
    run split "ck_profile_out"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "ck_profile_out" ]
    [ "${lines[1]}" = "ck_profile_out" ]
}

@test "src:dest form splits into two distinct values" {
    run split "ck_profile_out:ck_profile_out_server1"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "ck_profile_out" ]
    [ "${lines[1]}" = "ck_profile_out_server1" ]
}

@test "splits on the first colon only" {
    run split "a/b:c:d"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "a/b" ]
    [ "${lines[1]}" = "c:d" ]
}

@test "path with a single quote is not shell-interpolated" {
    run split "a'b"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "a'b" ]
    [ "${lines[1]}" = "a'b" ]
}

@test "option-like path does not get swallowed by echo" {
    run split "-n"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "-n" ]
    [ "${lines[1]}" = "-n" ]
}

@test "trailing colon: dest is empty" {
    run split "foo:"
    [ "$status" -eq 0 ]
    [ "$output" = "foo" ]
}

@test "leading colon: src is empty" {
    run split ":bar"
    [ "$status" -eq 0 ]
    [ "$output" = $'\nbar' ]
}
