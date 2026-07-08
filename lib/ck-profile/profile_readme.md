# ck-profile output

Each profiling mode writes its own folder here. Inside every folder, each run
gets its own `runs/<UTC-timestamp>/` (report files + raw data together), and
`latest` is a symlink repointed at the newest run after it finishes. Start at
`latest/index.md` or `latest/*_report.*` — they include a "How to read"
section. `depgraph/` is the one exception: it is not versioned (see its row
below).

| folder | mode | start here | raw/large data |
|--------|------|-----------|----------------|
| `static/` | compile-time resource usage | `latest/build_report.html` / `.md` | `static/build/` (instrumented build tree, reused across runs, not versioned) |
| `dynamic/` | rocprofv3 counters + verdict | `latest/summary.html` / `.md` / `.json` | `latest/raw/` (per-run CSVs) |
| `trace/` | rocprofv3 dispatch timeline | `latest/index.md` | `latest/raw/<variant>/run_NN/*.pftrace`, CSVs |
| `cfg/` | per-kernel ISA control-flow graphs | `latest/*.dot` | (DOT files only; no separate raw subfolder) |
| `depgraph/` | data + runtime dependency graphs | `index.md` | `dot/*.dot` |
| `compute/` | rocprof-compute roofline / SoL | `latest/<target>_report.html` / `.md` | `latest/raw/` (CSV panels, workload, text dump, log) |

## Run history

Every mode above except `depgraph/` never overwrites a previous run: each
invocation writes to its own `<mode>/runs/<UTC-timestamp>/`, and `<mode>/latest`
is a symlink repointed at the newest one after the run finishes. Old runs stay
on disk indefinitely (no pruning yet) — a `ckRemote pull` fetches the whole
`runs/` tree, so any past run's output is available to diff or script against
locally. Two artifacts are intentionally kept outside `runs/`, reused across
invocations rather than versioned, since they are not run history: `static/build/`
(the incremental CMake/Ninja tree) and `.venv-rocprof-compute-py*` at the
`ck_profile_out/` root (the one-time rocprof-compute install).

`dynamic/runs/*/summary.json` additionally carries a `schema_version` field
(currently `2`) for anything parsing it programmatically. `schema_version` `2`
added two things: `lds_bank_conflicts_per_wavefront`/`mfma_busy_cycles_per_wavefront`
per variant — the raw `lds_bank_conflicts`/`mfma_busy_cycles` sums scale with
`--nruns`/`--iters`, so these per-wavefront rates (both counters divided by
the same run's `SQ_WAVES` count) are the ones comparable across differently
configured runs — and the top-level `occ_sample` key (see below). A run with
zero `SQ_WAVES` contributes no sample to either per-wavefront rate, so their
mean/stdev may be computed over fewer runs than the variant's `runs` count.

`ckAggregate` (the tool behind `dynamic/*/summary.*`) is counter-set agnostic but
requires every counter in `counters.txt` to be classified `sum`, `mean`, or `ignore`
in its `COUNTER_CLASS` map — adding a pmc line without a matching classification
makes the next run fail loudly (rather than aggregating it incorrectly) until one is
added.

## Measured occupancy sample (`dynamic/*/summary.json`'s `occ_sample`)

`ckRunProfile` joins its own run with a sibling `compute/latest/` run (if one exists
for the same binary, matched by basename) and adds an `occ_sample` block to
`summary.{json,html,md}`: the *top kernel by time*'s measured VGPR/AGPR/SGPR/LDS/
wavefronts from rocprof-compute's Launch Stats panel, next to the arch's
`max_waves_cu` ceiling. `occ_sample` is `null`/omitted whenever compute mode hasn't
been run yet for this binary, or the panel isn't found.

This is a measured input sample, **not** an automated limiter classification —
nothing in this repo independently derives which single resource (VGPR/AGPR/LDS/
wave-slot) binds occupancy; that would need a per-resource waves-ceiling formula
this codebase doesn't have (see `lib/ck-profile/compute_report.py`'s
`top_launch_stats_row()`). It is also not a full per-kernel join between dynamic
mode's own kernel breakdown and rocprof-compute's — the two tools' kernel-name
strings are not guaranteed to match verbatim, so this always reports compute mode's
own top kernel, which may not be the same kernel dynamic mode's own per-kernel
table highlights.

The exact Launch Stats panel filename/columns (`7.1_Launch_Stats*.csv`) are a
best-effort guess from AMD's published rocprof-compute panel numbering, unconfirmed
against a live run — `top_launch_stats_row()` returns `None` (and `occ_sample`
disappears) if the guess doesn't match what a real `analyze --output-format csv`
run produces, rather than rendering wrong data.

## Quick reading order

1. **static** + **dynamic** together: dynamic's *verdict* says compute- /
   memory- / latency-bound; static's *occupancy ceiling* explains a
   latency/occupancy verdict (register or LDS pressure capping waves).
2. **trace** + **depgraph runtime**: *see* the serialization behind a
   latency-bound verdict — tiny dependent dispatches with gaps.
3. **cfg** + **compute**: per-kernel branch structure and microarchitecture
   (roofline / speed-of-light) attribution for the hottest kernel.

`.html` reports (including the trace `timeline.html`) are self-contained and open
offline in Live Preview; `.dot` files open in VS Code's Graphviz extension; the
`.pftrace` opens at <https://ui.perfetto.dev> for perfetto-only deep dives.

## Agent access via MCP

An agent can start and poll these runs directly through the `ck-profile` MCP
server (`lib/ck-profile-mcp/server.py`, registered by `setup.sh`) instead of a
human running the CLI — see `skills/ck-profile/REFERENCE.md`'s "MCP server"
section for the tool surface.
