---
name: ck-profile
argument-hint: "<target> [modes]"
description: >-
  Profile a Composable Kernel (CK) build target two ways: static compile-time
  resource analysis (registers, occupancy ceiling, spills, scratch, LDS) and
  dynamic runtime profiling with rocprofv3 (timing, HBM traffic, cache, occupancy)
  averaged over N runs and an argument sweep, with a roofline-lite
  compute/memory/latency verdict. Use when the user wants to profile, benchmark,
  or find the bottleneck of a CK example/test binary; says "profile <target>",
  "is <target> compute- or memory-bound", "check register spills / occupancy",
  "benchmark fp16 vs bf16", "rocprof <target>", "static/dynamic profile", or
  "sweep -B / -prec and compare". The user selects one or more of six modes:
  static, dynamic, trace, cfg, depgraph, compute. Not for non-CK or CPU-only
  targets, or for correctness testing.
---

# CK profiling (ck-profile)

Six independent modes; the user picks one or several:

- **static** — compile-time only, no GPU run. Builds the target with
  `-Rpass-analysis=kernel-resource-usage` and parses the remarks for register/
  occupancy/spill/scratch/LDS. Answers "what each kernel reserves and its
  occupancy ceiling."
- **dynamic** — runs the target under rocprofv3 (kernel trace + PMC multipass),
  aggregates over runs/variants, and classifies the bottleneck. Answers "what
  actually happened at runtime and what is the limiter."
- **trace** — rocprofv3 `--sys-trace` → an offline **HTML timeline** (host +
  device lanes, opens in Live Preview) plus a perfetto `.pftrace` (+ sys-trace
  CSVs); optional best-effort PC sampling. Answers "what is the dispatch timeline
  / where on the host-GPU timeline does time go."
- **cfg** — extracts the amdgcn code object and disassembles it (`llvm-objdump`),
  emitting one per-kernel ISA control-flow graph as Graphviz `.dot`. Answers
  "what does each kernel's basic-block / branch structure look like."
- **depgraph** — two dependency graphs as `.dot`: a logical data-dependency DAG
  (workspace producer→consumer, from the launch source) and a runtime dispatch
  graph (from a kernel trace). Answers "how do the kernels depend on / follow
  each other."
- **compute** — `rocprof-compute` (ROCm Compute Profiler): roofline +
  speed-of-light + memory-hierarchy panels. Answers "where in the
  microarchitecture is the kernel limited." Installs `rocprofiler-compute` if
  missing — the only mode that modifies the container.

Modes are independent and may be combined; **graphs (`cfg`, `depgraph`) emit DOT
only** — preview `.dot` in VS Code's Graphviz extension (no graphviz/SVG).

See [REFERENCE.md](REFERENCE.md) for counters, CSV layout, the static remark
format, the roofline thresholds, the CFG basic-block rules, the dependency-graph
semantics, and — for turning numbers into action — the **diagnosis playbook**
(pattern → signals → fix) and the **ranked optimization directions** rule.

**Golden rule: profile → diagnose → recommend, in that order. Never guess.** Do not
invent a bottleneck before the report; do not propose a fix you cannot tie to a
counter value. The deliverable is a short, ranked list of next optimizations, each
citing the specific numbers that justify it.

## Inputs

| Input | Required | Default | Notes |
|-------|----------|---------|-------|
| mode | yes | — | One or more of `static`, `dynamic`, `trace`, `cfg`, `depgraph`, `compute`. Ask if unspecified. |
| target | yes | — | CMake target, e.g. `tile_example_ssd_fwd`. No default. |
| container | no | `styuan_dev` | Named long-lived container. Used only when the remote server is a normal (non-Slurm) docker host. On Slurm, ignored — profile scripts auto-detect `srun` and dispatch via the GPU holder instead. |
| image | no | `rocm/composable_kernel:ck_ub24.04_rocm7.1.1_develop` | Container image. Used by both paths: the named container on docker servers, and the ephemeral `--rm` containers on Slurm (loaded from tarball on the compute node). |
| base args | no | `-v=0` | `dynamic`/`trace`/`compute`; passed every run (`-v=0` skips CPU verify). |
| sweep | no | none | `dynamic`/`trace`. A flag + comma values, e.g. `-prec=fp32,fp16,bf16` or `-B=1,2,4`. |
| nruns | no | 20 (dynamic), 1 (trace) | Runs per variant. |

