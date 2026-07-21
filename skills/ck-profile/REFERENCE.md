# ck-profile reference

## GPU execution model and terminology

The reports and the CK source mix AMD, HIP/CUDA, and CK names for the same
things. Canonical AMD/ROCm terms are used throughout this skill; this table maps
the synonyms.

| Concept | AMD / ROCm (used here) | HIP / CUDA | NVIDIA HW | CK config field |
|---|---|---|---|---|
| one execution lane | work-item (a *lane*) | thread | thread | — |
| lockstep SIMT group | **wavefront** (64 lanes on CDNA, 32 on RDNA wave32) | warp (implicit) | warp (32 lanes) | the lanes of one `*_Warp` |
| group sharing LDS + barriers | **workgroup** | block / thread block | thread block | one *block tile* = one workgroup |
| whole launch | grid | grid | grid | — |
| physical core | **Compute Unit (CU)** | — | SM | — |
| issue unit inside a CU | **SIMD** (4 per CU on CDNA) | — | SM sub-partition | — |
| resident-wave budget | waves/SIMD (8 → 32/CU on gfx942) | occupancy | occupancy | — |

Hardware nesting (gfx942): GPU → 304 **CU** → 4 **SIMD** each. A SIMD issues one
64-lane **wavefront** per cycle and holds up to **8 wavefronts resident** (= 32
per CU) for latency hiding. Each SIMD owns a 256-entry VGPR file plus a 256-entry
AGPR file; LDS (64 KB) and L1 are shared by the whole CU.

Launch nesting: a kernel launch is a **grid** of **workgroups (blocks)**; each
workgroup is placed on one CU and split into 64-lane **wavefronts** (a 256-thread
block is 4 wavefronts). Work-items in a workgroup share LDS and can
`__syncthreads()`; work-items in different workgroups cannot.

Two naming traps:

- **"wave" means "wavefront"**, not a 32-lane NVIDIA warp. A CDNA wavefront is 64
  lanes. The PMC counters (`SQ_WAVES`, `MeanOccupancyPerCU`) and the static
  remark `Occupancy [waves/SIMD]` all count 64-lane wavefronts.
- **CK names the per-block wavefront grid `*_Warp`** (`M_Warp`/`N_Warp`/`K_Warp`),
  an NVIDIA-ism. On AMD each is a wavefront, so `M_Warp=2, N_Warp=2, K_Warp=1` is
  **4 wavefronts**, not 4 NVIDIA warps. The grid is only a wavefront *count*;
  work-items per block = wavefronts × the wavefront size, and the wavefront size is
  set by the build target (64 on CDNA/gfx9, 32 on RDNA wave32), not by the config.
  So 4 wavefronts is 256 work-items on gfx942, 128 on an RDNA wave32 build.

## Why two rocprofv3 modes

| Mode | Command | Gives | Notes |
|------|---------|-------|-------|
| Kernel trace | `--kernel-trace --stats --summary -T` | per-launch timing; static VGPR/SGPR/LDS/scratch; per-kernel and domain stats | does not perturb timing |
| PMC multipass | `-i counters.txt` | L2 hit/miss, HBM fetch/write KB, occupancy, VALU% | serializes kernels; trust trace for timing, PMC for counters |

Counter mode is aggregate (per kernel). For per-instruction stall reasons use
`rocprofv3` PC sampling (`--pc-sampling-method ...`) or ATT (`--att-*`).

## counters.txt (one hardware pass per `pmc:` line)

```text
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
orphaned app process holding the GPU — on docker/srun each run dispatches in
its own ephemeral `--rm` container, so the orphan dies with the container; on
`MODE=direct` there is no container, so `kill_orphans` in `ckExec` `pkill`s
the target binary after each pass instead). Keep them in separate passes.
`FETCH_SIZE`/`WRITE_SIZE` units are **KB**.

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

```text
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

## MFMA instruction family

