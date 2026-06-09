#!/usr/bin/env bash
# ISA control-flow graphs for a CK target. Extracts the device (amdgcn) code
# object from the host binary, disassembles it with llvm-objdump, and emits one
# Graphviz .dot per kernel (via cfg_to_dot.py). DOT only — no graphviz/SVG.
#
#   CONTAINER  docker container        (default: styuan_dev)
#   REPO       host=container repo path (default: $PWD; auto-corrected)
#   BIN        binary under REPO        (required, e.g. build/bin/<target>)
#   ARCH       gfx arch                 (default: auto-detect in container)
#   OUTDIR     output dir               (default: REPO/ck_profile_out/cfg)
#   OBJDUMP    llvm-objdump path        (default: /opt/rocm/llvm/bin/llvm-objdump)
set -u

CONTAINER=${CONTAINER:-styuan_dev}
REPO=${REPO:-$PWD}
BIN=${BIN:?set BIN to the binary path under REPO, e.g. build/bin/<target>}

# Resolve REPO to the CK project root even if cwd drifted; fail fast otherwise.
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

ARCH=${ARCH:-}
OUTDIR=${OUTDIR:-$REPO/ck_profile_out/cfg}
OBJDUMP=${OBJDUMP:-/opt/rocm/llvm/bin/llvm-objdump}
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

dx() { docker exec -w "$REPO" "$CONTAINER" bash -c "$1"; }
[ -z "$ARCH" ] && ARCH=$(docker exec "$CONTAINER" bash -c "rocminfo 2>/dev/null | grep -m1 -oE 'gfx[0-9a-z]+'")

mkdir -p "$OUTDIR"
cp "$SELF_DIR/profile_readme.md" "$REPO/ck_profile_out/README.md" 2>/dev/null || true
bash "$SELF_DIR/git_exclude_outdir.sh" "$REPO" 2>/dev/null || true # ignore output via .git/info/exclude
echo "Extracting amdgcn code object from $BIN and disassembling ($ARCH) ..."
# Everything runs in the container: roc-obj-ls/-extract + llvm-objdump live there,
# c++filt (used by cfg_to_dot.py for demangling) is there too. REPO and the skill
# dir are bind-mounted at the same path, so paths match host-side afterwards.
dx "
set -e
tmp=\$(mktemp -d); cd \"\$tmp\"
uri=\$(roc-obj-ls '$REPO/$BIN' 2>/dev/null | grep gfx | awk '{print \$NF}' | head -1)
[ -z \"\$uri\" ] && { echo 'no amdgcn code object found in binary' >&2; exit 2; }
roc-obj-extract \"\$uri\" >/dev/null 2>&1
co=\$(ls *.co 2>/dev/null | head -1)
[ -z \"\$co\" ] && { echo 'roc-obj-extract produced no .co file' >&2; exit 3; }
'$OBJDUMP' -d \"\$co\" 2>/dev/null | python3 '$SELF_DIR/cfg_to_dot.py' --out '$OUTDIR' --arch '$ARCH'
rm -rf \"\$tmp\"
"
rc=$?
[ $rc -eq 0 ] && echo "CFG DOT files in $OUTDIR  (open .dot in VS Code Graphviz preview)" || echo "cfg_dump failed (exit $rc)"
exit $rc