## Common setup (all modes)

Development is local (no local GPU or Docker). All commands run on a remote server
via `ckRemote`. Profile scripts auto-detect the backend the same way `ckBuild`/`ckRun`
do — no separate named-container setup is needed.

**Slurm login node (the default workflow):**

Profile scripts detect `srun` via `scontrol ping` and dispatch each container command
into the running GPU holder via `srun --overlap`. The holder must be running before
any GPU-mode profile script is invoked:

```bash
ckRemote ckHold --arch gfx942   # start once; keeps a GPU allocation alive
```

Then invoke profile scripts via `ckRemote`:

```bash
ckRemote --no-sync REPO=<remote-repo-path> BIN=build/bin/<target> ARCH=gfx942 ckRunProfile
```

**Normal docker server (non-Slurm):**

Start the named container once:

```bash
ssh <remote> '~/bin/dockerRun <image> <container>'
```

Then pass `CONTAINER` when invoking profile scripts:

```bash
ckRemote --no-sync CONTAINER=<container> REPO=<remote-repo-path> BIN=build/bin/<target> ckRunProfile
```

**`REPO`** must be the **remote** absolute path to the CK project root — the same
path the container bind-mounts. The local checkout path is irrelevant. Do not use
`$PWD`; the cwd on the remote may differ. Prefer the literal remote path, e.g.
`REPO=/home/you/composable_kernel`.

1. **GPU arch.** Pass `ARCH=gfx942` explicitly (required on Slurm; auto-detected on
   docker servers from `rocminfo`). For `ckRemote ckBuild gfx942 <target>`, the arch
   is also a positional argument.

Every mode auto-adds `ck_profile_out/` to the repo's **`.git/info/exclude`** via
`git_exclude_outdir.sh` in `~/lib/ck-profile/` (idempotent, worktree-correct), so the output never
shows in `git status` — the tracked `.gitignore` is left untouched.

## Static mode

Run the bundled wrapper (separate throwaway build dir; the main `build/` is
untouched). The build is slow and template-heavy — run in background / delegate.
Run on the remote (auto-detects srun/docker backend):

```bash
ckRemote REPO=<remote-repo-path> TARGET=<target> ARCH=gfx942 ckStaticProfile
```

On a docker server, add `CONTAINER=<container>`.
On Slurm, ensure `ckHold` is running first; the script dispatches via the holder.

It builds with the resource-usage remark flag, parses the log (demangling kernel
names with `c++filt`), and prints a summary; full report + CSV land under the
repo at `ck_profile_out/static/build_report.{md,csv,html}` (the instrumented
build tree is kept in the `ck_profile_out/static/build/` subfolder; so the reports
are visible on the host; the `.html` is a self-contained chart view —
occupancy histogram, effective-VGPR bars with the cliff marked, spill rows
highlighted). Report scope: for a focused ask ("spills",
"occupancy", "LDS"), filter to the relevant columns; otherwise give the overview and
worst offenders. The occupancy cliff to watch is **129 effective VGPRs**
(128→4 waves, 129→3 waves). See REFERENCE.md.

## Dynamic mode

1. **Ensure the binary exists.** If `build/bin/<target>` is missing, build it with
   `ckRemote ckBuild` (rsyncs source, auto-detects backend, configures with a compiler
   cache — delegate it, logs are large):

   ```bash
   ckRemote ckBuild gfx942 --minimal <target>
   ```

   `ckBuild` is incremental by default (reuses `build/`); add `--scratch` only after
   an arch/toolchain/cmake-option change. `CONTAINER` is not used by `ckBuild`.
2. **Profile.** The harness writes per-run CSVs under
   `ck_profile_out/dynamic/raw/<variant>/run_NN/` and is robust to PMC counter-capacity
   crashes (kills orphaned app processes; cleans the `.rocprofv3/` scratch dir).
   On Slurm, ensure `ckHold` is running first:

   ```bash
   ckRemote ckHold --arch gfx942   # keep GPU allocated
   ckRemote --no-sync REPO=<remote-repo-path> BIN=build/bin/<target> ARCH=gfx942 \
     BASE_ARGS=-v=0 SWEEP_FLAG=<flag> SWEEP_VALS=<v1,v2,...> NRUNS=<n> ckRunProfile
   ```

   On a docker server, replace `ARCH=gfx942` with `CONTAINER=<container>` (arch
   auto-detected from `rocminfo`). Use `--no-sync` if source is already synced.

   Omit `SWEEP_FLAG`/`SWEEP_VALS` for a single variant. A long sweep
   (variants × nruns × passes) takes minutes — run in background.
