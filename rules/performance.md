# Performance Optimization

## Principles

- Measure before optimizing — profile first, then fix the hotspot
- Optimize the critical path first
- Consider algorithmic complexity
- Balance performance with readability
- Cache expensive operations

## Algorithmic Awareness

- Prefer O(n) or O(n log n) over O(n²) — use sets/maps for lookups instead of nested loops
- Choose appropriate data structures: hash maps for O(1) access, sorted structures for range queries
- Be aware of hidden quadratic behavior in string concatenation, repeated list scans, and nested filters

## Memory Optimization

- Use generators/iterators for large datasets instead of loading everything into memory
- Reuse objects via pooling for high-allocation hot paths
- Process files line-by-line, not by reading the entire file at once

## Async Performance

- Run independent I/O operations in parallel, not sequentially
- Use controlled concurrency (batch size) to avoid overwhelming downstream services
- Avoid blocking the event loop with CPU-heavy synchronous work

## Database Optimization

- Avoid N+1 queries — use JOINs or batch fetching
- Add indexes on columns used in WHERE, JOIN, and ORDER BY clauses
- Use connection pooling to reuse database connections

## Caching

- Cache at the right level: in-memory for hot data, distributed cache for shared state
- Set appropriate TTLs — stale data is a bug
- Implement cache invalidation strategy before adding caching
