# Coding Standards

## Code Size Limits

- Functions: 100 lines max (excluding blanks and comments). Split if longer.
- Files: 1000 lines max. Split by responsibility if larger.
- Nesting: 3 levels max. Use early returns or extract functions.
- Parameters: 6 max per function. Group into a struct if more are needed.
- Delete dead code. Never comment it out.
- No magic numbers or strings. Extract into named constants or `constexpr`.

## Naming

- Names must be self-explanatory. Purpose should be obvious without reading the implementation.
- Ban meaningless names: `data1`, `temp`, `info`, `obj`, `result`, `item` (loop counters excepted).
- Booleans: prefix with `is`/`has`/`can`/`should` — `is_valid`, `has_workspace`.
- Functions: start with a verb — `compute_gemm`, `validate_layout`, `get_block_size`.
- Constants: `ALL_CAPS_SNAKE_CASE` — `MAX_TILE_SIZE`, `DEFAULT_BLOCK_DIM`.
- Legacy code: follow legacy coding style and check against clang-format and clang-tidy.

## Architecture

- **Single Responsibility**: one function does one thing, one file owns one domain.
- **Dependency Direction**: upper layers depend on lower layers, never the reverse.
- **Program to Interfaces**: modules communicate through abstract base classes or concepts, not concrete implementations.
- **Composition Over Inheritance**: prefer composition unless there is a clear is-a relationship.
- **Templates with Constraints**: use `requires` clauses or `static_assert` to make template errors readable.

## Error Handling

- Validate at system boundaries (user-facing API, file I/O, runtime parameters).
- Trust internal function contracts. No redundant checks inside private code.
- Error messages must include context: what operation failed, what values were involved.
- Check HIP API return codes. Never ignore `hipError_t`.

## Avoid Over-Engineering

- Solve the current problem. Do not build for hypothetical future requirements.
- Three lines of duplication beats a premature abstraction.
- No utility functions for logic used in one place.
- No unnecessary wrappers, adapters, or intermediate layers.
- Add configuration only when flexibility is genuinely needed today.

## Communication

- Respond in English. Get straight to the point.
- Only output information relevant to the task. Do not echo back what the user said.
