#!/usr/bin/env bats
# Behavior tests for the shared dispatch/arch/root-finding helpers in
# bin/ckCommon: _dispatch_build_like, _dispatch_run_like,
# _resolve_arch_or_require, _find_ck_root/_require_ck_root.
#
# These stub out the lower-level primitives (_docker_run_local,
# _run_in_container, _srun_dispatch, _srun_overlap_dispatch, _ensure_image_tar,
# _hold_jobid) to verify the routing logic in isolation, and mock rocminfo via
# a fake PATH entry for the arch-probing tests. No real docker/srun/GPU needed.

setup() {
    CKCOMMON="${BATS_TEST_DIRNAME}/../../bin/ckCommon"
    REPO_ROOT=$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)
    mkdir -p "$REPO_ROOT/tmp"
    TMPDIR_TEST=$(mktemp -d "$REPO_ROOT/tmp/ckCommon-bats-XXXXXX")
    # Isolate from the real $HOME: a real ~/.config/ckdockersetup on the dev
    # machine running these tests must never leak in and trigger a real
    # docker build. Tests that exercise DOCKER_SETUP_CMD_FILE resolution set
    # it explicitly per-test, overriding this default.
    export DOCKER_SETUP_CMD_FILE="$TMPDIR_TEST/no-ckdockersetup-by-default"
}

teardown() {
    rm -rf "$TMPDIR_TEST"
}

# --- _dispatch_build_like: routes by MODE, no overlap attempt ---

@test "_dispatch_build_like on direct runs the program inline" {
    run bash -c "
        source '$CKCOMMON'
        MODE=direct
        _dispatch_build_like 0 '$TMPDIR_TEST' 'echo hello-direct'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello-direct"* ]]
}

@test "_dispatch_build_like on docker delegates to _docker_run_local" {
    run bash -c "
        source '$CKCOMMON'
        MODE=docker
        _docker_run_local() { echo \"docker_run_local:\$1:\$2:\$3\"; }
        _dispatch_build_like 1 /work prog
    "
    [ "$status" -eq 0 ]
    [ "$output" = "docker_run_local:1:/work:prog" ]
}

@test "_dispatch_build_like on srun ensures the image then srun-dispatches, no overlap" {
    run bash -c "
        source '$CKCOMMON'
        MODE=srun
        _ensure_image_tar() { return 0; }
        _run_in_container() { echo container-snippet; }
        _srun_overlap_dispatch() { echo 'ERROR: overlap must not be called for build-like dispatch' >&2; return 1; }
        _srun_dispatch() { echo \"srun_dispatch:\$1\"; }
        _dispatch_build_like 0 /work prog
    "
    [ "$status" -eq 0 ]
    [ "$output" = "srun_dispatch:container-snippet" ]
}

@test "_dispatch_build_like on direct runs the program with cwd set to workdir" {
    mkdir -p "$TMPDIR_TEST/workdir"
    run bash -c "
        source '$CKCOMMON'
        MODE=direct
        _dispatch_build_like 0 '$TMPDIR_TEST/workdir' 'pwd'
    "
    [ "$status" -eq 0 ]
    [ "$output" = "$TMPDIR_TEST/workdir" ]
}

@test "_dispatch_build_like on srun propagates gpu to the global GPU (no unbound var)" {
    run bash -u -c "
        source '$CKCOMMON'
        MODE=srun
        _ensure_image_tar() { return 0; }
        _run_in_container() { echo container-snippet; }
        srun() { echo \"srun-called:GPU=\$GPU:\$*\"; }
        _dispatch_build_like 0 /work prog
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"srun-called:GPU=0:"* ]]
}

@test "_dispatch_build_like on srun ignores an ambient GPU and uses the call-site gpu argument (no GPU-build-node feature)" {
    run bash -c "
        source '$CKCOMMON'
        MODE=srun
        GPU=1
        _ensure_image_tar() { return 0; }
        _run_in_container() { echo container-snippet; }
        srun() { echo \"srun-called:GPU=\$GPU:\$*\"; }
        _dispatch_build_like 0 /work prog
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"srun-called:GPU=0:"* ]]
}

@test "_dispatch_build_like on an unknown MODE exits 1" {
    run bash -c "
        source '$CKCOMMON'
        MODE=bogus
        _dispatch_build_like 0 /work prog
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown MODE"* ]]
}

@test "_dispatch_build_like on srun does not leak a mutated GPU past the call" {
    run bash -c "
        source '$CKCOMMON'
        MODE=srun
        unset GPU
        _ensure_image_tar() { return 0; }
        _run_in_container() { echo container-snippet; }
        _srun_dispatch() { return 0; }
        _dispatch_build_like 0 /work prog
        echo \"GPU=[\${GPU:-unset}]\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"GPU=[unset]"* ]]
}

@test "_dispatch_build_like on srun omits --time (one-shot builds use the partition default)" {
    run bash -c "
        source '$CKCOMMON'
        MODE=srun
        SRUN_TIME=02:00:00
        _ensure_image_tar() { return 0; }
        _run_in_container() { echo container-snippet; }
        srun() { echo \"srun-args:\$*\"; }
        _dispatch_build_like 0 /work prog
    "
    [ "$status" -eq 0 ]
    [[ "$output" != *"--time"* ]]
}

@test "_dispatch_build_like on srun does not leak the cleared SRUN_TIME past the call" {
    run bash -c "
        source '$CKCOMMON'
        MODE=srun
        SRUN_TIME=02:00:00
        _ensure_image_tar() { return 0; }
        _run_in_container() { echo container-snippet; }
        _srun_dispatch() { return 0; }
        _dispatch_build_like 0 /work prog
        echo \"SRUN_TIME=[\$SRUN_TIME]\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"SRUN_TIME=[02:00:00]"* ]]
}

@test "_dispatch_build_like on direct aborts a multi-line remote_prog entirely when cd fails" {
    # A single-line remote_prog would pass either way (&& gates it fine); the
    # bug this guards against only shows up with a second line, which used to
    # run unconditionally (in the original cwd) even after a failed cd.
    run bash -c "
        source '$CKCOMMON'
        MODE=direct
        remote_prog=\$'echo first-should-not-run\necho second-should-not-run'
        _dispatch_build_like 0 /no/such/dir \"\$remote_prog\"
    "
    [ "$status" -ne 0 ]
    [[ "$output" != *"should-not-run"* ]]
}

# --- _dispatch_run_like: srun prefers overlap, falls back to fresh dispatch ---

@test "_dispatch_run_like on direct runs the program inline" {
    run bash -c "
        source '$CKCOMMON'
        MODE=direct
        _dispatch_run_like 1 '$TMPDIR_TEST' 'echo hello-direct-run'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"hello-direct-run"* ]]
}

