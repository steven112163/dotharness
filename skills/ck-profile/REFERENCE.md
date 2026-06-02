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

```
run_NN/
  t_kernel_trace.csv     raw per-launch: timestamps, VGPR/SGPR, LDS, scratch, grid/block
  t_kernel_stats.csv     per-kernel aggregate (Calls, TotalDurationNs, Percentage, ...)
  t_domain_stats.csv     total KERNEL_DISPATCH time
  pmc_1..8/p_counter_collection.csv   one row per launch per counter (Counter_Name, Counter_Value)
  {t,p}.stdout / .stderr  program output / rocprof logs
```

Aggregated reports (written next to `raw/` by `aggregate.py`): `summary.md`,
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
in a separate build dir under the repo (`ck_profile_out/static/<target>-<arch>/`,
main `build/` untouched, log/reports host-visible), then
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

## Known gotchas

- `--truncate-kernels` (long form) can trip "dangerous command" shell guards
  because it contains the word *truncate*; use `-T`.
- The container login shell does not start in the repo; always set the working
  dir (`docker exec -w $REPO ...`).
- Default program options run CPU verification; pass `-v=0` for profiling and do
  one `-v=1` run separately to confirm correctness.
