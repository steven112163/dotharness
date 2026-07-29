#!/usr/bin/env bats
# Behavior tests for bin/ckBuild's `configure`/`build` subcommands: accumulating
# multiple gfx... tokens into one ";"-joined ARCH, validating that list, and
# passing it through to cmake-ck-dev.sh as a single shell word (regression
# test for a heredoc-quoting bug where an unquoted $ARCH would let the remote
# bash -c parse ";" as a statement separator instead of a literal character);
# plus the configure/build separation itself (build refuses an unconfigured tree).
#
# Runs the real bin/ckBuild against a fake CK project (a stub
# script/cmake-ck-dev.sh that records its argv, plus a stub ninja), MODE=direct
# so nothing touches docker/srun. No real GPU/toolchain needed.

setup() {
    CKBUILD="${BATS_TEST_DIRNAME}/../../bin/ckBuild"
    REPO_ROOT=$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)
    mkdir -p "$REPO_ROOT/tmp"
    TMPDIR_TEST=$(mktemp -d "$REPO_ROOT/tmp/ckBuild-bats-XXXXXX")

    FAKE_REPO="$TMPDIR_TEST/ck-repo"
    mkdir -p "$FAKE_REPO/script" "$TMPDIR_TEST/stubbin"
    touch "$FAKE_REPO/CMakeLists.txt"

    CMAKE_LOG="$TMPDIR_TEST/cmake-ck-dev-args.log"
    cat >"$FAKE_REPO/script/cmake-ck-dev.sh" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$CMAKE_LOG"
# Real cmake-ck-dev.sh writes build.ninja into the cwd (the build dir); the
# stub does too, so a later 'ckBuild build' sees a configured tree.
touch build.ninja
EOF
    chmod +x "$FAKE_REPO/script/cmake-ck-dev.sh"

    NINJA_LOG="$TMPDIR_TEST/ninja-args.log"
    cat >"$TMPDIR_TEST/stubbin/ninja" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$@" >"$NINJA_LOG"
exit 0
EOF
    chmod +x "$TMPDIR_TEST/stubbin/ninja"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

@test "ckBuild configure joins multiple gfx tokens and passes them as one quoted arg to cmake-ck-dev.sh" {
    run bash -c "
        export PATH=\"$TMPDIR_TEST/stubbin:\$PATH\"
        MODE=direct REPO='$FAKE_REPO' '$CKBUILD' configure gfx942 gfx950 gfx1250 --scratch
    "
    [ "$status" -eq 0 ]
    [ -f "$CMAKE_LOG" ]
    grep -qx "gfx942;gfx950;gfx1250" "$CMAKE_LOG"
    # Exactly one arg carries the arch list, not three separate words.
    [ "$(grep -c '^gfx' "$CMAKE_LOG")" -eq 1 ]
}

@test "ckBuild configure rejects a malformed arch inside a multi-arch list before running anything" {
    # "gfx" (no trailing digits) still matches the gfx* CLI branch, so it lands
    # in ARCH rather than being rejected as a stray target — exercising the
    # multi-arch validator rather than the target-rejection path.
    run bash -c "
        export PATH=\"$TMPDIR_TEST/stubbin:\$PATH\"
        MODE=direct REPO='$FAKE_REPO' '$CKBUILD' configure gfx942 gfx --scratch
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid arch list"* ]]
    [ ! -f "$CMAKE_LOG" ]
}

@test "ckBuild configure still configures a single arch unchanged" {
    run bash -c "
        export PATH=\"$TMPDIR_TEST/stubbin:\$PATH\"
        MODE=direct REPO='$FAKE_REPO' '$CKBUILD' configure gfx942 --scratch
    "
    [ "$status" -eq 0 ]
    [ -f "$CMAKE_LOG" ]
    grep -qx "gfx942" "$CMAKE_LOG"
    [ "$(grep -c '^gfx' "$CMAKE_LOG")" -eq 1 ]
}

@test "ckBuild configure builds a multi-arch fat binary from a pre-joined ARCH env var alone (no CLI tokens)" {
    run bash -c "
        export PATH=\"$TMPDIR_TEST/stubbin:\$PATH\"
        MODE=direct REPO='$FAKE_REPO' ARCH='gfx942;gfx950;gfx1250' '$CKBUILD' configure --scratch
    "
    [ "$status" -eq 0 ]
    [ -f "$CMAKE_LOG" ]
    grep -qx "gfx942;gfx950;gfx1250" "$CMAKE_LOG"
}