@test "_dispatch_run_like on docker delegates to _docker_run_local" {
    run bash -c "
        source '$CKCOMMON'
        MODE=docker
        _docker_run_local() { echo \"docker_run_local:\$1:\$2:\$3\"; }
        _dispatch_run_like 0 /work prog
    "
    [ "$status" -eq 0 ]
    [ "$output" = "docker_run_local:0:/work:prog" ]
}

@test "_dispatch_run_like on srun overlaps into a running holder when present" {
    run bash -c "
        source '$CKCOMMON'
        MODE=srun
        _ensure_image_tar() { return 0; }
        _run_in_container() { echo snippet; }
        _hold_jobid() { echo 12345; }
        _srun_overlap_dispatch() { echo \"overlap:\$1\"; }
        _srun_dispatch() { echo \"fresh:\$1\"; }
        _dispatch_run_like 1 /work prog
    "
    [ "$status" -eq 0 ]
    [ "$output" = "overlap:snippet" ]
}

@test "_dispatch_run_like on srun falls back to a fresh dispatch with no holder" {
    run bash -c "
        source '$CKCOMMON'
        MODE=srun
        _ensure_image_tar() { return 0; }
        _run_in_container() { echo snippet; }
        _hold_jobid() { echo ''; }
        _srun_overlap_dispatch() { echo \"overlap:\$1\"; }
        _srun_dispatch() { echo \"fresh:\$1\"; }
        _dispatch_run_like 1 /work prog
    "
    [ "$status" -eq 0 ]
    [ "$output" = "fresh:snippet" ]
}

@test "_dispatch_run_like's real srun fresh-dispatch keeps --time (holder-bound, unlike build-like)" {
    run bash -c "
        source '$CKCOMMON'
        MODE=srun
        GPU=1
        GRES='gpu:gfx942-mi300x:1'
        ARCH=gfx942
        _ensure_image_tar() { return 0; }
        _run_in_container() { echo container-snippet; }
        _hold_jobid() { echo ''; }
        srun() { echo \"srun-args:\$*\" >&2; }
        _dispatch_run_like 1 /work prog
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"--time=02:00:00"* ]]
}

@test "_dispatch_run_like's real srun fresh-dispatch path does not pollute captured stdout" {
    run bash -c "
        source '$CKCOMMON'
        MODE=srun
        GPU=1
        GRES='gpu:gfx942-mi300x:1'
        _ensure_image_tar() { return 0; }
        _run_in_container() { echo 'payload-only'; }
        _hold_jobid() { echo ''; }
        srun() { shift \$#; echo payload-only; }
        captured=\$(_dispatch_run_like 1 /work prog)
        echo \"captured=[\$captured]\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"captured=[payload-only]"* ]]
}

@test "_dispatch_run_like's real srun overlap path does not pollute captured stdout" {
    run bash -c "
        source '$CKCOMMON'
        MODE=srun
        _ensure_image_tar() { return 0; }
        _run_in_container() { echo 'payload-only'; }
        _hold_jobid() { echo 12345; }
        srun() { shift \$#; echo payload-only; }
        captured=\$(_dispatch_run_like 1 /work prog)
        echo \"captured=[\$captured]\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"captured=[payload-only]"* ]]
}

@test "_dispatch_run_like on direct runs the program with cwd set to workdir" {
    mkdir -p "$TMPDIR_TEST/workdir"
    run bash -c "
        source '$CKCOMMON'
        MODE=direct
        _dispatch_run_like 1 '$TMPDIR_TEST/workdir' 'pwd'
    "
    [ "$status" -eq 0 ]
    [ "$output" = "$TMPDIR_TEST/workdir" ]
}

@test "_dispatch_run_like on direct aborts a multi-line remote_prog entirely when cd fails" {
    run bash -c "
        source '$CKCOMMON'
        MODE=direct
        remote_prog=\$'echo first-should-not-run\necho second-should-not-run'
        _dispatch_run_like 1 /no/such/dir \"\$remote_prog\"
    "
    [ "$status" -ne 0 ]
    [[ "$output" != *"should-not-run"* ]]
}

@test "_dispatch_run_like on srun (no holder) propagates gpu to the global GPU (no unbound var)" {
    run bash -u -c "
        source '$CKCOMMON'
        MODE=srun
        GRES='gpu:gfx942-mi300x:1'
        _ensure_image_tar() { return 0; }
        _run_in_container() { echo container-snippet; }
        _hold_jobid() { echo ''; }
        srun() { echo \"srun-called:GPU=\$GPU:\$*\"; }
        _dispatch_run_like 1 /work prog
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"srun-called:GPU=1:"* ]]
}

@test "_dispatch_run_like on srun ignores an ambient GPU and uses the call-site gpu argument" {
    run bash -c "
        source '$CKCOMMON'
        MODE=srun
        GPU=0
        GRES='gpu:gfx942-mi300x:1'
        _ensure_image_tar() { return 0; }
        _run_in_container() { echo container-snippet; }
        _hold_jobid() { echo ''; }
        srun() { echo \"srun-called:GPU=\$GPU:\$*\"; }
        _dispatch_run_like 1 /work prog
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"srun-called:GPU=1:"* ]]
}

@test "_dispatch_run_like's real srun retries and excludes a node that lacks the repo" {
    run bash -c "
        source '$CKCOMMON'
        MODE=srun
        GPU=1
        GRES='gpu:gfx942-mi300x:1'
        MAX_NODE_RETRIES=2
        _ensure_image_tar() { return 0; }
        _run_in_container() { echo container-snippet; }
        _hold_jobid() { echo ''; }
        callfile='$TMPDIR_TEST/srun-calls'
        : >\"\$callfile\"
        srun() {
            echo \"\$*\" >>\"\$callfile\"
            shift \$#
            if [ \$(wc -l <\"\$callfile\") -eq 1 ]; then
                echo 'ERROR: repo not visible on badnode1 (/repo missing).' >&2
                return 75
            fi
            echo ok-payload
            return 0
        }
        captured=\$(_dispatch_run_like 1 /work prog)
        rc=\$?
        echo \"rc=[\$rc] captured=[\$captured] calls=[\$(wc -l <\"\$callfile\")]\"
        echo \"second-call-args=[\$(sed -n 2p \"\$callfile\")]\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=[0] captured=[ok-payload] calls=[2]"* ]]
    [[ "$output" == *"excluding: badnode1"* ]]
    [[ "$output" == *"second-call-args=["*"--exclude=badnode1"*"]"* ]]
}

@test "_dispatch_run_like's real srun retry loop survives being called as a bare statement under set -euo pipefail (ckRun's invocation pattern)" {
    run bash -c "
        set -euo pipefail
        source '$CKCOMMON'
        MODE=srun
        GPU=1
        GRES='gpu:gfx942-mi300x:1'
        MAX_NODE_RETRIES=2
        _ensure_image_tar() { return 0; }
        _run_in_container() { echo container-snippet; }
        _hold_jobid() { echo ''; }
        callfile='$TMPDIR_TEST/srun-calls-sete'
        : >\"\$callfile\"
        srun() {
            echo \"\$*\" >>\"\$callfile\"
            shift \$#
            if [ \$(wc -l <\"\$callfile\") -eq 1 ]; then
                echo 'ERROR: repo not visible on badnode1 (/repo missing).' >&2
                return 75
            fi
            echo ok-payload
            return 0
        }
        _dispatch_run_like 1 /work prog
        echo \"reached-after-dispatch calls=[\$(wc -l <\"\$callfile\")]\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ok-payload"* ]]
    [[ "$output" == *"reached-after-dispatch calls=[2]"* ]]
}

@test "_dispatch_run_like on an unknown MODE exits 1" {
    run bash -c "
        source '$CKCOMMON'
        MODE=bogus
        _dispatch_run_like 1 /work prog
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"unknown MODE"* ]]
}

# --- DOCKER_SETUP_CMD default resolution: read from DOCKER_SETUP_CMD_FILE
# (same config-file strategy as ckRemote's server list), same safety property
# as a missing $CK_REMOTE_CONF: file absent (the default, fresh checkout) ->
# empty, no derived image. These source ckCommon fresh per test (the
# resolution runs at source time, not inside a function). ---

@test "DOCKER_SETUP_CMD defaults to empty when DOCKER_SETUP_CMD_FILE is absent (safe default)" {
    run bash -c "
        DOCKER_SETUP_CMD_FILE='$TMPDIR_TEST/no-such-file'
        source '$CKCOMMON'
        echo \"[\$DOCKER_SETUP_CMD]\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "DOCKER_SETUP_CMD is read from DOCKER_SETUP_CMD_FILE when present" {
    printf 'line-one\nline-two\n' >"$TMPDIR_TEST/setup-cmd"
    run bash -c "
        DOCKER_SETUP_CMD_FILE='$TMPDIR_TEST/setup-cmd'
        source '$CKCOMMON'
        echo \"[\$DOCKER_SETUP_CMD]\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"line-one"* ]]
    [[ "$output" == *"line-two"* ]]
}

@test "an explicit empty DOCKER_SETUP_CMD opts out even when DOCKER_SETUP_CMD_FILE exists" {
    echo 'echo should-not-be-used' >"$TMPDIR_TEST/setup-cmd"
    run bash -c "
        DOCKER_SETUP_CMD_FILE='$TMPDIR_TEST/setup-cmd'
        DOCKER_SETUP_CMD=''
        source '$CKCOMMON'
        echo \"[\$DOCKER_SETUP_CMD]\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

@test "an explicit DOCKER_SETUP_CMD overrides DOCKER_SETUP_CMD_FILE content" {
    echo 'echo should-not-be-used' >"$TMPDIR_TEST/setup-cmd"
    run bash -c "
        DOCKER_SETUP_CMD_FILE='$TMPDIR_TEST/setup-cmd'
        DOCKER_SETUP_CMD='echo custom'
        source '$CKCOMMON'
        echo \"[\$DOCKER_SETUP_CMD]\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "[echo custom]" ]
}

@test "an existing but unreadable DOCKER_SETUP_CMD_FILE fails loudly instead of silently defaulting to empty" {
    [ "$(id -u)" -eq 0 ] && skip "root ignores file permissions"
    echo 'echo should-not-be-used' >"$TMPDIR_TEST/setup-cmd"
    chmod 000 "$TMPDIR_TEST/setup-cmd"
    run bash -c "
        DOCKER_SETUP_CMD_FILE='$TMPDIR_TEST/setup-cmd'
        source '$CKCOMMON'
    "
    chmod 644 "$TMPDIR_TEST/setup-cmd"
    [ "$status" -ne 0 ]
    [[ "$output" == *"exists but could not be read"* ]]
}

@test "a DOCKER_SETUP_CMD_FILE that is a directory fails loudly instead of silently defaulting to empty" {
    mkdir -p "$TMPDIR_TEST/setup-cmd-dir"
    run bash -c "
        DOCKER_SETUP_CMD_FILE='$TMPDIR_TEST/setup-cmd-dir'
        source '$CKCOMMON'
    "
    [ "$status" -ne 0 ]
    [[ "$output" == *"exists but could not be read"* ]]
}

@test "sourcing ckCommon again after fixing an unreadable DOCKER_SETUP_CMD_FILE succeeds instead of silently no-op'ing" {
    [ "$(id -u)" -eq 0 ] && skip "root ignores file permissions"
    echo 'echo should-not-be-used' >"$TMPDIR_TEST/setup-cmd"
    chmod 000 "$TMPDIR_TEST/setup-cmd"
    run bash -c "
        DOCKER_SETUP_CMD_FILE='$TMPDIR_TEST/setup-cmd'
        source '$CKCOMMON' || true
        chmod 644 '$TMPDIR_TEST/setup-cmd'
        source '$CKCOMMON'
        echo \"[\$DOCKER_SETUP_CMD]\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"should-not-be-used"* ]]
}

@test "an unreadable DOCKER_SETUP_CMD_FILE is not consulted at all when DOCKER_SETUP_CMD is already set (env still wins)" {
    [ "$(id -u)" -eq 0 ] && skip "root ignores file permissions"
    echo 'echo should-not-be-used' >"$TMPDIR_TEST/setup-cmd"
    chmod 000 "$TMPDIR_TEST/setup-cmd"
    run bash -c "
        DOCKER_SETUP_CMD_FILE='$TMPDIR_TEST/setup-cmd'
        DOCKER_SETUP_CMD='echo custom'
        source '$CKCOMMON'
        echo \"[\$DOCKER_SETUP_CMD]\"
    "
    chmod 644 "$TMPDIR_TEST/setup-cmd"
    [ "$status" -eq 0 ]
    [ "$output" = "[echo custom]" ]
}

# --- _docker_setup_image_tag / _ensure_docker_setup_image: bake DOCKER_SETUP_CMD
# into a derived image via docker commit, once per unique (IMAGE,
# DOCKER_SETUP_CMD) pair. All docker calls stubbed; no real docker needed. ---

@test "_docker_setup_image_tag is deterministic and changes when DOCKER_SETUP_CMD changes" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        USER=alice
        DOCKER_SETUP_CMD=cmd-a
        docker() { return 1; }
        t1=\$(_docker_setup_image_tag)
        t1b=\$(_docker_setup_image_tag)
        DOCKER_SETUP_CMD=cmd-b
        t2=\$(_docker_setup_image_tag)
        echo \"t1=[\$t1] t1b=[\$t1b] t2=[\$t2]\"
        [ \"\$t1\" = \"\$t1b\" ]
        [ \"\$t1\" != \"\$t2\" ]
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"t1=[test-image-alice-"* ]]
}

@test "_docker_setup_image_tag lowercases \$USER (docker repo names must be lowercase)" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        USER=Alice
        DOCKER_SETUP_CMD=cmd-a
        docker() { return 1; }
        _docker_setup_image_tag
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "test-image-alice-"* ]]
}

