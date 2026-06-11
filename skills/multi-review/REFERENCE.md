# Multi Review — lens checklists

Each lens reviewer applies one checklist below, drawing on the project's full
`rules/code-review.md`. These are the focused subsets per angle.

## Lens 1 — Correctness & numerics

- Logic matches the stated goal; new or changed paths have tests.
- Error cases handled: unchecked returns, null/dangling pointers, out-of-bounds.
- Edge cases: off-by-one, empty input, maximum dimensions, integer overflow.
- Numerics: accumulation precision, tolerance choices, loss of significance in
  reduced precision (fp16/bf16), NaN/Inf handling.
- Sync correctness: `__syncthreads()` only in uniform control flow.
- Security at boundaries: external input validated; buffer sizes checked;
  allocation returns (`hipMalloc`, `malloc`, `new`) checked; GPU memory freed on
  all paths including errors. No hardcoded secrets.

## Lens 2 — GPU performance

- Global memory coalesced: consecutive threads touch consecutive addresses.
- LDS padded to avoid bank conflicts.
- Block sizes multiples of wavefront 64; no warp-size-32 assumptions.
- Occupancy: `__launch_bounds__` where it matters; VGPR pressure noted.
- MFMA instruction/tile selection matched to dtype (e.g. K=16 for fp16/bf16).
- No allocations in hot loops; no avoidable host-device round-trips.
- Divergence minimized; predication over branching where possible.
- Independent kernels on separate streams to enable overlap; sync only as needed.

## Lens 3 — Code quality

- Readable without comments; names and structure self-documenting.
- Follows project conventions: naming, file layout, include order (project,
  third-party, standard library), error handling.
- Functions under 100 lines, files under 1000 lines, nesting under 3 levels,
  6 parameters max.
- No dead code, no commented-out code, no magic numbers or strings.
- All device functions annotated `__host__`/`__device__`/`__host__ __device__`.
- RAII for HIP streams, events, device memory.
- No `using namespace` in headers; namespace nesting at most 3 levels.
