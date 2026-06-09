#!/usr/bin/env bash
# Deep microarchitecture profiling with rocprof-compute (ROCm Compute Profiler):
# roofline + memory-hierarchy / speed-of-light panels. Installs the
# `rocprofiler-compute` package if missing — this is the ONLY ck-profile action
# that modifies the container, and only runs in this (compute) mode.
#
#   CONTAINER   docker container        (default: styuan_dev)
#   REPO        host=container repo path (default: $PWD; auto-corrected)
#   BIN         binary under REPO        (required, e.g. build/bin/<target>)
#   BASE_ARGS   args passed to the app   (default: "-v=0")
#   ARCH        gfx arch                 (default: auto-detect)
#   WORKLOAD    workload name            (default: basename of BIN)
#   OUTDIR      output dir               (default: REPO/ck_profile_out/compute)
set -u

CONTAINER=${CONTAINER:-styuan_dev}
REPO=${REPO:-$PWD}
BIN=${BIN:?set BIN to the binary path under REPO, e.g. build/bin/<target>}

_find_ck_root() {
    local d="$1"
    while [ -n "$d" ] && [ "$d" != "/" ]; do
        [ -e "$d/script/cmake-ck-dev.sh" ] && {
            printf '%s\n' "$d"
            return 0
        }
        d=$(dirname "$d")
    done
    return 1
}
if [ ! -e "$REPO/$BIN" ]; then
    alt=$(_find_ck_root "$REPO" || _find_ck_root "$PWD") && REPO="$alt"
fi
if [ ! -e "$REPO/$BIN" ]; then
    echo "ERROR: binary not found: \$REPO/\$BIN = $REPO/$BIN" >&2
    echo "  Set REPO to the CK project root and BIN to build/bin/<target>." >&2
    exit 1
fi

BASE_ARGS=${BASE_ARGS:--v=0}
ARCH=${ARCH:-}
WORKLOAD=${WORKLOAD:-$(basename "$BIN")}
OUTDIR=${OUTDIR:-$REPO/ck_profile_out/compute}
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

dx() { docker exec -w "$REPO" "$CONTAINER" bash -c "$1"; }
dxroot() { docker exec -u 0 -w "$REPO" "$CONTAINER" bash -c "$1"; } # install needs root
[ -z "$ARCH" ] && ARCH=$(docker exec "$CONTAINER" bash -c "rocminfo 2>/dev/null | grep -m1 -oE 'gfx[0-9a-z]+'")
mkdir -p "$OUTDIR"
cp "$SELF_DIR/profile_readme.md" "$REPO/ck_profile_out/README.md" 2>/dev/null || true
bash "$SELF_DIR/git_exclude_outdir.sh" "$REPO" 2>/dev/null || true # ignore output via .git/info/exclude

# Ensure rocprof-compute exists (the only container-modifying step). The
# container's default user is non-root and sudo needs a TTY/password, so the
# install runs as root via `docker exec -u 0`. The launcher lives in /opt/rocm/bin
# (often not on the non-login docker-exec PATH), so resolve it by path rather than
# relying on `command -v`.
# shellcheck disable=SC2016  # command template eval'd inside the container via dx; must not expand locally
_resolve_rpc='command -v rocprof-compute 2>/dev/null || for p in /opt/rocm/bin/rocprof-compute /opt/rocm*/bin/rocprof-compute; do [ -x "$p" ] && { echo "$p"; break; }; done'
RPC=$(dx "$_resolve_rpc")
if [ -z "$RPC" ]; then
    echo "rocprof-compute not found — installing rocprofiler-compute as root (modifies the container) ..."
    dxroot "apt-get install -y rocprofiler-compute || (apt-get update && apt-get install -y rocprofiler-compute)" ||
        {
            echo 'ERROR: rocprofiler-compute install failed; reporting rather than forcing.' >&2
            exit 2
        }
    RPC=$(dx "$_resolve_rpc")
fi
[ -z "$RPC" ] && {
    echo 'ERROR: rocprof-compute not found after install.' >&2
    exit 2
}