@test "_docker_setup_image_tag changes when the resolved image ID changes even though IMAGE/DOCKER_SETUP_CMD do not (rolling-tag safety)" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        USER=alice
        DOCKER_SETUP_CMD=cmd-a
        docker() { echo 'sha256:aaa'; return 0; }
        t1=\$(_docker_setup_image_tag)
        docker() { echo 'sha256:bbb'; return 0; }
        t2=\$(_docker_setup_image_tag)
        echo \"t1=[\$t1] t2=[\$t2]\"
        [ \"\$t1\" != \"\$t2\" ]
    "
    [ "$status" -eq 0 ]
}

@test "_docker_setup_image_tag is stable across the not-yet-pulled to pulled transition (cold-host regression)" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        USER=alice
        DOCKER_SETUP_CMD=cmd-a
        pulled=0
        docker() {
            case \"\$1\" in
            pull) pulled=1; return 0 ;;
            image)
                [ \"\$pulled\" -eq 1 ] && { echo 'sha256:fixed'; return 0; }
                return 1
                ;;
            esac
        }
        t1=\$(_docker_setup_image_tag)
        t2=\$(_docker_setup_image_tag)
        echo \"t1=[\$t1] t2=[\$t2]\"
        [ \"\$t1\" = \"\$t2\" ]
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"t1=[test-image-alice-"* ]]
}