AMD matrix cores run GEMMs via MFMA (Matrix Fused Multiply-Add) instructions;
their busy cycles show up in `SQ_VALU_MFMA_BUSY_CYCLES` and drive the compute-mode
roofline. Naming: `v_mfma_<accum>_<M>x<N>x<K>_<input-type>` (e.g.
`v_mfma_f32_32x32x8_f16` = fp16 inputs, fp32 accumulate, a 32×32 output tile, K=8
contraction). Two axes vary independently:

- **M×N** is the accumulator tile a single wavefront produces. 32×32 means fewer,
  larger instructions and more VGPR/AGPR per wavefront; 16×16 means smaller
  fragments and a deeper K per instruction.
- **K** is the contraction depth per instruction, roughly `bytes_per_lane /
  sizeof(element)`, so it grows as the element narrows.

| Input type | Typical gfx942 shapes (M×N×K) |
|---|---|
| fp32 | 16×16×4, 32×32×2 |
| fp16 / bf16 | 16×16×16, 32×32×8 |
| int8 | 16×16×32, 32×32×16 |
| fp8 / bf8 | 16×16×32, 32×32×16 |
| fp64 | 16×16×4 |

K doubles from fp16's 32×32×8 to int8/fp8's 32×32×16 as the element halves to one
byte. The fp16/bf16/fp32 rows are firm; the exact int8/fp8 set is arch-specific,
so get the authoritative list from AMD's `amd_matrix_instruction_calculator`
(`--architecture gfx942 --list-instructions`) rather than this table.

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

## Diagnosis playbook (pattern → fix)

The taxonomy says *where* to look; this playbook says *what it means and what to do*.
Each entry is **Signals** (a predicate over data we actually collect), **Why**,
**First-line fix** (cheapest), **Deeper fixes**, **Exceptions** (when the pattern is
expected and should be left alone), and **Confirm with** (the mode/counter that
corroborates). Most kernels match two to four patterns at once; rank by magnitude
(the ranked-directions rule below), fix the biggest first.

Signal vocabulary. Counters in the default `scripts/counters.txt`: `VALUBusy`,
`SALUBusy`, `SQ_VALU_MFMA_BUSY_CYCLES`, `SQ_WAVES`, `TCC_HIT`/`TCC_MISS`,
`FETCH_SIZE`, `WRITE_SIZE`, `MeanOccupancyPerCU`, `MemUnitStalled`,
`LDSBankConflict`. Derived by `aggregate.py`: **occ-util %** (achieved ÷ max
waves/CU), **BW-util %** (achieved HBM ÷ peak), achieved BW, L2 hit %. From the
static report: effective VGPR, occupancy ceiling, `scratch_size`, spill, dynamic
stack. Counters tagged **(add a pmc line)** are not in the default set — add them to
`counters.txt` (one group per pass; verify the group fits one pass) before relying
on them. Signals tagged **(PC sampling)** need per-instruction sampling, which is
beta and driver-dependent (reports unsupported on the gfx942 container), so treat
them as best-effort or fall back to `cfg`.

### Memory-bandwidth-bound (HBM)

- **Signals:** BW-util % ≥ 60; achieved BW near peak (`gpu_specs.py PEAK_MEM_GBS`); `FETCH_SIZE`+`WRITE_SIZE` large per iteration.
- **Why:** the kernel moves bytes faster than it computes; HBM is the limiter.
- **First-line fix:** cut bytes — fuse producer/consumer kernels (see depgraph), reuse via LDS, narrow dtype (fp16/bf16/fp8) if accuracy allows.
- **Deeper fixes:** recompute instead of reloading; tile so reused data stays in L2/LDS; pack/quantize the workspace.
- **Exceptions:** genuinely streaming kernels (copy, elementwise) — already optimal at high BW-util.
- **Confirm with:** dynamic verdict; `compute` mode roofline (DRAM ceiling).

### Compute-bound — VALU / SALU

