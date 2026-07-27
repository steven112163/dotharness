#!/usr/bin/env bats
# Behavior tests for bin/ckBuild's multi-arch CLI handling: accumulating
# multiple gfx... tokens into one ";"-joined ARCH, validating that list, and
# passing it through to cmake-ck-dev.sh as a single shell word (regression
# test for a heredoc-quoting bug where an unquoted $ARCH would let the remote
# bash -c parse ";" as a statement separator instead of a literal character).
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
EOF
    chmod +x "$FAKE_REPO/script/cmake-ck-dev.sh"

    cat >"$TMPDIR_TEST/stubbin/ninja" <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
    chmod +x "$TMPDIR_TEST/stubbin/ninja"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

@test "ckBuild joins multiple gfx tokens and passes them as one quoted arg to cmake-ck-dev.sh" {
    run bash -c "
        export PATH=\"$TMPDIR_TEST/stubbin:\$PATH\"
        MODE=direct GPU=0 REPO='$FAKE_REPO' '$CKBUILD' gfx942 gfx950 gfx1250 --scratch
    "
    [ "$status" -eq 0 ]
    [ -f "$CMAKE_LOG" ]
    grep -qx "gfx942;gfx950;gfx1250" "$CMAKE_LOG"
    # Exactly one arg carries the arch list, not three separate words.
    [ "$(grep -c '^gfx' "$CMAKE_LOG")" -eq 1 ]
}

@test "ckBuild rejects a malformed arch inside a multi-arch list before running anything" {
    # "gfx" (no trailing digits) still matches the gfx* CLI branch, so it lands
    # in ARCH rather than becoming a ninja target — exercising the multi-arch
    # validator rather than a bogus-target no-op.
    run bash -c "
        export PATH=\"$TMPDIR_TEST/stubbin:\$PATH\"
        MODE=direct GPU=0 REPO='$FAKE_REPO' '$CKBUILD' gfx942 gfx --scratch
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"invalid arch list"* ]]
    [ ! -f "$CMAKE_LOG" ]
}

@test "ckBuild still builds a single arch unchanged" {
    run bash -c "
        export PATH=\"$TMPDIR_TEST/stubbin:\$PATH\"
        MODE=direct GPU=0 REPO='$FAKE_REPO' '$CKBUILD' gfx942 --scratch
    "
    [ "$status" -eq 0 ]
    [ -f "$CMAKE_LOG" ]
    grep -qx "gfx942" "$CMAKE_LOG"
    [ "$(grep -c '^gfx' "$CMAKE_LOG")" -eq 1 ]
}