@test "_ensure_docker_setup_image echoes IMAGE unchanged when DOCKER_SETUP_CMD is empty (default, no-op)" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        DOCKER_SETUP_CMD=''
        docker() { echo 'ERROR: docker must not be called' >&2; return 1; }
        _ensure_docker_setup_image
    "
    [ "$status" -eq 0 ]
    [ "$output" = "test-image" ]
}

@test "_ensure_docker_setup_image builds and commits a derived image when the tag is missing" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        DOCKER_SETUP_CMD='echo setup'
        ACCT_DIR='$TMPDIR_TEST/acct'
        callfile='$TMPDIR_TEST/docker-calls'
        : >\"\$callfile\"
        docker() {
            echo \"\$*\" >>\"\$callfile\"
            [ \"\$1\" = image ] && return 1
            return 0
        }
        tag=\$(_ensure_docker_setup_image)
        echo \"tag=[\$tag]\"
        cat \"\$callfile\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"tag=[test-image-"*"]"* ]]
    [[ "$output" == *"image inspect"* ]]
    [[ "$output" == *"run -u 0 --name ck-setup-"* ]]
    [[ "$output" == *"commit ck-setup-"* ]]
    [[ "$output" == *"rm -f ck-setup-"* ]]
}

@test "_ensure_docker_setup_image reuses an existing derived image without rebuilding" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        DOCKER_SETUP_CMD='echo setup'
        ACCT_DIR='$TMPDIR_TEST/acct'
        callfile='$TMPDIR_TEST/docker-calls'
        : >\"\$callfile\"
        docker() {
            echo \"\$*\" >>\"\$callfile\"
            [ \"\$1\" = image ] && return 0
            return 1
        }
        tag=\$(_ensure_docker_setup_image)
        echo \"tag=[\$tag]\"
        echo \"calls=[\$(wc -l <\"\$callfile\")]\"
    "
    [ "$status" -eq 0 ]
    # 2, not 1: one docker image inspect from _docker_setup_image_tag's own
    # digest resolution, one from the tag-exists check. No build/commit/rm.
    [[ "$output" == *"calls=[2]"* ]]
}

@test "_ensure_docker_setup_image does not leak DOCKER_SETUP_CMD's own stdout into the captured tag" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        DOCKER_SETUP_CMD='echo setup'
        ACCT_DIR='$TMPDIR_TEST/acct'
        docker() {
            case \"\$1\" in
            image) return 1 ;;
            run)
                echo 'Collecting rocm...'
                echo 'Successfully installed rocm'
                return 0
                ;;
            commit) return 0 ;;
            rm) return 0 ;;
            esac
        }
        tag=\$(_ensure_docker_setup_image 2>/dev/null)
        echo \"tag=[\$tag]\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == "tag=[test-image-"*"]" ]]
}

