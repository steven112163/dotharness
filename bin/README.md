# Binaries

Helper scripts in `bin/`, symlinked individually into `~/bin/` (already on `PATH`).

- **dockerRun** — create a named dev container from an image, or print the attach command if it already exists. Used by the `ck-profile` skill to spin up its profiling container.
- **ckBuild** — standard Composable Kernel build command; used by the `builder` agent and the `ck-profile` / `dev-team` skills.
