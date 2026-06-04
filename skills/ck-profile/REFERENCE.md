# ck-profile reference

## Why two rocprofv3 modes

| Mode | Command | Gives | Notes |
|------|---------|-------|-------|
| Kernel trace | `--kernel-trace --stats --summary -T` | per-launch timing; static VGPR/SGPR/LDS/scratch; per-kernel and domain stats | does not perturb timing |
| PMC multipass | `-i counters.txt` | L2 hit/miss, HBM fetch/write KB, occupancy, VALU% | serializes kernels; trust trace for timing, PMC for counters |

Counter mode is aggregate (per kernel). For per-instruction stall reasons use
`rocprofv3` PC sampling (`--pc-sampling-method ...`) or ATT (`--att-*`).

## counters.txt (one hardware pass per `pmc:` line)

```
pmc: TCC_HIT TCC_MISS                  # pass 1 — L2 hit ratio = HIT/(HIT+MISS)
pmc: FETCH_SIZE                        # pass 2 — KB read from HBM  (own pass: EA counters)
pmc: WRITE_SIZE                        # pass 3 — KB written to HBM (own pass)
pmc: MeanOccupancyPerCU               # pass 4 — resident wavefronts per CU
pmc: VALUBusy SALUBusy                # pass 5 — % time vector / scalar ALU busy (0..100)
pmc: MemUnitStalled                   # pass 6 — % time the memory unit is stalled
pmc: LDSBankConflict                  # pass 7 — LDS bank-conflict count
pmc: SQ_VALU_MFMA_BUSY_CYCLES SQ_WAVES # pass 8 — matrix-engine busy cycles; wavefronts
```

`FETCH_SIZE` and `WRITE_SIZE` are derived from TCC_EA counters and **exceed the
per-pass counter budget if combined** (rocprof error 38, then it leaves an
orphaned app process holding the GPU — `run_profile.sh` kills orphans between
runs). Keep them in separate passes. `FETCH_SIZE`/`WRITE_SIZE` units are **KB**.

`aggregate.py` is counter-set-agnostic: it scans every `pmc_*` dir, so you can
add/remove `pmc:` lines without editing it. Verify each new group fits one pass
(`rocprofv3 --pmc ... -- <app>` exits 0). List counters with
`rocprofv3 --list-avail`. `SQ_VALU_MFMA_BUSY_CYCLES` is reported as **raw cycles
only** (non-zero ⇒ matrix engine used); converting it to a % needs per-CU
normalization, so it is not used in the verdict — use omniperf for an MFMA
roofline. Other useful extras: `SPI_RA_WVLIM_STALL_CSN` (occupancy-limited),
`SQ_WAIT_INST_*`.

## Output CSV layout (per run)

Per-run raw data lives under `ck_profile_out/dynamic/raw/<variant>/`:

```
run_NN/
  t_kernel_trace.csv     raw per-launch: timestamps, VGPR/SGPR, LDS, scratch, grid/block
  t_kernel_stats.csv     per-kernel aggregate (Calls, TotalDurationNs, Percentage, ...)
  t_domain_stats.csv     total KERNEL_DISPATCH time
  pmc_1..8/p_counter_collection.csv   one row per launch per counter (Counter_Name, Counter_Value)
  {t,p}.stdout / .stderr  program output / rocprof logs
```

Aggregated reports (written to `ck_profile_out/dynamic/` by `aggregate.py`): `summary.md`,
`summary_overall.csv`, `per_kernel_<variant>.csv`, and **`summary.html`** — a
self-contained report (inline CSS/SVG bars, no CDN, opens offline) with the
device-spec table, a runtime-across-variants bar chart, per-variant roofline
gauges (occ-util/BW-util/VALU/SALU/mem-stall/L2) with a colored verdict badge,
and per-kernel breakdown bars. The static parser likewise emits
`build_report.{md,csv,html}`; the HTML adds an occupancy histogram, an
effective-VGPR bar chart with the 128/129 cliff marked, and spill/scratch rows
highlighted. HTML generation lives in the shared `html_report.py` (no
dependencies — pure string templating).

Kernel names: trace uses `-T` (GEMMs show as `kentry`); PMC shows full mangled
template names (commas inside — parse with a real CSV reader, not `cut -d,`).

## Roofline-lite classification (aggregate.py)