@test "_ensure_docker_setup_image returns nonzero and does not echo a tag when docker commit fails" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        DOCKER_SETUP_CMD='echo setup'
        ACCT_DIR='$TMPDIR_TEST/acct'
        callfile='$TMPDIR_TEST/docker-calls'
        : >\"\$callfile\"
        docker() {
            echo \"\$*\" >>\"\$callfile\"
            case \"\$1\" in
            image) return 1 ;;
            run) return 0 ;;
            commit) return 1 ;;
            rm) return 0 ;;
            esac
        }
        tag=\$(_ensure_docker_setup_image 2>/dev/null)
        rc=\$?
        echo \"tag=[\$tag]\"
        cat \"\$callfile\"
        exit \$rc
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"tag=[]"* ]]
    [[ "$output" == *"commit ck-setup-"* ]]
    [[ "$output" == *"rm -f ck-setup-"* ]]
}

@test "_ensure_docker_setup_image aborts and never commits when DOCKER_SETUP_CMD fails partway (bash -euo pipefail exercised for real)" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        DOCKER_SETUP_CMD='false; echo ok'
        ACCT_DIR='$TMPDIR_TEST/acct'
        callfile='$TMPDIR_TEST/docker-calls'
        : >\"\$callfile\"
        docker() {
            echo \"\$*\" >>\"\$callfile\"
            case \"\$1\" in
            image) return 1 ;;
            run)
                # Actually execute the trailing 'bash -euo pipefail -c CMD'
                # (the last 5 args) instead of an unconditional stub return,
                # so this exercises bash's real -e semantics: 'false' aborts
                # the script before 'echo ok' ever runs.
                \"\${@: -5}\"
                ;;
            commit) echo 'ERROR: commit must not be called after a failed setup' >&2; return 1 ;;
            rm) return 0 ;;
            esac
        }
        _ensure_docker_setup_image
        rc=\$?
        cat \"\$callfile\"
        exit \$rc
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"bash -euo pipefail -c false; echo ok"* ]]
    [[ "$output" == *"rm -f ck-setup-"* ]]
    [[ "$output" != *"commit ck-setup-"* ]]
}

@test "_ensure_docker_setup_image removes a stale leftover container before building (self-heal)" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        DOCKER_SETUP_CMD='echo setup'
        ACCT_DIR='$TMPDIR_TEST/acct'
        callfile='$TMPDIR_TEST/docker-calls'
        : >\"\$callfile\"
        docker() {
            echo \"\$*\" >>\"\$callfile\"
            case \"\$1\" in
            image) return 1 ;;
            run) return 0 ;;
            commit) return 0 ;;
            rm) return 0 ;;
            esac
        }
        _ensure_docker_setup_image >/dev/null
        cat \"\$callfile\"
    "
    [ "$status" -eq 0 ]
    rm_line=$(grep -n '^rm -f ck-setup-' <<<"$output" | head -1 | cut -d: -f1)
    run_line=$(grep -n '^run -u 0' <<<"$output" | head -1 | cut -d: -f1)
    [ -n "$rm_line" ]
    [ -n "$run_line" ]
    [ "$rm_line" -lt "$run_line" ]
}

@test "_ensure_docker_setup_image skips the self-heal removal when no stale container exists" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        DOCKER_SETUP_CMD='echo setup'
        ACCT_DIR='$TMPDIR_TEST/acct'
        callfile='$TMPDIR_TEST/docker-calls'
        : >\"\$callfile\"
        docker() {
            echo \"\$*\" >>\"\$callfile\"
            case \"\$1\" in
            image) return 1 ;;
            container) return 1 ;;
            run) return 0 ;;
            commit) return 0 ;;
            rm) return 0 ;;
            esac
        }
        tag=\$(_ensure_docker_setup_image)
        echo \"tag=[\$tag]\"
        cat \"\$callfile\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"container inspect ck-setup-"* ]]
    # Exactly one rm -f: the unconditional post-commit cleanup. The self-heal
    # rm before run is skipped since docker container inspect said absent.
    rm_count=$(grep -c '^rm -f ck-setup-' <<<"$output")
    [ "$rm_count" -eq 1 ]
}

@test "_ensure_docker_setup_image aborts with a specific error when removing a real stale container fails" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        DOCKER_SETUP_CMD='echo setup'
        ACCT_DIR='$TMPDIR_TEST/acct'
        docker() {
            case \"\$1\" in
            image) return 1 ;;
            container) return 0 ;;
            rm) return 1 ;;
            run) echo 'ERROR: run must not be called when stale-container removal failed' >&2; return 1 ;;
            commit) echo 'ERROR: commit must not be called when stale-container removal failed' >&2; return 1 ;;
            esac
        }
        _ensure_docker_setup_image
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"failed to remove stale container"* ]]
}

@test "_ensure_docker_setup_image warns but still succeeds when the final container-removal fails (tag already committed)" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        DOCKER_SETUP_CMD='echo setup'
        ACCT_DIR='$TMPDIR_TEST/acct'
        docker() {
            case \"\$1\" in
            image) return 1 ;;
            container) return 1 ;;
            run) return 0 ;;
            commit) return 0 ;;
            rm) return 1 ;;
            esac
        }
        _ensure_docker_setup_image
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"test-image-"* ]]
    [[ "$output" == *"WARNING"* ]]
}

@test "_ensure_docker_setup_image's container name is tag-scoped, not a bare PID (collision safety)" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        USER=alice
        DOCKER_SETUP_CMD='echo setup'
        ACCT_DIR='$TMPDIR_TEST/acct'
        docker() {
            case \"\$1\" in
            image) return 1 ;;
            run) echo \"container=\$5\"; return 0 ;;
            commit) return 0 ;;
            rm) return 0 ;;
            esac
        }
        _ensure_docker_setup_image >/dev/null
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"container=ck-setup-test-image-alice-"* ]]
}

@test "_ensure_docker_setup_image does not commit and returns nonzero when DOCKER_SETUP_CMD fails" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        DOCKER_SETUP_CMD=false
        ACCT_DIR='$TMPDIR_TEST/acct'
        callfile='$TMPDIR_TEST/docker-calls'
        : >\"\$callfile\"
        docker() {
            echo \"\$*\" >>\"\$callfile\"
            case \"\$1\" in
            image) return 1 ;;
            run) return 1 ;;
            rm) return 0 ;;
            commit) echo 'ERROR: commit must not be called after a failed setup' >&2; return 1 ;;
            esac
        }
        _ensure_docker_setup_image
        rc=\$?
        cat \"\$callfile\"
        exit \$rc
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"rm -f ck-setup-"* ]]
    [[ "$output" != *"commit"* ]]
}