- **Signals:** `VALUBusy` (or `SALUBusy`) ≥ 60%; BW-util low.
- **Why:** the vector (or scalar) ALU pipe is saturated.
- **First-line fix:** reduce instruction count — strength-reduce, hoist invariants, vectorize (`global_load_dwordx4`), drop redundant address math (often the SALU source).
- **Deeper fixes:** move matrix work to MFMA; rebalance VALU/SALU; pick a tile with less per-element overhead.
- **Exceptions:** legitimately arithmetic-heavy kernels already near peak.
- **Confirm with:** `compute` mode speed-of-light; `cfg` for the hot straight-line block.

### Compute-bound — MFMA / matrix

- **Signals:** `SQ_VALU_MFMA_BUSY_CYCLES` large while `VALUBusy` is modest (the dynamic verdict may then read latency-bound because `VALUBusy` undercounts the matrix pipe).
- **Why:** the matrix engine is the real worker; the roofline-lite verdict can't see it (raw cycles, no per-CU normalization).
- **First-line fix:** treat as compute-bound; improve MFMA feeding (LDS staging, larger K per instruction) rather than chasing the misleading latency verdict.
- **Deeper fixes:** pick MFMA shapes matched to the dtype (see the MFMA table above); overlap MMA with global/LDS loads.
- **Exceptions:** none — this is the desired state for a GEMM; the note exists to avoid misreading the verdict.
- **Confirm with:** `compute` mode (MFMA roofline) — the only mode that attributes this properly.

### Occupancy capped by registers

- **Signals:** static effective VGPR at/over the **129 cliff** (128→4 waves, 129→3); low `MeanOccupancyPerCU` / occ-util %.
- **Why:** each wave reserves too many VGPRs, so fewer waves stay resident to hide latency.
- **First-line fix:** `__launch_bounds__(block, min_waves)` to cap the register budget; cut live values.
- **Deeper fixes:** split the kernel; recompute instead of caching; shrink the tile.
- **Exceptions:** large fused kernels (FlashAttention-style) that trade occupancy for upstream savings.
- **Confirm with:** `static` mode (the ceiling) vs dynamic occ-util % (the achieved).

### Occupancy capped by LDS

- **Signals:** LDS/block (static) high relative to LDS/CU (`gpu_specs.py lds_kb_per_cu`); low occ-util % with VGPR below the cliff.
- **Why:** the workgroup's LDS allocation limits resident workgroups per CU.
- **First-line fix:** shrink the LDS tile, or split the LDS-heavy phase.
- **Deeper fixes:** stage in smaller chunks; reuse one LDS buffer across phases.
- **Exceptions:** kernels deliberately trading occupancy for large-tile reuse.
- **Confirm with:** `static` LDS column; dynamic occ-util %.

### Register spill / scratch

- **Signals:** static `scratch_size` > 0, non-zero spill, or dynamic stack (highlighted rows).
- **Why:** the compiler ran out of registers and spilled to scratch (global-backed) — per-lane DRAM traffic on every access.
- **First-line fix:** `__launch_bounds__`; remove the largest live arrays.
- **Deeper fixes:** split the kernel; move per-thread arrays to LDS with explicit indexing.
- **Exceptions:** rarely acceptable; spill almost always costs more than it saves.
- **Confirm with:** `static` mode (authoritative); shows even without a GPU run.

### Latency-bound — dependent loads

- **Signals:** the roofline-lite **below-both** verdict (compute util < 25% **and** BW-util < 25%, per the thresholds above); corroborated by low occ-util % and elevated `MemUnitStalled`; `SQ_WAIT_INST_*` **(add a pmc line)**.
- **Why:** waves issue a load then stall on the result before the next dependent op, and there aren't enough other waves resident to hide it.
- **First-line fix:** add ILP — unroll so several loads are in flight before the first is used; raise occupancy (see the two occupancy patterns).
- **Deeper fixes:** async/bulk loads; software-pipeline (preload tile N+1 while computing N); move reuse to LDS.
- **Exceptions:** pointer-chasing / graph traversal — the dependency chain is fundamental.
- **Confirm with:** `trace` (gaps between small dispatches); `static` (is it the occupancy ceiling?).

