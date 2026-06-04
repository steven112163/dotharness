#!/usr/bin/env bash
# Timeline trace of a CK binary with rocprofv3: --sys-trace -> a perfetto
# .pftrace (open at https://ui.perfetto.dev) plus CSV (kernel-trace, reused by
# depgraph.py runtime mode). Optionally a best-effort PC-sampling pass for
# instruction-level hotspots (beta; skipped cleanly if the driver lacks support).
#
#   CONTAINER    docker container        (default: styuan_dev)
#   REPO         host=container repo path (default: $PWD; auto-corrected)
#   BIN          binary under REPO        (required, e.g. build/bin/<target>)
#   BASE_ARGS    args passed every run    (default: "-v=0")
#   SWEEP_FLAG   flag to vary, e.g. -prec (optional)
#   SWEEP_VALS   comma list, e.g. fp16,bf16 (optional)
#   NRUNS        runs per variant         (default: 1 — a timeline needs one)
#   PC_SAMPLING  1=attempt PC sampling, 0=skip (default: 1, best-effort)
#   OUTDIR       output dir               (default: REPO/ck_profile_out/trace)
set -u

CONTAINER=${CONTAINER:-styuan_dev}
REPO=${REPO:-$PWD}
BIN=${BIN:?set BIN to the binary path under REPO, e.g. build/bin/<target>}

# Resolve REPO to the CK project root even if cwd drifted; fail fast otherwise.
_find_ck_root() {
  local d="$1"
  while [ -n "$d" ] && [ "$d" != "/" ]; do
    [ -e "$d/script/cmake-ck-dev.sh" ] && { printf '%s\n' "$d"; return 0; }
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
SWEEP_FLAG=${SWEEP_FLAG:-}
SWEEP_VALS=${SWEEP_VALS:-}
NRUNS=${NRUNS:-1}
PC_SAMPLING=${PC_SAMPLING:-1}
OUTDIR=${OUTDIR:-$REPO/ck_profile_out/trace}
SELF_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

binbase=$(basename "$BIN")
dx() { docker exec -w "$REPO" "$CONTAINER" bash -c "$1"; }
kill_orphans() { docker exec "$CONTAINER" pkill -9 -f "$binbase" 2>/dev/null; }

if [ -n "$SWEEP_VALS" ]; then IFS=',' read -ra VARIANTS <<< "$SWEEP_VALS"; else VARIANTS=("default"); fi
rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"
cp "$SELF_DIR/profile_readme.md" "$REPO/ck_profile_out/README.md" 2>/dev/null || true
bash "$SELF_DIR/git_exclude_outdir.sh" "$REPO" 2>/dev/null || true  # ignore output via .git/info/exclude
index="$OUTDIR/index.md"
{ echo "# trace mode — rocprofv3 timeline";
  echo;
  echo "## How to read";
  echo "- **\`raw/<variant>/run_NN/timeline.html\`** — open this in Cursor's Live";
  echo "  Preview (offline, self-contained). A host (HIP API) lane over a GPU dispatch";
  echo "  lane on a shared time axis: ctrl+wheel zooms at the cursor, drag pans, hover";
  echo "  shows name/start/duration. This is the in-editor view — no browser needed.";
  echo "- **\`raw/<variant>/run_NN/trace_results.pftrace\`** — the full perfetto trace";
  echo "  for deep dives (flows, counter tracks, CPU sched, nanosecond zoom). Open";
  echo "  https://ui.perfetto.dev and drag the file in (the file is local; only the";
  echo "  viewer is web). The HTML timeline is the useful 80%; reach for this for the";
  echo "  rest.";
  echo "- **What to look for (either view):** gaps between dispatches (host launch";
  echo "  latency / serialization), whether kernels overlap, which kernel dominates a";
  echo "  frame. A chain of tiny back-to-back kernels with gaps = latency-bound.";
  echo "- **Companion CSVs** (\`raw/.../trace_*_trace.csv\`) are the same events as text;";
  echo "  \`*_kernel_trace.csv\` feeds both the HTML timeline and \`depgraph --mode runtime\`.";
  echo "- Use **dynamic** mode for absolute numbers/verdict (\`--sys-trace\` adds";
  echo "  overhead); use **trace** to see ordering and bubbles.";
  echo;
  echo "## Traces"; echo; } > "$index"

for v in "${VARIANTS[@]}"; do
  if [ "$v" = "default" ] || [ -z "$SWEEP_FLAG" ]; then args="$BASE_ARGS"; vlabel="default"
  else args="$BASE_ARGS $SWEEP_FLAG=$v"; vlabel="$v"; fi
  for i in $(seq 1 "$NRUNS"); do
    rid=$(printf "%02d" "$i"); out="$OUTDIR/raw/$vlabel/run_$rid"; mkdir -p "$out"
    dx "rocprofv3 --sys-trace -f pftrace csv -d '$out' -o trace -- ./$BIN $args >'$out/trace.stdout' 2>'$out/trace.stderr'"
    te=$?; kill_orphans
    pc="skipped"
    if [ "$PC_SAMPLING" = "1" ]; then
      dx "rocprofv3 --pc-sampling-beta-enabled --pc-sampling-method stochastic --pc-sampling-unit instructions --pc-sampling-interval 1048576 -f csv -d '$out' -o pc -- ./$BIN $args >'$out/pc.stdout' 2>'$out/pc.stderr'"
      [ $? -eq 0 ] && pc="ok" || pc="unsupported"
      kill_orphans
    fi
    pft=$(cd "$out" 2>/dev/null && ls *.pftrace 2>/dev/null | head -1)
    # Render the offline HTML timeline from the CSVs (pure-stdlib python on the host).
    tl="missing"
    python3 "$SELF_DIR/trace_timeline.py" --run-dir "$out" --prefix trace \
      --name "$vlabel/run_$rid" >/dev/null 2>"$out/timeline.stderr" \
      && [ -s "$out/timeline.html" ] && tl="ok"
    [ -s "$out/timeline.stderr" ] || rm -f "$out/timeline.stderr"  # drop empty log
    echo "- **$vlabel** run $rid: trace_exit=$te pc_sampling=$pc timeline=$tl  ->  \`$out/timeline.html\` · \`$out/${pft:-trace.pftrace}\`" >> "$index"
    echo "$vlabel run $rid: trace_exit=$te pc_sampling=$pc timeline=$tl"
  done
done
find "$REPO/.rocprofv3" -mindepth 1 -delete 2>/dev/null; rmdir "$REPO/.rocprofv3" 2>/dev/null
echo "DONE  (traces in $OUTDIR; see index.md)"
