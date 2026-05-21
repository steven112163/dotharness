# Observability

## Logging

- Use structured logging where possible.
- Log at appropriate levels: ERROR for failures needing action, WARN for degraded state, INFO for key events, DEBUG for development.
- Never log sensitive information (tokens, keys, credentials).
- Include enough context to reproduce the issue: operation name, input parameters, error codes.

## Performance Metrics

- Instrument kernel execution time and memory throughput for performance-critical paths.
- Track build times and test durations in CI to catch regressions.
- Use `rocprof` or `omniperf` output as the source of truth for GPU performance data.

## CI Observability

- Make build and test failures clearly attributable: which commit, which test, which GPU target.
- Retain logs and artifacts from failed CI runs for post-mortem analysis.
- Alert on persistent test failures — do not let broken tests accumulate.