@test "ckBuild configure rejects a malformed ARCH env var (no CLI tokens)" {
    run bash -c "
        export PATH=\"$TMPDIR_TEST/stubbin:\$PATH\"
        MODE=direct REPO='$FAKE_REPO' ARCH='gfx942;;gfx950' '$CKBUILD' configure --scratch
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid arch list"* ]]
    [ ! -f "$CMAKE_LOG" ]
}

@test "ckBuild configure's first CLI gfx token overrides an inherited ARCH env var instead of accumulating onto it" {
    # ARCH=gfx942 in the environment plus a CLI gfx950 must resolve to gfx950
    # alone ("same as ARCH=" in usage_configure()), not silently merge into a
    # two-arch gfx942;gfx950 build the caller never asked for.
    run bash -c "
        export PATH=\"$TMPDIR_TEST/stubbin:\$PATH\"
        MODE=direct REPO='$FAKE_REPO' ARCH=gfx942 '$CKBUILD' configure gfx950 --scratch
    "
    [ "$status" -eq 0 ]
    [ -f "$CMAKE_LOG" ]
    # -x: the whole recorded arg is exactly "gfx950", not "gfx942;gfx950" or
    # any other value containing the overridden env arch.
    grep -qx "gfx950" "$CMAKE_LOG"
    [ "$(grep -c '^gfx' "$CMAKE_LOG")" -eq 1 ]
}

@test "ckBuild configure's second CLI gfx token still accumulates onto the first (multi-arch via repeated CLI args)" {
    run bash -c "
        export PATH=\"$TMPDIR_TEST/stubbin:\$PATH\"
        MODE=direct REPO='$FAKE_REPO' ARCH=gfx942 '$CKBUILD' configure gfx950 gfx1250 --scratch
    "
    [ "$status" -eq 0 ]
    [ -f "$CMAKE_LOG" ]
    grep -qx "gfx950;gfx1250" "$CMAKE_LOG"
    [ "$(grep -c '^gfx' "$CMAKE_LOG")" -eq 1 ]
}

@test "ckBuild configure rejects a stray positional target argument" {
    run bash -c "
        export PATH=\"$TMPDIR_TEST/stubbin:\$PATH\"
        MODE=direct REPO='$FAKE_REPO' '$CKBUILD' configure gfx942 my_target
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"'configure' takes no target arguments"* ]]
    [ ! -f "$CMAKE_LOG" ]
}

@test "ckBuild build refuses an unconfigured tree without touching ninja" {
    run bash -c "
        export PATH=\"$TMPDIR_TEST/stubbin:\$PATH\"
        MODE=direct REPO='$FAKE_REPO' '$CKBUILD' build my_target
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"is not configured"* ]]
    [[ "$output" == *"ckBuild configure"* ]]
    [ ! -f "$NINJA_LOG" ]
}

@test "ckBuild build rejects a gfx arch argument, pointing at configure" {
    run bash -c "
        export PATH=\"$TMPDIR_TEST/stubbin:\$PATH\"
        MODE=direct REPO='$FAKE_REPO' '$CKBUILD' build gfx942
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"'build' takes no arch arguments"* ]]
    [ ! -f "$NINJA_LOG" ]
}

@test "ckBuild build runs ninja on a target after configure ran" {
    run bash -c "
        export PATH=\"$TMPDIR_TEST/stubbin:\$PATH\"
        MODE=direct REPO='$FAKE_REPO' '$CKBUILD' configure gfx942 --scratch &&
        MODE=direct REPO='$FAKE_REPO' '$CKBUILD' build my_target
    "
    [ "$status" -eq 0 ]
    [ -f "$NINJA_LOG" ]
    grep -qx "my_target" "$NINJA_LOG"
}

@test "ckBuild build defaults to building all targets when none are given" {
    run bash -c "
        export PATH=\"$TMPDIR_TEST/stubbin:\$PATH\"
        MODE=direct REPO='$FAKE_REPO' '$CKBUILD' configure gfx942 --scratch &&
        MODE=direct REPO='$FAKE_REPO' '$CKBUILD' build
    "
    [ "$status" -eq 0 ]
    [ -f "$NINJA_LOG" ]
    # Only the -jN flag is passed through, no target name (ninja's own default:
    # build everything).
    [ "$(wc -l <"$NINJA_LOG")" -eq 1 ]
    grep -qE '^-j[0-9]+$' "$NINJA_LOG"
}

@test "ckBuild with no subcommand is a usage error" {
    run bash -c "
        export PATH=\"$TMPDIR_TEST/stubbin:\$PATH\"
        MODE=direct REPO='$FAKE_REPO' '$CKBUILD' gfx942
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown subcommand"* ]]
}
