# lib/ck-profile

Internal Python libraries and data files for the CK profiling binaries (`bin/ck*Profile`).
Symlinked to `~/lib/ck-profile/` by `setup.sh`. Not on `PATH` — imported programmatically.

`ckExec` sets `LIB_DIR` at source time by resolving its own real path via `readlink -f` and
navigating `../lib/ck-profile/`, so all sourcing scripts find this directory correctly from
any repo on the host.

## Python libraries

- **ck_profile_utils.py** — shared pure helpers: `classify(compute_pct, bw_util_pct)` (roofline verdict), `msd(xs)` (mean + stdev over NaN-filtered list), `short(name)` (kernel name shortener). Imported by `ckAggregate` and `ckDepgraph`.
- **gpu_specs.py** — per-arch hardware specs (CUs, wave size, peak bandwidth, VGPR file size). Imported by `ckAggregate` and `parse_resource_usage.py`.
- **html_report.py** — zero-dependency self-contained HTML report renderer (dark "telemetry" theme). Imported by `ckAggregate`, `parse_resource_usage.py`, and `compute_report.py`.
- **parse_resource_usage.py** — parses `-Rpass-analysis=kernel-resource-usage` build log remarks into VGPR/AGPR/SGPR/occupancy/spill/LDS tables. Invoked by `ckStaticProfile` inside the container (needs `c++filt` for demangling).
- **compute_report.py** — renders rocprof-compute CSV panels into styled HTML + Markdown. Invoked by `ckComputeProfile`.
- **trace_timeline.py** — renders rocprofv3 sys-trace CSVs into a self-contained offline HTML timeline. Invoked by `ckTraceProfile` on the host (pure stdlib Python).
- **cfg_to_dot.py** — converts `llvm-objdump -d` output into per-kernel Graphviz DOT files. Invoked by `ckCfgProfile` inside the container.

## Data files

- **counters.txt** — rocprofv3 PMC counter list for `ckRunProfile`.
- **git_exclude_outdir.sh** — adds `ck_profile_out/` to `.git/info/exclude` (idempotent, worktree-correct). Called by all `ck*Profile` scripts.
- **profile_readme.md** — README written to `ck_profile_out/README.md` when any profile run starts.