Two ratios per variant:
- **compute util** = `max(VALUBusy, SALUBusy)` %.
- **bandwidth util** = achieved HBM GB/s ÷ peak HBM GB/s, where achieved =
  `(FETCH_SIZE+WRITE_SIZE) bytes ÷ total kernel-active time`.

Verdict thresholds (heuristic, tune in `aggregate.py`):
- compute util ≥ 60% → **compute-bound**
- else bandwidth util ≥ 60% → **memory-bandwidth-bound**
- else both < 25% → **latency/occupancy-bound** (check occupancy, register/LDS
  limits, dependent-load stalls; run the static mode for the occupancy ceiling)
- otherwise → **mixed**

Note: `VALUBusy` may understate compute for MFMA-heavy GEMMs (the matrix engine
is a separate pipe). If `mfma_busy_cycles` is large but the verdict says
latency-bound, treat compute as a candidate and confirm with omniperf.

Peak memory-bandwidth and per-arch hardware specs both live in `gpu_specs.py`
(`PEAK_MEM_GBS` and `SPECS`), imported by both `aggregate.py` (dynamic) and
`parse_resource_usage.py` (static) so the two reports cannot disagree.
Theoretical peak from AMD specs, not host-measured, so no matching hardware is
needed. gfx IDs are confirmed against AMD's internal GFX/LLVM-target reference
sheet.

CDNA (Instinct, HBM) — exact, one product family per gfx ID:
- gfx942 (MI300X/MI325X, HBM3) = 5300
- gfx950 (MI350X/MI355X, HBM3E) = 8000
- gfx1250 (MI450/MI455X, HBM4) = 19600, gfx1251 (MI430X, HBM4) = 19600

RDNA (Radeon, GDDR) — **one gfx ID covers many SKUs with different memory**, so
the table holds the *flagship* of each family; for an exact card pass
`--peak-gbs <value>`:
- gfx1201 (RX 9070 XT) = 640, gfx1200 (RX 9060 XT) = 320
- gfx1100 (RX 7900 XTX) = 960, gfx1101 (RX 7800 XT) = 624, gfx1102 (RX 7600) = 288

Add a new arch's peak (or use `--peak-gbs`) before trusting its BW verdict.

## Device specs (`SPECS` in gpu_specs.py)

Per-arch hardware resources shown in a **Device spec** block at the top of both
the dynamic `summary.md` and the static `build_report.md`. The dynamic report
also turns one of them into a ratio: **occ util %** = measured
`MeanOccupancyPerCU` ÷ `max_waves_cu` (achieved occupancy as a fraction of the
ceiling — the occupancy analogue of BW util %). The rest (CU count, wave size,
SIMD/CU, VGPR/AGPR file, LDS/CU) are informational context for the grid size and
the static per-kernel VGPR/LDS, not computed into ratios.

| gfx | SKU(s) | CUs | wave | SIMD/CU | max waves/CU | VGPR/SIMD | AGPR/SIMD | LDS/CU |
|-----|--------|-----|------|---------|--------------|-----------|-----------|--------|
| gfx942 | MI300X/MI325X | 304 | 64 | 4 | 32 | 256 | 256 | 64 KB |
| gfx950 | MI350X/MI355X | 256 | 64 | 4 | 32 | 256 | 256 | 160 KB |
| gfx1250 | MI450/MI455X | n/a | 64 | n/a | n/a | n/a | n/a | n/a |
| gfx1251 | MI430X | n/a | 64 | n/a | n/a | n/a | n/a | n/a |
| gfx1201 | RX 9070 XT | 64 | 32 | 2 | 32 | 1536 | 0 | 128 KB |
| gfx1200 | RX 9060 XT | 32 | 32 | 2 | 32 | 1536 | 0 | 128 KB |
| gfx1100 | RX 7900 XTX | 96 | 32 | 2 | 32 | 1536 | 0 | 128 KB |
| gfx1101 | RX 7800 XT | 60 | 32 | 2 | 32 | 1536 | 0 | 128 KB |
| gfx1102 | RX 7600 | 32 | 32 | 2 | 32 | 1024 | 0 | 128 KB |

Three caveats baked into these numbers:
- **max waves/CU = 32 is derived, not quoted verbatim.** CDNA = 8 waves/SIMD × 4
  SIMD; RDNA = 16 waves/SIMD × 2 SIMD. Both give 32. The legacy "10 waves/SIMD →
  40/CU" is GCN-era and does not apply to CDNA3/RDNA3+.
