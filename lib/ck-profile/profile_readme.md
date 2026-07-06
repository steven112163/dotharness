# ck-profile output

Each profiling mode writes its own folder here. Inside every folder: the
**report files** at the top, and a **subfolder** (`raw/`, `build/`, or `dot/`)
holding everything else (raw data / large artifacts). Start at each folder's
`index.md` or `*_summary.md` — they include a "How to read" section.

| folder | mode | start here | raw/large data |
|--------|------|-----------|----------------|
| `static/` | compile-time resource usage | `build_report.html` / `.md` | `build/` (instrumented build tree) |
| `dynamic/` | rocprofv3 counters + verdict | `latest/summary.html` / `.md` / `.json` | `latest/raw/` (per-run CSVs); prior runs under `runs/<timestamp>/` |
| `trace/` | rocprofv3 dispatch timeline | `raw/<variant>/run_NN/timeline.html` (+ `index.md`) | `raw/.../*.pftrace`, CSVs |
| `cfg/` | per-kernel ISA control-flow graphs | `index.md` | `dot/*.dot` |
| `depgraph/` | data + runtime dependency graphs | `index.md` | `dot/*.dot` |
| `compute/` | rocprof-compute roofline / SoL | `<target>_report.html` / `.md` | `raw/` (CSV panels, workload, text dump, log) |

## `dynamic/` run history

`ckRunProfile` never overwrites a previous run: each invocation writes to its own
`dynamic/runs/<UTC-timestamp>/` (report files + `raw/` together), and `dynamic/latest`
is a symlink repointed at the newest one after the run finishes. Old runs stay on
disk indefinitely (no pruning yet) — a `ckRemote pull` fetches the whole `runs/`
tree, so `dynamic/runs/*/summary.json` from any past run is available to diff or
script against locally. `summary.json` carries a `schema_version` field (currently
`1`) for anything parsing it programmatically.

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
