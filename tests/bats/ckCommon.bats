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

@test "_dispatch_build_like on srun does not clobber a caller-set GPU (ckBuild's GPU-build-node case)" {
    run bash -c "
        source '$CKCOMMON'
        MODE=srun
        GPU=1
        GRES='gpu:gfx942-mi300x:1'
        _ensure_image_tar() { return 0; }
        _run_in_container() { echo container-snippet; }
        srun() { echo \"srun-called:GPU=\$GPU:\$*\"; }
        _dispatch_build_like 0 /work prog
    "
    [ "$status" -eq 0 ]
    [[ "$output" == *"srun-called:GPU=1:"* ]]
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