### LDS bank conflicts

- **Signals:** `LDSBankConflict` high relative to LDS access volume.
- **Why:** LDS has 32 banks; same-bank accesses in a wave serialize.
- **First-line fix:** pad the leading dimension (`tile[N][N+1]`) to break the stride.
- **Deeper fixes:** swizzle (XOR-scramble) indices; restructure so lanes hit distinct banks.
- **Exceptions:** broadcast reads (all lanes same address) are conflict-free; low LDS volume — ignore.
- **Confirm with:** dynamic `LDSBankConflict`; `cfg` to locate the `ds_*` ops.

### Uncoalesced / low-utilization HBM traffic

- **Signals:** achieved BW low while `FETCH_SIZE` is high (bytes moved but throughput poor); per-access coalescing metrics need **(PC sampling)** — rocprofv3 has no direct sectors/request counter like NCU.
- **Why:** lanes in a wave touch non-contiguous addresses, so hardware fetches sectors only a few lanes use.
- **First-line fix:** rework the thread↔data map so consecutive lanes read consecutive addresses; vectorize loads.
- **Deeper fixes:** AoS→SoA; stage through LDS as a transposer.
- **Exceptions:** gather/scatter by random index (embedding, sparse) — inherently uncoalesced; sort indices for locality if feasible.
- **Confirm with:** `compute` mode (L1/L2 sector efficiency); `cfg`/source for the offending load.

### Atomics contention

- **Signals:** high L2 traffic with low compute throughput; atomic-specific counters (`TCC_EA_*` atom/red) need **(add a pmc line)**.
- **Why:** many threads atomically update few locations and serialize.
- **First-line fix:** reduce hierarchically — wave-level (`ds_swizzle`/DPP/`__shfl`), then LDS within the workgroup, then one global atomic per workgroup.
- **Deeper fixes:** LDS histogram flushed in one coalesced pass; bucket then merge.
- **Exceptions:** RCCL-style collectives where atomics are fundamental.
- **Confirm with:** `compute` mode (L2 atomic rows).

### Barrier / synchronization overhead

- **Signals:** barrier stalls dominate **(PC sampling)**; otherwise infer from many `s_barrier` in `cfg` plus workgroup imbalance.
- **Why:** `s_barrier` waits for the slowest wave; any per-wave imbalance amplifies it.
- **First-line fix:** replace workgroup syncs with wave-scoped primitives (DPP/`ds_permute`/`__shfl`) where only wave-scope is needed; consolidate sync phases.
- **Deeper fixes:** wave-specialized producer/consumer with named barriers instead of full `s_barrier`.
- **Exceptions:** correctness-required barriers — do not remove.
- **Confirm with:** `cfg` (count `s_barrier`); PC sampling if the driver supports it.

### Pipeline bubbles (no compute/memory overlap)

- **Signals:** `trace` timeline shows a sawtooth (compute and HBM alternate, never overlap); `MemUnitStalled` high while BW also high.
- **Why:** single-buffered — load tile, compute, load next; nothing overlaps.
- **First-line fix:** double-buffer two LDS tiles; compute on A while loading B.
- **Deeper fixes:** multi-stage software pipeline with async loads.
- **Exceptions:** kernels too small to amortize the extra LDS.
- **Confirm with:** `trace` (the shape is the evidence).

### Tail / work imbalance

