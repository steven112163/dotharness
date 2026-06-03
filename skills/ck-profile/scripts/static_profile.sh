#!/usr/bin/env bash
# Static (compile-time) kernel resource analysis: build a CK target with
# -Rpass-analysis=kernel-resource-usage and parse the remarks for VGPR/AGPR/
# SGPR/occupancy/spill/scratch/LDS. No GPU execution. Complements run_profile.sh.
#
# Uses a SEPARATE build dir under the repo (ck_profile_out/static/...) so the
# user's main build/ is never reconfigured with diagnostic flags, while the log
# and reports stay visible on the host. cmake-ck-dev.sh cannot target an
# alternate build dir (its dev preset hardcodes binaryDir), so this calls cmake
# directly with the equivalent dev settings.
#
#   CONTAINER  docker container        (default: styuan_dev)
#   REPO       host=container repo path (default: $PWD)
#   TARGET     CMake target name        (required)
#   ARCH       gfx arch                 (default: auto-detect in container)
set -u

CONTAINER=${CONTAINER:-styuan_dev}
REPO=${REPO:-$PWD}
TARGET=${TARGET:?set TARGET to the CMake target name}
ARCH=${ARCH:-}
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
PARSER=${PARSER:-$SELF_DIR/parse_resource_usage.py}  # under $HOME, visible in container

# Resolve REPO to the CK project root even if the caller's cwd drifted into a
# subdir: walk up from REPO, then $PWD, for script/cmake-ck-dev.sh. Fail fast if
# it is still not a CK root rather than configuring a build in the wrong place.
_find_ck_root() {
  local d="$1"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -e "$d/script/cmake-ck-dev.sh" ] && { printf '%s\n' "$d"; return 0; }
    d=$(dirname "$d")
  done
  return 1
}
if [ ! -e "$REPO/script/cmake-ck-dev.sh" ]; then
  alt=$(_find_ck_root "$REPO" || _find_ck_root "$PWD") && REPO="$alt"
fi
if [ ! -e "$REPO/CMakeLists.txt" ] || [ ! -e "$REPO/script/cmake-ck-dev.sh" ]; then
  echo "ERROR: \$REPO ($REPO) is not the CK project root" >&2
  echo "  (expected script/cmake-ck-dev.sh and CMakeLists.txt). Set REPO to that dir," >&2
  echo "  e.g. REPO=\$(git rev-parse --show-toplevel)." >&2
  exit 1
fi

dx() { docker exec -w "$REPO" "$CONTAINER" bash -c "$1"; }

[ -z "$ARCH" ] && ARCH=$(docker exec "$CONTAINER" bash -c "rocminfo 2>/dev/null | grep -m1 -oE 'gfx[0-9a-z]+'")
[ -z "$ARCH" ] && { echo "could not detect GPU arch"; exit 1; }
# Keep the heavy throwaway CMake/Ninja tree (compile_commands.json, CMakeCache,
# .ninja_*, ~2k files) OUT of the reports dir: editor tooling (CMake Tools /
# clangd) activates on a build tree and keeps touching files, which makes the
# Cursor "Live Preview" webview reload repeatedly when the report sits inside it.
# Reports go to a clean dir with nothing but the .md/.csv/.html.
BUILD=$REPO/ck_profile_out/static-build/$TARGET-$ARCH   # throwaway build tree (big)
REPORTDIR=$REPO/ck_profile_out/static/$TARGET-$ARCH     # clean: reports only
LOG=$BUILD/build.log
mkdir -p "$BUILD" "$REPORTDIR"

echo "Configuring static-analysis build ($ARCH) in container $BUILD ..."
dx "cmake -S '$REPO' -B '$BUILD' -GNinja \
  -DCMAKE_PREFIX_PATH=/opt/rocm/ \
  -DCMAKE_CXX_COMPILER=/opt/rocm/llvm/bin/clang++ \
  -DCMAKE_HIP_COMPILER=/opt/rocm/llvm/bin/clang++ \
  '-DCMAKE_CXX_FLAGS=-Rpass-analysis=kernel-resource-usage -ftemplate-backtrace-limit=0 -fPIE -Wno-gnu-line-marker -fbracket-depth=1024' \
  -DCMAKE_BUILD_TYPE=Release -DBUILD_DEV=ON -DGPU_TARGETS=$ARCH" || { echo "configure failed"; exit 1; }

echo "Building $TARGET (slow; remarks go to the log) ..."
dx "cmake --build '$BUILD' --target '$TARGET' -j\$(( \$(nproc) / 2 )) > '$LOG' 2>&1"
echo "build exit: $?  (partial logs still parse)"

# Parser runs in the container so c++filt is available for demangling; the log
# and reports live under the repo, so they are visible on the host afterwards.
echo "Parsing resource-usage remarks (demangling with c++filt) ..."
docker exec -w "$REPO" "$CONTAINER" python3 "$PARSER" "$LOG" --target "$TARGET" --arch "$ARCH" --out "$REPORTDIR"
echo "Reports: $REPORTDIR/build_report.{md,csv,html}  (build tree kept separately in $BUILD)"