# --- _ACCT_SETUP_SH: merges the image's own /etc/passwd|group with the real
# host getent entry at our uid/gid, so LDAP/SSSD (or any) uid resolves to a
# name inside the container. `docker` stubbed to fake `cat /etc/passwd`/
# `/etc/group` output for the image-fetch calls only; the real host `getent`
# still runs (it's not a docker call), so assertions use the real caller's
# $(id -u)/$(id -un). ---

@test "_ACCT_SETUP_SH replaces an image-baked user that collides with the host uid, instead of shadowing it (WSL whoami bug)" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        ACCT_DIR='$TMPDIR_TEST/acct'
        docker() {
            case \"\${@: -1}\" in
            /etc/passwd) printf 'root:x:0:0:root:/root:/bin/bash\nubuntu:x:%s:%s:Ubuntu:/home/ubuntu:/bin/bash\n' \"\$(id -u)\" \"\$(id -g)\" ;;
            /etc/group) printf 'root:x:0:\nubuntu:x:%s:\n' \"\$(id -g)\" ;;
            esac
        }
        _ACCT_GPU=0 _ACCT_FLAGS=''
        eval \"\$_ACCT_SETUP_SH\"
        cat \"\$ACCT_DIR/passwd-\$(id -u)\"
        cat \"\$ACCT_DIR/group-\$(id -g)\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"$(id -un):x:$(id -u):$(id -g):"* ]]
    [[ "$output" != *"ubuntu:x:$(id -u):"* ]]
    [[ "$output" != *"ubuntu:x:$(id -g):"* ]]
}

@test "_ACCT_SETUP_SH appends the host's getent entry when the image has no user at that uid (regression, no collision)" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        ACCT_DIR='$TMPDIR_TEST/acct'
        docker() {
            case \"\${@: -1}\" in
            /etc/passwd) printf 'root:x:0:0:root:/root:/bin/bash\n' ;;
            /etc/group) printf 'root:x:0:\n' ;;
            esac
        }
        _ACCT_GPU=0 _ACCT_FLAGS=''
        eval \"\$_ACCT_SETUP_SH\"
        cat \"\$ACCT_DIR/passwd-\$(id -u)\"
        cat \"\$ACCT_DIR/group-\$(id -g)\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"root:x:0:0:root:/root:/bin/bash"* ]]
    [[ "$output" == *"$(id -un):x:$(id -u):$(id -g):"* ]]
}

@test "_docker_run_local dispatches against IMAGE unchanged when DOCKER_SETUP_CMD is empty (regression)" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        DOCKER_SETUP_CMD=''
        REPO=/repo
        ACCT_DIR='$TMPDIR_TEST/acct'
        CCACHE_DIR='$TMPDIR_TEST/ccache'
        callfile='$TMPDIR_TEST/docker-calls'
        : >\"\$callfile\"
        docker() { echo \"\$*\" >>\"\$callfile\"; return 0; }
        _docker_run_local 0 /repo 'echo hi' >/dev/null
        cat \"\$callfile\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" != *"image inspect"* ]]
    [[ "$output" != *"-u 0"* ]]
    [[ "$output" == *"test-image bash -c"* ]]
}

@test "_docker_run_local dispatches against the derived tag, not IMAGE, when DOCKER_SETUP_CMD is set" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        DOCKER_SETUP_CMD='echo setup'
        REPO=/repo
        ACCT_DIR='$TMPDIR_TEST/acct'
        CCACHE_DIR='$TMPDIR_TEST/ccache'
        callfile='$TMPDIR_TEST/docker-calls'
        : >\"\$callfile\"
        docker() {
            echo \"\$*\" >>\"\$callfile\"
            [ \"\$1\" = image ] && return 0
            return 0
        }
        _docker_run_local 0 /repo 'echo hi' >/dev/null
        cat \"\$callfile\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" != *"-u 0"* ]]
    [[ "$output" != *"commit"* ]]
    [[ "$output" != *"test-image cat"* ]]
    [[ "$output" != *"test-image bash -c"* ]]
    [[ "$output" == *"bash -c"* ]]
}

@test "_dispatch_build_like on srun resolves the derived setup image before ensuring the tarball" {
    run bash -c "
        source '$CKCOMMON'
        MODE=srun
        IMAGE=test-image
        DOCKER_SETUP_CMD='echo setup'
        _ensure_docker_setup_image() { echo derived-tag; }
        _ensure_image_tar() { echo \"ensure_image_tar:\$1\"; }
        _run_in_container() { echo \"run_in_container:IMAGE=\$IMAGE\"; }
        _srun_dispatch() { echo \"srun_dispatch:\$1\"; }
        _dispatch_build_like 0 /work prog
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ensure_image_tar:derived-tag"* ]]
    [[ "$output" == *"srun_dispatch:run_in_container:IMAGE=derived-tag"* ]]
}

@test "_dispatch_run_like on srun resolves the derived setup image before ensuring the tarball" {
    run bash -c "
        source '$CKCOMMON'
        MODE=srun
        IMAGE=test-image
        DOCKER_SETUP_CMD='echo setup'
        _ensure_docker_setup_image() { echo derived-tag; }
        _ensure_image_tar() { echo \"ensure_image_tar:\$1\"; }
        _run_in_container() { echo \"run_in_container:IMAGE=\$IMAGE\"; }
        _hold_jobid() { echo ''; }
        _srun_dispatch() { echo \"srun_dispatch:\$1\"; }
        _dispatch_run_like 1 /work prog
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ensure_image_tar:derived-tag"* ]]
    [[ "$output" == *"srun_dispatch:run_in_container:IMAGE=derived-tag"* ]]
}

# --- _resolve_arch_or_require: hard error on srun, probe on direct/docker ---

@test "_resolve_arch_or_require errors on srun with no arch" {
    run bash -c "
        source '$CKCOMMON'
        ARCH=''
        _resolve_arch_or_require srun
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"no GPU to probe"* ]]
}

@test "_resolve_arch_or_require leaves an already-set ARCH untouched on srun" {
    run bash -c "
        source '$CKCOMMON'
        ARCH=gfx950
        _resolve_arch_or_require srun
        echo \"ARCH=\$ARCH\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARCH=gfx950"* ]]
}

@test "_resolve_arch_or_require probes rocminfo inline on direct" {
    mkdir -p "$TMPDIR_TEST/bin"
    cat >"$TMPDIR_TEST/bin/rocminfo" <<'EOF'
#!/usr/bin/env bash
echo "  Name: gfx942"
EOF
    chmod +x "$TMPDIR_TEST/bin/rocminfo"
    run bash -c "
        export PATH='$TMPDIR_TEST/bin:$PATH'
        source '$CKCOMMON'
        ARCH=''
        _resolve_arch_or_require direct
        echo \"rc=\$?\"
        echo \"ARCH=\$ARCH\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0"* ]]
    [[ "$output" == *"ARCH=gfx942"* ]]
}