# rocprof-compute is a Python app; its runtime deps (requirements.txt) are NOT
# shipped by the apt package — the official install runs
# `pip install -r .../requirements.txt`. Ubuntu 24.04 blocks system pip (PEP 668),
# so install them into a dedicated venv (reversible: delete it) and run the
# launcher with that venv's python. --system-site-packages reuses what's present.
RPC_REAL=$(dx "readlink -f '$RPC' 2>/dev/null || echo '$RPC'")
REQ=$(dx "ls /opt/rocm/libexec/rocprofiler-compute/requirements.txt /opt/rocm*/libexec/rocprofiler-compute/requirements.txt 2>/dev/null | head -1")
# Persistent venv in a stable home location (bind-mounted, so it survives across
# container sessions and is reused). It is built with the CONTAINER's python and
# is container-only: the host python differs (e.g. 3.10 vs 3.12), and the host
# can't run rocprof-compute anyway (no in-container ROCm/GPU). The python version
# is in the name so multiple interpreters don't collide.
PYVER=$(dx 'python3 -c "import sys;print(f\"{sys.version_info.major}.{sys.version_info.minor}\")" 2>/dev/null')
VENV="${VENV:-$HOME/pyenv/rocprof-compute-py$PYVER}"
PYBIN="$VENV/bin/python"
if ! dx "test -x '$PYBIN' && '$PYBIN' '$RPC_REAL' --version >/dev/null 2>&1"; then
    [ -z "$REQ" ] && {
        echo 'ERROR: requirements.txt not found for rocprof-compute.' >&2
        exit 2
    }
    echo "Installing rocprof-compute python deps into venv $VENV (python $PYVER; one-time; heavy) ..."
    if dx "command -v uv >/dev/null 2>&1"; then
        # uv is much faster when present (the user can install it later; auto-used).
        dx "uv venv --system-site-packages --python python3 '$VENV' && uv pip install -q --python '$PYBIN' -r '$REQ'" ||
            {
                echo 'ERROR: uv failed to build rocprof-compute venv.' >&2
                exit 2
            }
    else
        dx "python3 -m venv --system-site-packages '$VENV' && '$PYBIN' -m pip install -q --upgrade pip && '$PYBIN' -m pip install -q -r '$REQ'" ||
            {
                echo 'ERROR: failed to install rocprof-compute python deps into venv.' >&2
                exit 2
            }
    fi
fi
RUN_RPC="'$PYBIN' '$RPC_REAL'"
echo "rocprof-compute: $(dx "$RUN_RPC --version 2>&1 | head -1")  (venv: $VENV, python $PYVER)"

# rocprof-compute writes the workload data directly into `-p <dir>` (sysinfo.csv,
# pmc_perf.csv, roofline.csv, perfmon/, ...), so analyze reads the same dir. Keep
# that bulk under raw/; the report .html/.md go at the top of the mode dir.
RAW="$OUTDIR/raw"
mkdir -p "$RAW"
wl_dir="$RAW/$WORKLOAD"
echo "Profiling $BIN with rocprof-compute (multi-pass) ..."
dx "$RUN_RPC profile -n '$WORKLOAD' -p '$wl_dir' -- ./$BIN $BASE_ARGS >'$RAW/profile.log' 2>&1"
pe=$?
echo "profile exit: $pe"

# Export structured CSV panels (for the styled report) and a raw text dump (kept
# in raw/ for power users), then render HTML + Markdown via compute_report.py.
echo "Analyzing (CSV panels + text dump) ..."
# --output-name must be a bare name (alnum/_/-, no slashes/dots), created in CWD,
# so run with the working dir set to raw/.
csvname="${WORKLOAD}_csv"
csvdir="$RAW/$csvname"
docker exec -w "$RAW" "$CONTAINER" bash -c "$RUN_RPC analyze -p '$wl_dir' --output-format csv --output-name '$csvname' >'$RAW/analyze_csv.log' 2>&1"
ae=$?
echo "analyze exit: $ae"
dx "$RUN_RPC analyze -p '$wl_dir' >'$RAW/${WORKLOAD}_analyze.txt' 2>&1" || true

echo "Rendering HTML + Markdown report ..."
docker exec -w "$REPO" "$CONTAINER" python3 "$SELF_DIR/compute_report.py" \
    --csv "$csvdir" --out "$OUTDIR" --name "$WORKLOAD" --arch "$ARCH"
re=$?
# rocprof-compute runs the app under rocprofv3, which leaves a .rocprofv3/ scratch
# dir (raw counter dumps) in the cwd (= $REPO); remove it like the other modes do.
find "$REPO/.rocprofv3" -mindepth 1 -delete 2>/dev/null
rmdir "$REPO/.rocprofv3" 2>/dev/null
echo "DONE  (profile=$pe analyze=$ae report=$re)"
echo "  report: $OUTDIR/${WORKLOAD}_report.html / .md   (raw data + text dump in $RAW)"
[ $pe -eq 0 ] && [ $ae -eq 0 ] && [ $re -eq 0 ]