3. **Aggregate + classify.**

   After pulling results locally (`ckRemote pull`), run:

   ```bash
   ckAggregate --raw ck_profile_out/dynamic/raw \
     --arch gfx942 [--iters N | --marker <kernel-substr>]
   ```

   `--iters` (e.g. warmup+repeat) or `--marker` (a kernel firing once per
   pipeline) gives per-iteration numbers; otherwise values are per-run. Writes
   `summary.md` (readable report), `summary_overall.csv`, and
   `per_kernel_<variant>.csv`.
4. **Report.** `ckAggregate` writes `summary.md` (markdown), `summary.html`
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

## Trace mode

A dispatch timeline (one run is enough; supports the same sweep as dynamic).
On Slurm, ensure `ckHold` is running:

```bash
ckRemote --no-sync REPO=<remote-repo-path> BIN=build/bin/<target> ARCH=gfx942 \
  BASE_ARGS=-v=0 SWEEP_FLAG=-prec SWEEP_VALS=fp16,bf16 NRUNS=1 PC_SAMPLING=1 ckTraceProfile
```

On a docker server, replace `ARCH=gfx942` with `CONTAINER=<container>`.

Each run writes two views of the same trace under
`ck_profile_out/trace/raw/<variant>/run_NN/`:

- **`timeline.html`** — the in-editor view: a self-contained, offline HTML
  rendered from the sys-trace CSVs by `trace_timeline.py` (host HIP-API lane over
  a GPU dispatch lane on a shared time axis; ctrl+wheel zoom at cursor, drag pan,
  hover for name/start/duration). Open it in Cursor's Live Preview — no browser.
  It is the **useful 80%** (ordering, gaps, overlap, who dominates wall time), not
  a perfetto clone: no flows, counter tracks, SQL, or CPU-scheduling.
- **`trace_results.pftrace`** — the full perfetto trace for the remaining 20%
  (flows, counters, CPU sched, nanosecond zoom). Open <https://ui.perfetto.dev> and
  drag it in (the file is local; only the viewer is web).

The reading guide is in `ck_profile_out/trace/index.md`. PC sampling is beta and
best-effort — if the driver lacks support the run reports `pc_sampling=unsupported`
and continues. The emitted `*_kernel_trace.csv` feeds both `timeline.html` and the
depgraph runtime graph. Use **dynamic** for absolute numbers (`--sys-trace` adds
overhead); use **trace** to see ordering, gaps, and host launch latency.

## CFG mode

Per-kernel ISA control-flow graphs as Graphviz DOT (no GPU run):

```bash
ckRemote --no-sync REPO=<remote-repo-path> BIN=build/bin/<target> ARCH=gfx942 ckCfgProfile
```

On Slurm, cfg dispatches into the holder with `_CK_EXEC_GPU=0` (no GRES claimed
in the overlap step, so a running holder is sufficient but no GPU is required).
On a docker server, add `CONTAINER=<container>`.

Extracts the amdgcn code object (`roc-obj-ls`/`roc-obj-extract`), disassembles it
(`/opt/rocm/llvm/bin/llvm-objdump -d`), and writes one `ck_profile_out/cfg/dot/<kernel>.dot`
per kernel plus `ck_profile_out/cfg/index.md` (reading guide + blocks/edges/insns
per kernel, names demangled via `c++filt`). DOT only — preview in VS Code's
Graphviz extension, or `dot -Tsvg` where graphviz is available. Basic-block /
edge rules: see REFERENCE.md.

## Depgraph mode

Two dependency graphs as DOT:

After pulling results locally (`ckRemote pull`):

```bash
ckDepgraph --mode both \
  --raw ck_profile_out --out ck_profile_out/depgraph
```

- `dot/data_dependency.dot` — the logical producer→consumer DAG over workspace
  buffers, encoded from `ssd_fwd.hpp` launch order (last-writer-wins handles the
  reused `pa`/`pb` scratch). Needs no GPU run.
