# Coding Standards

## Code Size Limits

- Functions: 100 lines max (excluding blanks and comments). Split if longer.
- Files: 1000 lines max. Split by responsibility if larger.
- Nesting: 3 levels max (if/for/callback). Use early returns or extract functions.
- Parameters: 6 max per function. Group into an object if more are needed.
- Delete dead code. Never comment it out.
- No magic numbers or strings. Extract into named constants.

## Naming

- Names must be self-explanatory. Purpose should be obvious without reading the implementation.
- Ban meaningless names: `data1`, `temp`, `info`, `obj`, `result`, `item` (loop counters excepted).
- Booleans: prefix with `is`/`has`/`can`/`should` — `isLoading`, `hasPermission`.
- Functions: start with a verb — `fetchUser`, `validateInput`, `calculateTotal`.
- Constants: `ALL_CAPS_SNAKE_CASE` — `MAX_RETRY_COUNT`, `API_BASE_URL`.
- Event handlers: `handle` prefix — `handleClick`, `handleSubmit`.
- Legacy code: follow legacy coding style and check against clang-format and clang-tidy

## Architecture

- **Single Responsibility**: one function does one thing, one file owns one domain.
- **Separation of Concerns**: UI has no business logic, business logic has no UI code, data access is its own layer.
- **Dependency Direction**: upper layers depend on lower layers, never the reverse.
- **Program to Interfaces**: modules talk through interfaces, not concrete implementations.
- **Composition Over Inheritance**: prefer composition unless there is a clear is-a relationship.

## Error Handling

- Validate only at system boundaries (user input, API responses, file I/O).
- Trust internal function contracts. No redundant type checking inside private code.
- Error messages must include context: what operation failed, what values were involved.
- Every async operation needs error handling. No bare promises or unhandled async calls.
- Scope try-catch to the specific operation that can fail, not the entire function body.

## Avoid Over-Engineering

- Solve the current problem. Do not build for hypothetical future requirements.
- Three lines of duplication beats a premature abstraction.
- No utility functions for logic used in one place.
- No unnecessary wrappers, adapters, or intermediate layers.
- Add configuration only when flexibility is genuinely needed today.

## Communication

- Respond in English. Get straight to the point.
- Only output information relevant to the task. Do not echo back what the user said.
