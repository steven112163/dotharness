# Code Review

## Checklist

### Correctness

- Does the diff match the stated goal in the PR description?
- Does new or changed logic have corresponding tests?
- Are error cases handled? Unchecked return codes, null/dangling pointers, out-of-bounds access.
- Are edge cases covered? Off-by-one, empty input, maximum dimensions, integer overflow.
- Is the code more generic or configurable than the current requirement demands?

### Security

- Is external input validated at the boundary?
- Any hardcoded secrets, API keys, or tokens?
- Are all buffer sizes checked before access?
- Are allocation return values checked (`hipMalloc`, `malloc`, `new`)?
- Is GPU memory freed on all exit paths, including error paths?

### Performance

- Unnecessary copies? Pass large objects by const reference, use move semantics.
- Unbounded loops or hidden quadratic behavior?
- Missing parallelism or excessive synchronization?
- Are allocations avoided in hot loops?

### C++ / HIP

Apply when the diff touches `.cpp`, `.hpp`, `.h`, `.hip`, or `.cu` files.

- Are all functions annotated with `__host__`, `__device__`, or `__host__ __device__`? No implicit annotations.
- Is `__syncthreads()` called only in uniform control flow (never inside divergent branches)?
- Are global memory accesses coalesced? Consecutive threads access consecutive addresses.
- Is shared memory (LDS) padded to avoid bank conflicts?
- Are block sizes multiples of the wavefront size (64 on AMD GPUs)?
- Is `hipGetLastError()` checked after every kernel launch?
- Does the code assume warp size 32? AMD wavefront size is 64.
- Are include groups ordered correctly? Project, then third-party, then standard library.
- Are RAII wrappers used for HIP streams, events, and device memory?
- Is data kept on-device between kernel calls, or are there unnecessary host-device round-trips?
- Does the kernel use `__launch_bounds__` when occupancy matters? Is VGPR usage documented?
- Is divergent branching minimized within wavefronts? Can predication replace branches?
- Are independent kernels launched on separate streams to enable overlap?

### Concurrency

Apply when the diff involves multi-threaded host code, multiple HIP streams, or shared state.

- Is shared mutable state protected? Mutex, atomic, or thread confinement.
- Are check-then-act sequences atomic? No `if (map.count(k)) map[k]` patterns.
- Are critical sections as short as possible? No I/O or kernel launches under locks.
- Are HIP streams that touch the same memory explicitly synchronized?
- Is there a consistent lock ordering to prevent deadlocks?

### Readability

- Is the code readable without comments? Names and structure should be self-documenting.
- Does it follow project conventions? Naming, file layout, include order, error handling.
- Functions under 100 lines, files under 1000 lines, nesting under 3 levels?

### Testing

- Do tests verify real behavior, not just mock interactions?
- Are error paths tested explicitly?
- For performance claims, is profiling evidence included (before/after kernel time, bandwidth)?

## Severity Prefixes

Prefix every review comment with one of:

| Prefix | Meaning | Blocks approval? |
|--------|---------|-----------------|
| `blocker:` | Must fix — bug, security issue, data loss risk, broken functionality | Yes |
| `suggestion:` | Recommended improvement — architecture, missing tests, error handling | No |
| `question:` | Request for clarification — intent, design choice, edge case | No |
| `nit:` | Minor — style, naming, formatting | No |
| `educational:` | Teaches something new — language feature, pattern, design principle | No |

Only `blocker:` prevents approval. Everything else is at the author's discretion.

## When to Approve

- CI must be green before review begins.
- At least one code owner approval for the changed area.
- Two approvals for: build system changes, public API changes, CI/infrastructure changes.
- All blocker comments resolved. Author responds to every comment — resolve or discuss.
- Diffs over 3000 lines should be split into smaller PRs.

## Reviewer

- Read the PR description and linked issue first for context.
- Read the full diff before commenting. Avoid reviewing file-by-file in isolation.
- Scan in priority order: security, correctness, concurrency, performance, readability. Find critical issues before spending attention on style.
- Suggest specific alternatives, not just "this is wrong."
- Weigh findings by impact: correctness and security outweigh style nits. Performance findings carry high weight when the task has explicit performance targets.
- Consolidate repeated findings. If the same issue appears in multiple locations, comment once and note "this pattern repeats in N other places."
- Separate what you would not do from what should not be done. Personal preference is not a blocker.
- Comments are about the code, not the developer. "This function does X" not "you did X."

## Author

- Write a clear description: what changed, why, how to test, known risks.
- Self-review the diff before requesting reviews.
- One concern per PR. Do not mix refactoring with feature work.
- Link the related issue or ticket.
- Respond to all review comments within one business day.

## Anti-patterns

- Do not rubber-stamp. If you did not read the code, do not approve.
- Do not block on style preferences that linters handle. If clang-format or clang-tidy can catch it, it is not a blocker.
- Do not comment on the same issue N times across files. Consolidate into one comment referencing all locations.
- Do not give vague feedback ("improve error handling"). Name the specific function, the failure mode, and a fix.

## Automation

- Format and lint in CI (clang-format, clang-tidy).
- Build with warnings-as-errors enabled.
- Test suite on target hardware (MI-series GPUs) or emulation.