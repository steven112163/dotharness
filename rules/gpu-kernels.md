---
paths:
  - "**/*.hip"
  - "**/*.hpp"
  - "**/*.cpp"
  - "**/*.h"
  - "**/CMakeLists.txt"
---

# GPU kernel development

## Annotation discipline

- Mark every function with exactly one of `__host__`, `__device__`, or `__host__ __device__`. Never leave it implicit.
- Use a project macro (`CK_TILE_HOST_DEVICE`) for functions that must compile on both sides.
- Keep `__host__ __device__` functions small. Large dual-target functions hide divergent host/device behavior.

## Occupancy and register pressure

- Know the VGPR budget for each target architecture. Check occupancy with `rocprof --stats` or `--hsa-trace`.
- Document the target occupancy for performance-critical kernels near the kernel definition.
- When occupancy is too low, reduce VGPR pressure by narrowing data types, reusing registers, or splitting the kernel.
- Avoid large local arrays in device code. They spill to slow memory and destroy occupancy.

## Shared memory (LDS)

- Declare LDS size as a `constexpr` or template parameter, not a runtime variable.
- Pad shared memory arrays to avoid bank conflicts. When a row stride is a multiple of the bank count, pad by one element so consecutive rows map to different banks (AMD LDS is commonly 32 banks; confirm the count for the target architecture).
- Never access LDS out of bounds. Off-by-one errors in LDS indexing cause silent data corruption.

## Synchronization

- Place `__syncthreads()` only in uniform control flow. Never call it inside a branch where some threads diverge.
- Minimize synchronization points. Restructure algorithms to reduce the number of barriers.
- Use `__threadfence()` or `__threadfence_block()` when publishing data between threads without a full barrier. Document the memory ordering intent.

## Memory access patterns

- Coalesce global memory reads and writes: consecutive threads access consecutive addresses.
- Align base addresses to 128 bytes for vectorized loads (`float4`, `int4`).
- Prefer vectorized loads/stores (2-element or 4-element) when data layout permits.
- Avoid strided or scattered access patterns in global memory. Restructure data layout if necessary.
- Stage global memory through LDS when access patterns cannot be made coalesced directly.

## Kernel launch

- Validate grid and block dimensions before launch. Zero-dimension launches are silent no-ops.
- Check `hipGetLastError()` immediately after every kernel launch to catch async errors.
- Prefer `hipStreamSynchronize` over `hipDeviceSynchronize`. Device-wide sync stalls all streams.
- Set block sizes as multiples of the wavefront size (64 on AMD GPUs).

## HIP portability

- Use HIP API calls, not CUDA equivalents. Do not rely on the HIP-to-CUDA translation layer in production code.
- Use `__shfl_xor`, `__shfl_up`, `__shfl_down` for warp-level communication. Verify the mask covers all participating lanes.
- Wavefront size is 64 on AMD (not 32). Code that assumes warp size 32 will silently produce wrong results.
- Test on all target architectures listed in `GPU_TARGETS`. Behavior can differ across gfx generations.

## Numerical correctness

- Compare floating-point results against an explicit tolerance. Never assert bitwise equality on reduction or accumulation output.
- Accumulate reductions in a wider type than the inputs (a `float` accumulator for `__half` data) to bound rounding error.
- Handle NaN and Inf deliberately: decide whether they are valid inputs, and test the path that produces or consumes them.
- Note when a kernel is non-deterministic. Atomics and multi-pass reductions change accumulation order, so run-to-run results can differ.

## Profiling workflow

- Profile before and after every performance-sensitive change.
- Use `rocprof` for kernel timing, memory bandwidth, and occupancy. Use `omniperf` for deeper microarchitecture analysis.
- Include profiling evidence (before/after kernel time, bandwidth utilization) in PRs that claim performance improvements.
