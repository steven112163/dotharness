# Performance

## Principles

- Measure before optimizing — profile first, then fix the hotspot.
- Optimize the critical path first.
- Balance performance with readability.

## Algorithmic Awareness

- Prefer O(n) or O(n log n) over O(n²). Use hash maps or sets for lookups instead of nested loops.
- Choose data structures that match access patterns: contiguous memory for sequential access, maps for sparse lookups.
- Watch for hidden quadratic behavior in repeated container scans and string concatenation.

## Memory

- Minimize allocations in hot loops. Pre-allocate buffers and reuse them.
- Prefer stack allocation and `constexpr` computation over heap allocation.
- Use move semantics to avoid unnecessary copies. Pass large objects by const reference.
- Process large data in streaming fashion rather than loading everything into memory.

## GPU / HIP

- Maximize occupancy: balance VGPR usage, LDS allocation, and wavefront count.
- Minimize host-device transfers. Batch work on the GPU.
- Use async memory copies and overlap computation with data movement.
- Coalesce global memory accesses. Avoid strided or scattered reads.
- Profile with `rocprof` before tuning. Do not guess at bottlenecks.

## Concurrency

- Run independent operations in parallel.
- Use controlled concurrency to avoid overwhelming downstream resources.
- Minimize synchronization points and lock contention.
