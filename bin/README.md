# Binaries

Helper scripts in `bin/`, symlinked individually into `~/bin/` (already on `PATH`).
Internal Python libs and data files live in `lib/ck-profile/` — see `../lib/ck-profile/README.md`.

## Composable Kernel build/run

- **ckBuild** — build inside the CK docker image; no GPU needed (CK cross-compiles). Auto-detects backend: `direct` (in container), `docker` (shared host), `srun` (Slurm login node). Used by the `builder` agent and the `ck-profile` / `dev-team` skills.
- **ckRun** — run a command on a GPU inside the CK image. Under `srun`, overlaps into a running `ckHold` allocation for instant dispatch; falls back to a fresh GPU job.
- **ckHold** — hold one persistent GPU allocation on Slurm (`sleep infinity` batch job) so `ckRun` calls land instantly. `start` / `status` / `stop`.
- **ckRemote** — drive remote CK work from a local checkout. Rsyncs source, picks the first reachable/capable server from `~/.config/ckremote`, runs the `ck*` command over SSH. `ckRemote pull` rsyncs `ck_profile_out/` back locally after profiling.
- **ckCommon** — sourced by `ckBuild`/`ckRun`/`ckHold`/`dockerRun`; not executed directly. Defines cluster defaults, docker-flag assembly, LDAP/SSSD account files, GPU-holder dispatch, and `srun` node-exclude retry.
- **ckExec** — sourced by all `ck*Profile` scripts; not executed directly. Provides `dx()`/`kill_orphans()`/`dxroot()`/`arch_from_container()` with auto-detected `srun`/`docker` backend, and sets `LIB_DIR` pointing at `lib/ck-profile/`.

## Composable Kernel profiling

All profiling binaries follow the same CLI style as `ckBuild`/`ckRun`: `REPO` auto-detected from git, `--arch gfx942`, positional binary/target. Invoke via `ckRemote --no-sync <cmd> --arch gfx942 <bin>`.

- **ckStaticProfile** — compile-time resource analysis (`-Rpass-analysis=kernel-resource-usage`). Accepts `<target>` (CMake target name). No GPU run; CPU-only srun fallback on Slurm.
- **ckRunProfile** — dynamic profiling with rocprofv3 (kernel trace + PMC multipass). Accepts `<bin>`, `--sweep <flag>=<v1,v2,...>`, `--nruns N`, `--base-args`.
- **ckTraceProfile** — rocprofv3 `--sys-trace` → perfetto `.pftrace` + offline HTML timeline. Same sweep/nruns flags as `ckRunProfile`. `--no-pc-sampling` to skip PC sampling.
- **ckCfgProfile** — ISA CFG as Graphviz DOT via `llvm-objdump`. No GPU run.
- **ckComputeProfile** — deep microarchitecture analysis with rocprof-compute. Accepts `--workload <name>`. On Slurm, `rocprofiler-compute` must be pre-installed in the image.
- **ckAggregate** — aggregate raw rocprofv3 output from `ckRunProfile` into a summary report (markdown + HTML + CSV). Run locally after `ckRemote pull`.
- **ckDepgraph** — emit kernel dependency graphs as Graphviz DOT (logical data-dependency DAG and runtime dispatch graph from a kernel trace CSV).

## Other

- **dockerRun** — create a named dev container from an image, or print the attach command if it already exists.
- **llm** — query an external LLM gateway (bash wrapper over `llm.py`). Requires `ANTHROPIC_BASE_URL`, `LLM_GATEWAY_KEY`, `LLM_GATEWAY_KEY_HEADER`. Default model `gpt-5.5`.
- **llm.py** — Python implementation for `llm`; not invoked directly.