- **RDNA CU counts are the flagship of each gfx family** (one gfx ID spans many
  SKUs), same convention as the bandwidth table. AGPR is 0 — RDNA has no separate
  accumulation register file.
- **gfx1250/gfx1251 (MI450/MI455X/MI430X) are unreleased**: only HBM4 bandwidth
  is public, so their `SPECS` fields are `None` and print as `n/a`. The bandwidth
  verdict still works.

Sources: ROCm GPU hardware specs page; AMD CDNA3 ISA guide + CDNA3/CDNA4
whitepapers; TechPowerUp GPU database (RDNA SKUs); GPUOpen "Occupancy explained".

## Bottleneck taxonomy (what to look at next)

Top level is the roofline (compute vs bandwidth vs below-both). When below both,
the cause is one of:

| Category | Detect with |
|----------|-------------|
| Compute: VALU / MFMA / SALU / transcendental | `VALUBusy`, `SQ_VALU_MFMA_BUSY_CYCLES`, `SALUBusy`, `SQ_INSTS_VALU_TRANS_*` |
| Memory level: HBM / L2 / L1 / LDS / scratch | fetch+write vs peak; `TCC_HIT/MISS`; `LDSBankConflict`; `scratch_size` |
| Occupancy limited: registers / LDS / wave cap | effective VGPR (static mode); `SPI_RA_*_STALL_CSN`; `MeanOccupancyPerCU` |
| Latency: dependent loads | `SQ_WAIT_INST_*`, low occupancy |
| Front-end: I-cache / issue | `SQC_ICACHE_BUSY_CYCLES`, `SQ_IFETCH_LEVEL` |
| Efficiency: divergence / bank conflict / atomics / barriers | PC sampling / ATT; `LDSBankConflict` |
| Work distribution: tail / imbalance / partition camping | grid vs CU count; channel skew |
| System: launch overhead / PCIe / multi-GPU / throttling | many tiny kernels (trace count); H2D/D2H; XGMI/RCCL; clock |
| Algorithmic: serial fraction (Amdahl) | sequential kernels in the trace |

## Static mode (compile-time resource usage)

`static_profile.sh` builds the target with `-Rpass-analysis=kernel-resource-usage`
in a separate build dir (`ck_profile_out/static/build/`, the project's own
`build/` untouched) with the reports at `ck_profile_out/static/` (host-visible), then
`parse_resource_usage.py` extracts one block of remarks per kernel and demangles
names with `c++filt`. Raw format (ANSI-colored; each line tagged
`[-Rpass-analysis=kernel-resource-usage]`):

```
remark: Function Name: <mangled>
remark:     TotalSGPRs: 58
remark:     VGPRs: 256
remark:     AGPRs: 143
remark:     ScratchSize [bytes/lane]: 0
remark:     Dynamic Stack: False
remark:     Occupancy [waves/SIMD]: 1
remark:     SGPRs Spill: 0
remark:     VGPRs Spill: 0
remark:     LDS Size [bytes/block]: 17408
```

Report CSV columns: `source,kernel,vgprs,agprs,effective_vgprs,total_sgprs,
scratch_size,occupancy,sgpr_spill,vgpr_spill,lds_size,dynamic_stack`.

Effective VGPRs and the occupancy cliff:
- CDNA3 (gfx94x): `EffVGPRs = max(VGPRs, AGPRs)` (separate register files)
- CDNA4 (gfx95x): `EffVGPRs = VGPRs + AGPRs` (unified file)
- Cliff at **129 effective VGPRs**: 128 → 4 waves/SIMD, 129 → 3 waves (one extra
  register costs 25% of wave slots). Non-zero scratch/spill or Dynamic Stack:True
  are red flags (global-memory round-trips per lane).

This is the *ceiling*; the dynamic mode's `MeanOccupancyPerCU` is what was
*achieved*. A low achieved occupancy with a high VGPR count points at register
pressure as the limiter.

## Trace mode (rocprofv3 timeline)

`trace_profile.sh` runs `rocprofv3 --sys-trace -f pftrace csv` once per variant.
`--sys-trace` records HIP + HSA API, kernel dispatches, and memory ops on one
time axis with host↔device correlation. Output per run:

