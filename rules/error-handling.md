# Robust Error Handling

## Principles

- Fail fast and fail clearly
- Provide actionable error messages
- Log errors with appropriate context
- Handle errors at the right level
- Never swallow errors silently

## Error Types

- Define custom error types for distinct failure categories (validation, network, business logic, data integrity)
- Include relevant context in error objects (operation name, input values, upstream cause)
- Re-throw or transform errors based on type — do not catch-all and discard

## Recovery Strategies

### Retry with Backoff
- Use exponential backoff for transient failures (network, rate limits)
- Set a max retry count (typically 3)
- Only retry on errors known to be transient — do not retry validation errors

### Circuit Breaker
- Track consecutive failures to an external dependency
- Open the circuit (stop calling) after a threshold (e.g., 5 failures)
- Attempt reset after a timeout period
- Fail fast with a clear message while the circuit is open

### Graceful Degradation
- Fall back to cached data or defaults when a dependency is unavailable
- Log the fallback so it is visible in monitoring
- Do not silently degrade — make it observable

## Best Practices

- Use try-catch-finally blocks appropriately; finally for cleanup
- Create error boundaries in UI components
- Implement global error handlers for uncaught exceptions
- Validate early and fail fast at system boundaries
- Provide user-friendly error messages separate from technical logs
- Log errors with sufficient context (correlation ID, operation, input)
- Test error scenarios explicitly — happy path tests alone are insufficient
