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

dx() { docker exec -w "$REPO" "$CONTAINER" bash -c "$1"; }

[ -z "$ARCH" ] && ARCH=$(docker exec "$CONTAINER" bash -c "rocminfo 2>/dev/null | grep -m1 -oE 'gfx[0-9a-z]+'")
[ -z "$ARCH" ] && { echo "could not detect GPU arch"; exit 1; }
BUILD=$REPO/ck_profile_out/static/$TARGET-$ARCH   # under repo -> host-visible log/reports
LOG=$BUILD/build.log
mkdir -p "$BUILD"

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
docker exec -w "$REPO" "$CONTAINER" python3 "$PARSER" "$LOG" --target "$TARGET" --arch "$ARCH"
echo "Reports: $BUILD/build_report.md and .csv"
