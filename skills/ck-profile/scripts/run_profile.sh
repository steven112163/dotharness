#!/usr/bin/env bash
# Runtime-profile a CK binary with rocprofv3: kernel trace (runtime + static
# resources) and PMC multipass (L2 hit ratio, HBM fetch/write, occupancy, VALU).
#
# Driven entirely by environment variables so the skill can reuse it for any
# target and any argument sweep:
#
#   CONTAINER   docker container name              (default: styuan_dev)
#   REPO        host path = container path of repo (default: $PWD)
#   BIN         binary path relative to REPO       (required, e.g. build/bin/tile_example_ssd_fwd)
#   BASE_ARGS   args passed on every run           (default: "-v=0")
#   SWEEP_FLAG  flag to vary, e.g. "-prec"         (optional; empty = single variant)
#   SWEEP_VALS  comma list, e.g. "fp32,fp16,bf16"  (optional)
#   NRUNS       runs per variant                   (default: 20)
#   COUNTERS    path to counters.txt               (default: alongside this script)
#   OUTDIR      where raw output is written        (default: REPO/ck_profile_out/raw)
#
# Profiling uses BASE_ARGS as given; pass -v=0 there to skip CPU verification.
set -u

CONTAINER=${CONTAINER:-styuan_dev}
REPO=${REPO:-$PWD}
BIN=${BIN:?set BIN to the binary path under REPO, e.g. build/bin/<target>}
BASE_ARGS=${BASE_ARGS:--v=0}
SWEEP_FLAG=${SWEEP_FLAG:-}
SWEEP_VALS=${SWEEP_VALS:-}
NRUNS=${NRUNS:-20}
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
COUNTERS=${COUNTERS:-$SELF_DIR/counters.txt}
OUTDIR=${OUTDIR:-$REPO/ck_profile_out/raw}

binbase=$(basename "$BIN")
dx() { docker exec -w "$REPO" "$CONTAINER" bash -c "$1"; }
kill_orphans() { docker exec "$CONTAINER" pkill -9 -f "$binbase" 2>/dev/null; }

# Copy counters.txt to a repo-visible path so the container can read it.
cp "$COUNTERS" "$REPO/.ck_profile_counters.txt"
CNT_IN_REPO=.ck_profile_counters.txt

# Build the variant list. Empty sweep -> one variant named "default".
if [ -n "$SWEEP_VALS" ]; then
  IFS=',' read -ra VARIANTS <<< "$SWEEP_VALS"
else
  VARIANTS=("default")
fi

rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"

for v in "${VARIANTS[@]}"; do
  if [ "$v" = "default" ] || [ -z "$SWEEP_FLAG" ]; then
    args="$BASE_ARGS"; vlabel="default"
  else
    args="$BASE_ARGS $SWEEP_FLAG=$v"; vlabel="$v"
  fi
  for i in $(seq 1 "$NRUNS"); do
    rid=$(printf "%02d" "$i")
    out="$OUTDIR/$vlabel/run_$rid"
    mkdir -p "$out"
    dx "rocprofv3 --kernel-trace --stats --summary -T -d '$out' -o t -f csv -- ./$BIN $args >'$out/t.stdout' 2>'$out/t.stderr'"
    te=$?; kill_orphans
    dx "rocprofv3 -i '$CNT_IN_REPO' -d '$out' -o p -f csv -- ./$BIN $args >'$out/p.stdout' 2>'$out/p.stderr'"
    pe=$?; kill_orphans
    echo "$vlabel run $rid: trace_exit=$te pmc_exit=$pe"
  done
done
rm -f "$REPO/.ck_profile_counters.txt"
# rocprofv3 leaves a .rocprofv3/ scratch dir (raw counter dumps) in the cwd.
find "$REPO/.rocprofv3" -mindepth 1 -delete 2>/dev/null; rmdir "$REPO/.rocprofv3" 2>/dev/null
echo "DONE  (raw output in $OUTDIR)"