@test "_resolve_arch_or_require fails on direct when the probe finds nothing" {
    mkdir -p "$TMPDIR_TEST/bin"
    run bash -c "
        export PATH='$TMPDIR_TEST/bin'
        source '$CKCOMMON'
        ARCH=''
        _resolve_arch_or_require direct
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not detect GPU arch"* ]]
}

@test "_resolve_arch_or_require probes rocminfo inside the container on docker" {
    run bash -c "
        source '$CKCOMMON'
        REPO=/repo
        ARCH=''
        _docker_run_local() { echo gfx942; }
        _resolve_arch_or_require docker
        echo \"rc=\$?\"
        echo \"ARCH=\$ARCH\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0"* ]]
    [[ "$output" == *"ARCH=gfx942"* ]]
}

@test "_resolve_arch_or_require fails on docker when the container probe finds nothing" {
    run bash -c "
        source '$CKCOMMON'
        REPO=/repo
        ARCH=''
        _docker_run_local() { return 0; }
        _resolve_arch_or_require docker
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"could not detect GPU arch"* ]]
}

# --- _validate_arch / _resolve_arch_or_require: reject malformed --arch input ---

@test "_validate_arch accepts a well-formed gfx arch" {
    run bash -c "
        source '$CKCOMMON'
        _validate_arch gfx942
    "
    [ "$status" -eq 0 ]
}

@test "_validate_arch rejects a shell-metacharacter payload" {
    run bash -c "
        source '$CKCOMMON'
        _validate_arch 'gfx942;touch pwned'
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid arch"* ]]
}

@test "_validate_arch rejects a path-traversal payload" {
    run bash -c "
        source '$CKCOMMON'
        _validate_arch '../../etc/passwd'
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid arch"* ]]
}

@test "_resolve_arch_or_require rejects an already-set malformed ARCH on srun" {
    run bash -c "
        source '$CKCOMMON'
        ARCH='gfx942;touch pwned'
        _resolve_arch_or_require srun
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid arch"* ]]
}

@test "_resolve_arch_or_require with a malformed ARCH stays non-fatal under || true" {
    run bash -c "
        source '$CKCOMMON'
        ARCH='gfx942;touch pwned'
        _resolve_arch_or_require srun 2>/dev/null || true
        echo survived
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"survived"* ]]
}

@test "_resolve_arch_or_require clears ARCH on a malformed value so best-effort callers can't leak it" {
    run bash -c "
        source '$CKCOMMON'
        ARCH='gfx942;touch pwned'
        _resolve_arch_or_require srun 2>/dev/null || true
        echo \"ARCH=[\$ARCH]\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"ARCH=[]"* ]]
}

# --- _validate_arch_list: ckBuild's multi-arch fat-binary validator ---

@test "_validate_arch_list accepts a single arch" {
    run bash -c "
        source '$CKCOMMON'
        _validate_arch_list gfx942
    "
    [ "$status" -eq 0 ]
}

@test "_validate_arch_list accepts a multi-arch list" {
    run bash -c "
        source '$CKCOMMON'
        _validate_arch_list 'gfx942;gfx950;gfx1250'
    "
    [ "$status" -eq 0 ]
}

@test "_validate_arch_list accepts exactly 8 archs (the documented cap)" {
    run bash -c "
        source '$CKCOMMON'
        _validate_arch_list 'gfx900;gfx901;gfx902;gfx903;gfx904;gfx905;gfx906;gfx907'
    "
    [ "$status" -eq 0 ]
}

@test "_validate_arch_list rejects 9 archs (one past the documented cap)" {
    run bash -c "
        source '$CKCOMMON'
        _validate_arch_list 'gfx900;gfx901;gfx902;gfx903;gfx904;gfx905;gfx906;gfx907;gfx908'
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid arch list"* ]]
}

@test "_validate_arch_list rejects an empty list" {
    run bash -c "
        source '$CKCOMMON'
        _validate_arch_list ''
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid arch list"* ]]
}

@test "_validate_arch_list rejects a malformed entry inside an otherwise-valid list" {
    run bash -c "
        source '$CKCOMMON'
        _validate_arch_list 'gfx942;bogus'
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid arch list"* ]]
}

@test "_validate_arch_list rejects a trailing separator" {
    run bash -c "
        source '$CKCOMMON'
        _validate_arch_list 'gfx942;'
    "
    [ "$status" -eq 1 ]
}

@test "_validate_arch_list rejects a leading separator" {
    run bash -c "
        source '$CKCOMMON'
        _validate_arch_list ';gfx942'
    "
    [ "$status" -eq 1 ]
}

@test "_validate_arch_list rejects a doubled separator" {
    run bash -c "
        source '$CKCOMMON'
        _validate_arch_list 'gfx942;;gfx950'
    "
    [ "$status" -eq 1 ]
}

@test "_validate_arch_list rejects a shell-metacharacter payload" {
    run bash -c "
        source '$CKCOMMON'
        _validate_arch_list 'gfx942;touch pwned'
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid arch list"* ]]
}

@test "_gres_for_arch returns empty for a multi-arch list" {
    # No exact-string case in _gres_for_arch matches a ;-joined list, so a
    # multi-arch ARCH falls through to the existing "GPU=1 but no GRES
    # mapping" error in _srun_dispatch rather than guessing an arch to map.
    run bash -c "
        source '$CKCOMMON'
        echo \"[\$(_gres_for_arch 'gfx942;gfx950')]\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "[]" ]
}

# --- _run_in_container: the docker/srun escaping layer must not unquote a
# multi-arch ARCH. ckBuild.bats only exercises MODE=direct (no extra escaping
# layer); this covers the layer docker and srun both add on top of the
# heredoc-quoted $ARCH, without needing a full docker/srun mock. ---

