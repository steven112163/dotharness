---
name: ck-profile
description: >-
  Profile a Composable Kernel (CK) build target two ways: STATIC compile-time
  resource analysis (VGPR/AGPR/SGPR, occupancy ceiling, register spills,
  scratch, LDS via -Rpass-analysis) and DYNAMIC runtime profiling with rocprofv3
  (kernel timing, HBM fetch/write, L2 hit ratio, occupancy, VALU/SALU,
  memory-stall %, LDS bank conflicts) averaged over N runs and across an
  argument sweep, with a roofline-lite compute/memory/latency bottleneck
  verdict. Use when the user wants to profile, benchmark, or find the
  performance bottleneck of a CK example/test binary; says "profile <target>",
  "is <target> compute- or memory-bound", "check register spills / occupancy",
  "benchmark fp16 vs bf16", "rocprof <target>", "static/dynamic profile", or
  "sweep -B / -prec and compare". The user can choose static, dynamic, or both.
---

# CK profiling (ck-profile)

Two independent modes; the user picks one or both:

- **static** — compile-time only, no GPU run. Builds the target with
  `-Rpass-analysis=kernel-resource-usage` and parses the remarks for register/
  occupancy/spill/scratch/LDS. Answers "what each kernel reserves and its
  occupancy ceiling."
- **dynamic** — runs the target under rocprofv3 (kernel trace + PMC multipass),
  aggregates over runs/variants, and classifies the bottleneck. Answers "what
  actually happened at runtime and what is the limiter."

See [REFERENCE.md](REFERENCE.md) for counters, CSV layout, the static remark
format, and the roofline thresholds.

## Inputs

| Input | Required | Default | Notes |
|-------|----------|---------|-------|
| mode | yes | — | `static`, `dynamic`, or `both`. Ask if unspecified. |
| target | yes | — | CMake target, e.g. `tile_example_ssd_fwd`. No default. |
| container | no | `styuan_dev` | Created via `~/bin/dockerRun` if missing. |
| image | no | `rocm/composable_kernel:ck_ub24.04_rocm7.1.1_develop` | Only used if the container must be created. |
| base args | no | `-v=0` | Dynamic only; passed every run (`-v=0` skips CPU verify). |
| sweep | no | none | Dynamic only. A flag + comma values, e.g. `-prec=fp32,fp16,bf16` or `-B=1,2,4`. |
| nruns | no | 20 | Dynamic only. Runs per variant. |

## Common setup (both modes)

1. **Preconditions.** Confirm `pwd` is a CK repo (`script/cmake-ck-dev.sh`
   exists); set `$REPO=$PWD`. The repo and `$HOME` are bind-mounted at the same
   path inside the container, so host and container paths (including this
   skill's scripts) match.
2. **Container.** `docker ps --filter name=^<container>$`. If not running, start
   it with `~/bin/dockerRun <image> <container>` using the default image above.
3. **GPU arch.** `docker exec <container> bash -c "rocminfo | grep -m1 -oE 'gfx[0-9a-z]+'"`.
   Save as `$ARCH`; build for this arch only.

## Static mode

Run the bundled wrapper (separate throwaway build dir; the main `build/` is
untouched). The build is slow and template-heavy — run in background / delegate:

```bash
CONTAINER=<container> REPO=$REPO TARGET=<target> ARCH=$ARCH \
  bash <skill-dir>/scripts/static_profile.sh
```

It builds with the resource-usage remark flag, parses the log (demangling kernel
names with `c++filt`), and prints a summary; full report + CSV land under the
repo at `ck_profile_out/static/<target>-<arch>/build_report.{md,csv,html}` (so
they are visible on the host; the `.html` is a self-contained chart view —
occupancy histogram, effective-VGPR bars with the cliff marked, spill rows
highlighted). Report scope: for a focused ask ("spills",
"occupancy", "LDS"), filter to the relevant columns; otherwise give the overview
+ worst offenders. The occupancy cliff to watch is **129 effective VGPRs**
(128→4 waves, 129→3 waves). See REFERENCE.md.

## Dynamic mode

1. **Ensure the binary exists.** If `build/bin/<target>` is missing, configure
   and build for the host arch only (delegate the build — logs are large):
   ```bash
   docker exec -w $REPO/build <container> bash -c \
     "../script/cmake-ck-dev.sh --minimal .. $ARCH -G Ninja && ninja <target>"
   ```
2. **Profile.** The harness writes per-run CSVs under
   `ck_profile_out/raw/<variant>/run_NN/` and is robust to PMC counter-capacity
   crashes (kills orphaned app processes; cleans the `.rocprofv3/` scratch dir):
   ```bash
   CONTAINER=<container> REPO=$REPO BIN=build/bin/<target> \
     BASE_ARGS='-v=0' SWEEP_FLAG='<flag>' SWEEP_VALS='<v1,v2,...>' NRUNS=<n> \
     bash <skill-dir>/scripts/run_profile.sh
   ```
   Omit `SWEEP_FLAG`/`SWEEP_VALS` for a single variant. A long sweep
   (variants × nruns × passes) takes minutes — run in background.
3. **Aggregate + classify.**
   ```bash
   python3 <skill-dir>/scripts/aggregate.py --raw $REPO/ck_profile_out/raw \
     --arch $ARCH [--iters N | --marker <kernel-substr>]
   ```
   `--iters` (e.g. warmup+repeat) or `--marker` (a kernel firing once per
   pipeline) gives per-iteration numbers; otherwise values are per-run. Writes
   `summary.md` (readable report), `summary_overall.csv`, and
   `per_kernel_<variant>.csv`.
4. **Report.** `aggregate.py` writes `summary.md` (markdown), `summary.html`
   (self-contained, opens offline — runtime bar chart, per-variant roofline
   gauges + verdict badges, per-kernel bars), `summary_overall.csv`, and
   `per_kernel_*.csv`. Show `summary.md` (point the user at `summary.html` for the
   charts) — a **Device spec** block (CUs, wave size, SIMD/CU, max waves/CU,
   VGPR/AGPR file, LDS/CU, peak BW from `gpu_specs.py`), the per-variant table
   (gpu_ms, L2 hit %, fetch/write MB, occupancy, **occ-util %** = achieved ÷ max
   waves/CU, VALU/SALU %, mem-stall %, achieved BW, BW-util %, **verdict**), and
   the per-kernel breakdown. For a focused ask, lead with the verdict and the two
   ratios behind it (see the taxonomy in REFERENCE.md). The static report is
   emitted as `build_report.{md,csv,html}` with the same device-spec block.

## Both

Run static and dynamic and combine: the static occupancy *ceiling* explains a
low achieved-occupancy / latency-bound dynamic verdict (e.g. register spills or
high VGPR pressure capping the wave count).