- **Signals:** `trace` timeline shows a long gradual tail; grid only slightly exceeds a wave; per-input work skew (e.g. variable seq-len driving the inner loop).
- **Why:** a few workgroups with more work keep running after the rest finish.
- **First-line fix:** chunk the variable work into fixed-size pieces; or split long items across more workgroups with a small post-reduction.
- **Deeper fixes:** sort/pack inputs by length; classify-and-dispatch (short vs long paths); persistent kernel with a work queue.
- **Exceptions:** kernels short enough that the tail is absolute-small.
- **Confirm with:** `trace` (tail shape); always inspect the input distribution (max/avg work ratio > 3–5 flags it).

### Small grid / CU idle

- **Signals:** total grid < CU count (`gpu_specs.py cu`), or waves/CU < 1; the chip is under-filled.
- **Why:** each workgroup sits on one CU; with fewer workgroups than CUs, some CUs idle the whole kernel.
- **First-line fix:** expose more parallelism — split-K for reductions/attention, split across heads/channels, grid-stride for cheap units.
- **Deeper fixes:** persistent kernel dequeuing work; fuse adjacent kernels for more work per launch.
- **Exceptions:** decode-style launches (batch 1) that are fundamentally small — split-K over KV is the standard mitigation.
- **Confirm with:** `static`/`trace` launch geometry; dynamic occ-util %.

### Unintended FP64

- **Signals:** FP64 pipe active in a kernel meant to be FP32; no default counter — read the disassembly (`cfg`/`llvm-objdump` for `v_*_f64`) or the source.
- **Why:** C++ literals (`1.0`, `0.5`) are `double`; `float x = a + 1.0*b` promotes the expression to FP64, slower than the intended fp32 path — and dramatically slower on parts with a reduced FP64 rate (consumer RDNA), though even on full-rate CDNA Instinct the promotion wastes the fp32 pipes.
- **First-line fix:** add the `f` suffix to every literal (`1.0f`); use `__ocml`/`*f` transcendentals.
- **Deeper fixes:** audit headers/macros for stray `double`.
- **Exceptions:** kernels that genuinely need FP64.
- **Confirm with:** `cfg` (grep for `_f64` instructions).

### Branch divergence

- **Signals:** `cfg` shows many small basic blocks / branchy structure; lanes in a wave take different paths.
- **Why:** the wave serializes divergent paths; effective lane utilization drops.
- **First-line fix:** make all lanes in a wave take the same branch (sort/partition data); predicate cheap `if/else` into `mask*a + (1-mask)*b`.
- **Deeper fixes:** restructure the algorithm to remove the data-dependent branch.
- **Exceptions:** tree-reduction tails and edge/boundary handling — not worth fighting.
- **Confirm with:** `cfg` (block count/branch density); PC sampling for branch stalls if supported.

### Front-end / I-cache

- **Signals:** `SQC_ICACHE_BUSY_CYCLES`, `SQ_IFETCH_LEVEL` **(add a pmc line)** elevated with the compute pipes idle.
- **Why:** instruction fetch can't keep the issue unit fed — usually an oversized unrolled body.
- **First-line fix:** reduce code size (dial back unrolling, shrink the instruction footprint of the hot loop).
- **Deeper fixes:** restructure so the hot path fits the I-cache.
- **Exceptions:** rare; pursue only after compute/memory/occupancy are ruled out.
- **Confirm with:** the added counters; `static` instruction count if available.

## Ranked optimization directions (the recommendation)

Profiling ends with a recommendation, not a wall of suggestions. After the verdict
and the playbook match, emit a **ranked list of at most 3–5 directions**. More than
five dilutes the signal; past the third, each usually contributes little.

There is no `Est. Speedup` oracle here — `rocprofv3` has no rule engine like Nsight
Compute. So rank by judgement, not a fabricated number:

> **priority ≈ evidence strength × roofline headroom × (1 / effort)**

- **evidence strength** — how directly the counters implicate this pattern (a clear
  ≥60% `VALUBusy` outranks an inferred barrier guess).
- **roofline headroom** — how far the limiter sits from peak (a kernel at 20%
  BW-util has more to gain from a memory fix than one already at 85%).