@test "_run_in_container passes a double-quoted multi-arch value through unchanged (docker/srun layer)" {
    run bash -c "
        source '$CKCOMMON'
        IMAGE=test-image
        IMAGE_DIR='$TMPDIR_TEST'
        _run_in_container 0 /work 'echo \"gfx942;gfx950;gfx1250\" -G Ninja'
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *'echo "gfx942;gfx950;gfx1250" -G Ninja'* ]]
}

# --- _require_arch_for_srun: hard-required on srun, no-op elsewhere ---

@test "_require_arch_for_srun exits 1 on srun with no arch" {
    run bash -c "
        source '$CKCOMMON'
        ARCH=''
        _require_arch_for_srun srun
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"no GPU to probe"* ]]
}

@test "_require_arch_for_srun computes GRES from ARCH on srun" {
    run bash -c "
        source '$CKCOMMON'
        ARCH=gfx942
        GRES=''
        _require_arch_for_srun srun
        echo \"GRES=\$GRES\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"GRES=gpu:gfx942-mi300x:1"* ]]
}

@test "_require_arch_for_srun does not overwrite a caller-set GRES" {
    run bash -c "
        source '$CKCOMMON'
        ARCH=gfx942
        GRES=custom-gres
        _require_arch_for_srun srun
        echo \"GRES=\$GRES\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"GRES=custom-gres"* ]]
}

@test "_require_arch_for_srun rejects a malformed ARCH on srun" {
    run bash -c "
        source '$CKCOMMON'
        ARCH='gfx942;touch pwned'
        _require_arch_for_srun srun
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"invalid arch"* ]]
}

@test "_require_arch_for_srun is a no-op on direct/docker" {
    run bash -c "
        source '$CKCOMMON'
        ARCH=''
        GRES=''
        _require_arch_for_srun direct
        echo \"rc=\$? ARCH=[\$ARCH] GRES=[\$GRES]\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"rc=0 ARCH=[] GRES=[]"* ]]
}

# --- _find_ck_root / _require_ck_root ---

@test "_find_ck_root walks up to the directory holding script/cmake-ck-dev.sh" {
    mkdir -p "$TMPDIR_TEST/root/script" "$TMPDIR_TEST/root/sub/dir"
    touch "$TMPDIR_TEST/root/script/cmake-ck-dev.sh"
    run bash -c "
        source '$CKCOMMON'
        _find_ck_root '$TMPDIR_TEST/root/sub/dir'
    "
    [ "$status" -eq 0 ]
    [ "$output" = "$TMPDIR_TEST/root" ]
}

@test "_find_ck_root fails when no ancestor has the marker file" {
    mkdir -p "$TMPDIR_TEST/a/b/c"
    run bash -c "
        source '$CKCOMMON'
        _find_ck_root '$TMPDIR_TEST/a/b/c'
    "
    [ "$status" -eq 1 ]
}

@test "_require_ck_root reassigns REPO by walking up from PWD when REPO is wrong" {
    mkdir -p "$TMPDIR_TEST/root/sub"
    touch "$TMPDIR_TEST/root/CMakeLists.txt"
    mkdir -p "$TMPDIR_TEST/root/script"
    touch "$TMPDIR_TEST/root/script/cmake-ck-dev.sh"
    run bash -c "
        cd '$TMPDIR_TEST/root/sub'
        source '$CKCOMMON'
        REPO=/nonexistent
        _require_ck_root
        echo \"REPO=\$REPO\"
    "
    [ "$status" -eq 0 ]
    [ "$output" = "REPO=$TMPDIR_TEST/root" ]
}

@test "_require_ck_root exits 1 when neither REPO nor PWD is a CK root" {
    mkdir -p "$TMPDIR_TEST/nowhere"
    run bash -c "
        cd '$TMPDIR_TEST/nowhere'
        source '$CKCOMMON'
        REPO=/nonexistent
        _require_ck_root
    "
    [ "$status" -eq 1 ]
    [[ "$output" == *"is not the CK project root"* ]]
}

# --- _new_run_dir: runs/<id> collision-avoidance ---

@test "_new_run_dir creates runs/<id> and echoes the id" {
    run bash -c "
        source '$CKCOMMON'
        run_id=\$(_new_run_dir '$TMPDIR_TEST/mode')
        [ -d \"$TMPDIR_TEST/mode/runs/\$run_id\" ]
        echo \"\$run_id\"
    "
    [ "$status" -eq 0 ]
    [[ "$output" =~ ^[0-9]{8}T[0-9]{6}Z$ ]]
}

@test "_new_run_dir suffixes with PID on a same-second collision" {
    run bash -c "
        set -e
        source '$CKCOMMON'
        date() { echo 20260707T000000Z; }
        run_id=\$(_new_run_dir '$TMPDIR_TEST/mode')
        [ \"\$run_id\" = 20260707T000000Z ]
        run_id2=\$(_new_run_dir '$TMPDIR_TEST/mode')
        [ \"\$run_id2\" = \"20260707T000000Z-\$\$-1\" ]
        [ -d \"$TMPDIR_TEST/mode/runs/\$run_id2\" ]
        run_id3=\$(_new_run_dir '$TMPDIR_TEST/mode')
        [ \"\$run_id3\" = \"20260707T000000Z-\$\$-2\" ]
    "
    [ "$status" -eq 0 ]
}

@test "_new_run_dir returns nonzero when runs/ cannot be created" {
    [ "$(id -u)" -eq 0 ] && skip "root bypasses directory permissions"
    run bash -c "
        source '$CKCOMMON'
        mkdir -p '$TMPDIR_TEST/blocked'
        chmod 000 '$TMPDIR_TEST/blocked'
        _new_run_dir '$TMPDIR_TEST/blocked/mode'
    "
    chmod 755 "$TMPDIR_TEST/blocked"
    [ "$status" -ne 0 ]
}

@test "_new_run_dir returns nonzero instead of looping when runs/ exists but is unwritable" {
    [ "$(id -u)" -eq 0 ] && skip "root bypasses directory permissions"
    mkdir -p "$TMPDIR_TEST/mode/runs"
    chmod 555 "$TMPDIR_TEST/mode/runs"
    run timeout 5 bash -c "
        source '$CKCOMMON'
        _new_run_dir '$TMPDIR_TEST/mode'
    "
    chmod 755 "$TMPDIR_TEST/mode/runs"
    [ "$status" -ne 0 ]
    [ "$status" -ne 124 ]
}
