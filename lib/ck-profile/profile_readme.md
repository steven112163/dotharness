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
(currently `1`) for anything parsing it programmatically.

`ckAggregate` (the tool behind `dynamic/*/summary.*`) is counter-set agnostic but
requires every counter in `counters.txt` to be classified `sum`, `mean`, or `ignore`
in its `COUNTER_CLASS` map — adding a pmc line without a matching classification
makes the next run fail loudly (rather than aggregating it incorrectly) until one is
added.

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
