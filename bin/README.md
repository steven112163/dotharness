# Binaries

Helper scripts in `bin/`, symlinked individually into `~/bin/` (already on `PATH`).

## Composable Kernel build/run

- **ckBuild** — standard Composable Kernel build command. Builds inside the CK docker image (toolchain comes from the image, not the host), so the build needs no GPU — CK cross-compiles. Auto-detects the backend (`direct` inside the dev container, `docker` on a shared host, `srun` on a Slurm login node; override with `MODE`). Used by the `builder` agent and the `ck-profile` / `dev-team` skills.
- **ckRun** — run an arbitrary command (typically a freshly built binary) on a GPU inside the CK image. Companion to `ckBuild`, with the same backend auto-detection. Under `srun`, it overlaps into a running `ckHold` allocation when one exists (instant, no queue wait) and otherwise dispatches a fresh GPU job.
- **ckHold** — hold one persistent GPU allocation on Slurm (a named `sleep infinity` batch job) so repeated `ckRun` calls land instantly via `srun --jobid --overlap` instead of queuing each time. `start` waits for the allocation; `status` and `stop` manage it.
- **ckRemote** — drive a remote CK build/run from a local dev checkout (runs locally; the others run where the build/run happens). Walks a priority-ordered server list and picks the first that is reachable, can execute (`docker` for a `normal` host, `srun` for a `slurm` host), and offers the requested GPU arch (`all` matches any), then rsyncs source (excluding `build/` and `.git`) and runs the `ck*` command over SSH. Config in `~/.config/ckremote`.
- **ckCommon** — shared helper library sourced by `ckBuild`, `ckRun`, `ckHold`, and `dockerRun`; not executed directly. Defines cluster-wide defaults (image, constraint, ccache dir), docker-flag assembly, merged passwd/group account files for LDAP/SSSD users inside the container, the GPU-holder dispatch, and the `srun` dispatch with node-exclude retry.

## Other

- **dockerRun** — create a named dev container from an image, or print the attach command if it already exists. Used by the `ck-profile` skill to spin up its profiling container.
- **llm** — query an external LLM gateway (bash wrapper; invokes `llm.py` via the repo `.venv`). Requires `ANTHROPIC_BASE_URL`, `LLM_GATEWAY_KEY`, and `LLM_GATEWAY_KEY_HEADER`. Default model `gpt-5.5`. Driven by the `llm` skill.
- **llm.py** — Python implementation for `llm`; not invoked directly.