```
trace/raw/<variant>/run_NN/
  timeline.html                  offline HTML timeline (open in Live Preview)
  trace_results.pftrace          perfetto timeline (drag into ui.perfetto.dev)
  trace_kernel_trace.csv         dispatch order/timing (feeds timeline + depgraph)
  trace_hip_api_trace.csv, trace_hsa_api_trace.csv, trace_memory_*_trace.csv
  pc.{stdout,stderr}             PC-sampling pass (best-effort)
```

### timeline.html (trace_timeline.py)

`trace_profile.sh` calls `trace_timeline.py` (pure stdlib, runs on the host) per
run to render an offline-standalone HTML timeline from the CSVs — the in-editor
alternative to the perfetto web UI for a remote `.pftrace`. Lanes, top to bottom:
**HIP API** (host), an optional **COPY** lane (SDMA `memory_copy` rows when any
fall in the window), and **GPU** (kernel dispatches). Construction notes:

- `Kernel_Name` carries template commas, so it parses with `csv.DictReader`
  (never `cut -d,`); device labels use the shared `aggregate.short`.
- Host lane is filtered to the runtime loop (`launch`/`memcpy`/`memset`/
  `synchron`/`event`), dropping one-time setup (`__hipRegister*`, push/pop config,
  `hipGetDevice*`). Host/copy events are kept only if they overlap the kernel
  window; the display origin then spans all kept events so host launches that
  precede the first kernel are not pushed to negative offsets.
- Device kernels get a stable color per short-name (first-seen order) so the
  repeating pipeline is visually obvious; host bars are colored by kind
  (launch / sync / mem / event).
- Bars are server-rendered at a "fit" scale (≈1500 px for the full span) with
  `data-t0`/`data-du` (µs); a small static `<script>` adds ctrl+wheel zoom at the
  cursor, drag-to-pan (native horizontal scroll), and a `textContent` tooltip
  (`white-space:pre-wrap`, so template `<…>` is never reinterpreted as HTML).
  Without JS the initial fit-scale timeline still shows; CSS/JS are inline (no
  CDN), so it opens offline.
- **Fidelity:** the useful 80% (ordering, gaps, overlap, dominant kernel, host↔
  device overlap). Not in scope vs. perfetto: flow arrows, counter tracks, SQL
  queries, CPU scheduling, sub-µs precision — use the `.pftrace` for those.

PC sampling (`--pc-sampling-beta-enabled --pc-sampling-method stochastic
--pc-sampling-unit instructions`) is beta and **driver-dependent** — on this
gfx942 container it reports unsupported and is skipped. Trace vs dynamic: same
tool, different subsystem. dynamic = aggregated PMC counters + a verdict (numbers,
with variance, but PMC serializes kernels); trace = a single-run event timeline
(structure: ordering, gaps, launch latency, but `--sys-trace` adds overhead).
Use dynamic for *how much*, trace for *when / in what order*.

## CFG mode (ISA control-flow graphs)

`cfg_dump.sh` → `cfg_to_dot.py`. The device code object is extracted from the
host binary (`roc-obj-ls` gives the `hipv4-amdgcn-amd-amdhsa--gfx<arch>` URI,
`roc-obj-extract` writes a `.co`) and disassembled with
`/opt/rocm/llvm/bin/llvm-objdump -d`. Note: `llvm-objdump` on the *executable*
shows x86 host code — you must extract the device object first.

`llvm-objdump` emits, per instruction:
`<tab>MNEMONIC ops   // <hexaddr>: <encoding> [<symbol+0xoff>]`. The trailing
`<symbol+0xoff>` on branches already resolves the target, so the parser builds
basic blocks without decoding relative offsets:

- **Leaders**: kernel entry; any branch target; the instruction after any
  `s_branch` / `s_cbranch*` / `s_endpgm`.
- **Terminators / edges**: `s_branch` → unconditional edge to target;
  `s_cbranch*` → taken edge (target) + fall-through edge (next); `s_endpgm` /
  `s_setpc*` → terminal (no successor); anything else → fall-through.
- Trailing inter-kernel padding after the final `s_endpgm` (alignment `s_nop`s)
  is dropped.