- **effort** — a flag rebuild (`__launch_bounds__`, `f` literals) outranks a tiling
  rewrite at equal expected gain.

Each direction cites **specific counter values**, never a vague label. Template:

```text
Ranked optimization directions — <target> (<arch>), verdict: <verdict>

1. <direction>  [effort: low|med|high]
   Evidence: <counter = value, counter = value>  (playbook: <pattern>)
   Lever: <which roofline ceiling this moves, and the current headroom>
   Confirm with: <mode/counter to re-measure after the change>

2. ...
```

Example: "1. Cap registers with `__launch_bounds__` [effort: low] — Evidence:
effective VGPR 132 (over the 129 cliff → 3 waves), occ-util 38% (playbook:
occupancy capped by registers). Lever: raises the occupancy ceiling toward 4 waves,
which should lift the 38% achieved occupancy. Confirm with: static mode (new
ceiling) + dynamic occ-util." Fill values from the actual report — the specificity
is the deliverable. State a confidence/caveat line when a key signal is inferred or
needs an added counter / PC sampling.

## Static mode (compile-time resource usage)

`static_profile.sh` builds the target with `-Rpass-analysis=kernel-resource-usage`
in a separate build dir (`ck_profile_out/static/build/`, the project's own
`build/` untouched) with the reports at `ck_profile_out/static/` (host-visible), then
`parse_resource_usage.py` extracts one block of remarks per kernel and demangles
names with `c++filt`. Raw format (ANSI-colored; each line tagged
`[-Rpass-analysis=kernel-resource-usage]`):

```text
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

```text
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
memory-hierarchy panels. Install facts learned the hard way:

1. No official ROCm image bundles it, and every dispatch runs in a fresh,
   ephemeral `--rm` container, so nothing installed at runtime persists to the
   next call unless it lands somewhere bind-mounted identically across every
   backend. The script installs it itself via pip — AMD publishes a
   self-contained `rocm[profiler]` wheel (launcher + its Python deps in one
   shot) at `https://repo.amd.com/rocm/whl-multi-arch/` (override the index
   with `ROCM_WHL_INDEX=`) — into a **persistent venv** at
   `$HOME/rocprof-compute-venv` (override `VENV=`; `uv venv`+`uv pip` if `uv`
   is installed, else `python3 -m venv --system-site-packages`+pip) and runs
   the launcher from that venv's own console-script
   (`$VENV/bin/rocprof-compute`). `$HOME` is bind-mounted at an identical path
   on every backend — `direct` runs on the host with no container at all, and
   both `docker` and `srun` build their container flags from the same
   `_docker_static_flags` in `ckCommon`, which mounts `-v "$HOME:$HOME"`
   alongside `-v "$REPO:$REPO"` — so the venv persists across runs, run IDs,
   and even different `$REPO` checkouts, with no image pre-bake needed — as
   long as `VENV=` resolves under `$HOME` or `$REPO` (anywhere else isn't
   bind-mounted, so docker/srun would reinstall from scratch every call). A
   `VENV=` override is canonicalized with `realpath -s -m` (closes off a
   relative path, but — unlike `readlink -f` — does not resolve symlinks, so
   a symlinked `$HOME` still matches the literal, unresolved path
   docker/srun bind-mount) and validated (basename must look like
   `rocprof-compute-venv*`, and the resolved path must fall under `$HOME` or
   `$REPO`) before anything is deleted, so a typo like `VENV=$HOME` or an
   override outside both roots is rejected instead of silently reinstalling
   every call or wiping the caller's home directory.
2. The venv path is fixed, with no python-version suffix, so a venv built
   against one image's `python3` could go stale if a later run uses a
   different `python3` minor version. No special handling for this: the
   existing "does it still work" check (`test -x "$RPC" && "$RPC" --version`)
   already catches a broken/incompatible venv and triggers a reinstall.
   Reversible either way: delete the dir (the `$VENV.lock` sidecar it leaves
   behind is harmless and fine to delete alongside it).