- `dot/runtime_trace.dot` — the as-executed dispatch graph from a rocprofv3
  kernel-trace CSV (`--raw` searches for `*kernel_trace.csv`; or `--trace-csv`).
  Run `trace` or `dynamic` first to produce one. `--mode data` or `runtime`
  selects a single graph. A reading guide is written to
  `ck_profile_out/depgraph/index.md`. DOT only.

## Compute mode

Deep microarchitecture analysis with rocprof-compute (roofline / speed-of-light /
memory hierarchy). **This is the only mode that modifies the container.**

```bash
ckRemote --no-sync REPO=<remote-repo-path> BIN=build/bin/<target> ARCH=gfx942 BASE_ARGS=-v=0 ckComputeProfile  # slow (multi-pass) — run in background
```

On a docker server, add `CONTAINER=<container>`.

On first use on a **docker server**, it installs the `rocprofiler-compute` apt package
**as root** (`docker exec -u 0`; the default user's sudo needs a password).
**On Slurm**, ephemeral `--rm` containers cannot be modified — pre-install
`rocprofiler-compute` in the image before using compute mode. The apt package
ships only the launcher; its Python deps (`requirements.txt`) are **not** apt —
the official install uses pip, and Ubuntu 24.04 blocks system pip (PEP 668), so
the script installs them into a **persistent venv at
`$HOME/pyenv/rocprof-compute-py<ver>`** (python version in the name; override with
`VENV=`; reused across runs, reversible: delete the dir; `uv` is used
automatically if installed, else stdlib `venv`+`pip`). The venv is built with the
**container's** python and is **container-only** — the host python differs (e.g.
3.10 vs 3.12) and the host cannot run rocprof-compute anyway. It profiles into
`ck_profile_out/compute/raw/<wl>`, exports the analysis as per-panel CSVs
(`analyze --output-format csv`), then `compute_report.py` renders a **styled
`ck_profile_out/compute/<wl>_report.html` + `<wl>_report.md`** (Speed-of-Light
%-of-peak gauges, top-kernel bars, a derived bottleneck verdict) — the same dark
theme as the other reports. The CSV panels, the text dump (`<wl>_analyze.txt`),
the workload, and `profile.log` stay under `raw/`. Re-open interactively with
`rocprof-compute analyze -p ck_profile_out/compute/raw/<wl>` (add `--gui`).

## Diagnose & recommend

Profiling is not done when the report renders — it is done when you have named the
limiter and what to try next. After the relevant mode(s) report:

1. **Read the verdict** (dynamic/compute) or the resource ceiling (static).
2. **Match the diagnosis playbook** in REFERENCE.md: find the pattern(s) whose
   *Signals* the data satisfies. Most kernels match two to four; note each.
3. **Emit ranked optimization directions** (REFERENCE.md rule): at most 3–5, ranked
   by evidence strength × roofline headroom × inverse effort, each citing specific
   counter values and the mode that would confirm the fix. No `Est. Speedup` oracle
   exists for rocprofv3 — rank by judgement, and say so when a signal is inferred or
   needs an added counter / PC sampling.

This step is what the dev-team profiler role consumes to drive its candidate loop,
and what a solo user reads to pick the next change.

## Combining modes

The six modes are independent in output, but **always run them strictly
sequentially — never two at once**. Finish and verify one mode before starting
the next. Why: concurrent runs conflict — two `rocprofv3`/`rocprof-compute`
instances contend for the GPU and hardware counters (PMC capacity, orphaned app
processes that hold the device), and a heavy build (static, compute) running
alongside a timing-sensitive GPU run (dynamic, trace) saturates the container and
skews the measurements. This applies even to modes that look independent (e.g.
cfg + dynamic): do not background one mode and launch another while it runs. If a
single mode is long (static build, compute multi-pass), background just that one
and wait for it before starting anything else. A sensible order when running
several: static → dynamic → trace → cfg → depgraph → compute (depgraph's runtime
graph wants a trace/dynamic kernel-trace to already exist).

The views reinforce each other: the static occupancy *ceiling* explains a low
achieved-occupancy / latency-bound dynamic verdict; the trace timeline and
depgraph runtime graph *show* the serialization behind it; cfg explains
per-kernel branch structure; compute attributes limits to microarchitecture
units.