One `cfg/<short>.dot` per kernel (dark-themed digraph: blocks = boxes labelled
`addr-range / N insn / terminator`; edge colors green=taken, grey=fall,
violet=jump) plus `index.md` (blocks/edges/insns, demangled). **DOT only** —
preview in VS Code's Graphviz extension or `dot -Tsvg x.dot` where graphviz
exists (not installed in-container by choice).

## Dependency graphs (depgraph.py)

Two complementary `.dot` views:

- **data_dependency.dot** — logical producer→consumer DAG. `SSD_PIPELINE` at the
  top of `depgraph.py` encodes each stage's read/write buffers exactly as launched
  in `ssd_fwd.hpp`; edges are added by **last-writer-wins over program order**, so
  the reused `pa`/`pb` scratch buffers correctly link each pack to the single GEMM
  that consumes it. Input/output tensors are ellipse nodes, kernels are boxes,
  edges labelled with the connecting buffer. Tied to the SSD pipeline; extend the
  table for other targets.
- **runtime_trace.dot** — as-executed graph from a rocprofv3 kernel-trace CSV
  (any `*kernel_trace.csv` under `--raw`, or `--trace-csv`). Dispatches are sorted
  by start time; nodes = kernels (calls + total/avg µs, names via `aggregate.short`),
  edges = consecutive transitions with `xN` weights, so the recurring pipeline
  appears as a cycle.

## Compute mode (rocprof-compute)

`compute_profile.sh`. `rocprof-compute` (ROCm Compute Profiler, package
`rocprofiler-compute`) is the omniperf successor — roofline, speed-of-light, and
memory-hierarchy panels. Two install facts learned the hard way:

1. The apt package installs only the launcher (`/opt/rocm/bin/rocprof-compute`, a
   symlink into `libexec/`), often **not on the non-login `docker exec` PATH** —
   resolve it by path. Install needs **root** (`docker exec -u 0`; the default
   user's sudo wants a password).
2. The launcher is a Python app whose deps are **not** in the apt package; the
   official install runs `pip install -r
   /opt/rocm/libexec/rocprofiler-compute/requirements.txt`. Ubuntu 24.04 blocks
   system pip (PEP 668), so the script installs them into a **persistent venv**
   at `$HOME/pyenv/rocprof-compute-py<ver>` (python version in the name to avoid
   interpreter collisions; override `VENV=`; `uv venv`+`uv pip` if `uv` is
   installed, else `python3 -m venv --system-site-packages`+pip) and runs the launcher with that
   venv's python. The venv lives under `$HOME` (bind-mounted, so it persists and
   is reused across container sessions) but is **container-only**: it is built
   with the container's python (e.g. 3.12) and the host python differs (3.10), so
   the same venv can't run on the host — and the host has no in-container ROCm to
   run rocprof-compute regardless. Reversible: delete the dir.

`rocprof-compute profile -n <wl> -p <dir> -- <app>` runs the app multi-pass
(slow) and writes the workload data **directly into `<dir>`** (sysinfo.csv,
pmc_perf.csv, roofline.csv, perfmon/, ...) — there is no `workloads/<wl>/<arch>`
nesting. Analysis is exported as **per-panel CSVs** with
`analyze -p <dir> --output-format csv --output-name <name>` — note `--output-name`
must be a **bare** name (alnum/`_`/`-`, no slashes/dots) created in the **current
working dir**, so run it with the working dir set to `raw/`. `compute_report.py`
then reads those panels (`2.1_System_Speed-of-Light.csv`, `0.1_Top_Kernels.csv`,
`1.1_System_Info.csv`, ...) and renders `<wl>_report.html` + `<wl>_report.md`:
Speed-of-Light rows become %-of-peak gauges, top kernels become bars, and a
verdict is derived (max FLOP/IOP % vs max cache/LDS BW %, same taxonomy as the
dynamic roofline-lite). A plain-text `analyze` dump is also kept in
`raw/<wl>_analyze.txt`. `--gui` serves the interactive dashboard. Use this for the
MFMA/roofline attribution that the dynamic mode's single `VALUBusy` cannot give.

## Known gotchas

- `--truncate-kernels` (long form) can trip "dangerous command" shell guards
  because it contains the word *truncate*; use `-T`.
- The container login shell does not start in the repo; always set the working
  dir (`docker exec -w $REPO ...`).
- Default program options run CPU verification; pass `-v=0` for profiling and do
  one `-v=1` run separately to confirm correctness.
