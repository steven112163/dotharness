---
paths:
  - "**/*.cpp"
  - "**/*.hpp"
  - "**/*.h"
  - "**/*.hip"
  - "**/*.py"
---

# Error Handling

## Principles

- Fail fast and fail clearly.
- Provide actionable error messages with context (operation, values, upstream cause).
- Never swallow errors silently.
- Handle errors at the right level — do not catch everything at the top.

## C++ Specifics

- Prefer exceptions or error codes consistently within a project — do not mix both.
- Use `static_assert` for compile-time invariants. Use `assert` for debug-only runtime checks.
- Return `std::optional` or `std::expected` for operations that can legitimately fail.

## Recovery

- Retry with exponential backoff only for transient failures (network, file locks). Max 3 retries.
- Do not retry on logic or validation errors.
- When falling back to a default or cached value, log the fallback so it is observable.

## Best Practices

- Validate early at system boundaries. Trust internal contracts.
- Log errors with sufficient context: correlation ID, operation name, input values.
- Test error paths explicitly — happy-path tests alone are insufficient.