3. A shared-home-wide path means concurrent invocations (any host, any
   backend) can race on it, so the check-then-install runs under a single `flock`
   covering both the re-check and the install (same pattern as `ckCommon`'s
   `_ACCT_SETUP_SH` for the same shared-`$HOME` problem), and any reinstall
   always wipes the venv first rather than repairing it in place. Both the
   `exec` that opens the lock file and the `flock` call itself are
   error-checked (an unchecked failure would silently skip locking and
   reintroduce the race).
4. The exclusive install lock only covers the reinstall; a long profiling run
   uses the venv for minutes afterward with no protection of its own. Unlike
   fact #3's lock (taken and released within one dispatched command), this is
   a different topology: the script holds a **shared** lock directly in its
   own orchestrating process for the whole `profile`+`analyze` sequence, so a
   concurrent reinstall's exclusive lock (still inside a dispatched fragment)
   blocks until every shared holder releases, instead of deleting a venv a
   sibling run still needs.

   Fully verified on `direct`/`docker` (same host). On `srun` the exclusive
   lock runs on whichever compute node Slurm allocates while the shared lock
   is taken in the orchestrator's own process (typically a login node);
   whether `flock()` contends across two physical hosts sharing `$HOME`
   depends on the network filesystem's advisory-lock support (NFS, NFSv4,
   Lustre, GPFS) and can't be verified from source. In the documented
   workflow, `ckComputeProfile` runs only via `ckRemote`, whose
   `with_server_lock` (`bin/ckRemote:374-384`) already serializes jobs against
   the same `SERVER` from the invoking client — so this is a defense-in-depth
   backstop on `srun`, not the primary guarantee.

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

## MCP server

`lib/ck-profile-mcp/server.py` exposes the CLI modes as agent-callable tools —
registered at user scope (`setup.sh` runs `claude mcp add -s user ck-profile ...`),
so it is available from any CK checkout, not just this repo. It runs locally and
shells out to `ckRemote` exactly as a human would; no remote-side changes.

Tools:

- `run_profile(mode, arch, target, repo, server?)` — starts one of `ckStaticProfile`
  `ckRunProfile`, `ckTraceProfile`, `ckCfgProfile`, `ckComputeProfile` as a background
  job and returns a `job_id`. `repo` must be a CK project root (has both
  `script/cmake-ck-dev.sh` and `CMakeLists.txt`); `server`, if omitted, is
  auto-selected the same way `ckRemote` would. Rejected outright (no queue) if the
  chosen server already has a job in flight.
- `get_job_status(job_id)` — state machine: `running -> pulling -> done | failed |
  pull_failed | timeout`. `failed` means the remote command itself exited non-zero;
  `pull_failed` means it succeeded but `ckRemote pull` failed; `timeout` is
  mode-aware (10 min for static/cfg, 1 hour for run/trace/compute).
- `get_summary(job_id)` — reads `summary.json` for a finished job. Only
  `ckRunProfile` (dynamic mode) currently emits one; other modes raise, pointing at
  the HTML/MD report to read instead.

`compare_runs`/`list_runs` are not implemented yet — read successive `runs/<id>/`
directories directly (see `lib/ck-profile/profile_readme.md`'s "Run history"
section) until those land.

If the MCP server process itself dies while a job's remote command is still
running, the orphaned `ckRemote` process is eventually reconciled to `failed`
on restart even if it actually succeeded remotely, and no pull phase ever
runs. Recover manually: `ckRemote pull ck_profile_out/<mode_output_dir>`.

## Known gotchas

- `--truncate-kernels` (long form) can trip "dangerous command" shell guards
  because it contains the word *truncate*; use `-T`.
- The container login shell does not start in the repo; always set the working
  dir (`docker exec -w $REPO ...`).
- Default program options run CPU verification; pass `-v=0` for profiling and do
  one `-v=1` run separately to confirm correctness.
