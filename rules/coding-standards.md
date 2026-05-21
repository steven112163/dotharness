# Coding Standards

## Code Size Limits

- Functions: 100 lines max (excluding blanks and comments). Split if longer.
- Files: 1000 lines max. Split by responsibility if larger.
- Nesting: 3 levels max. Use early returns or extract functions.
- Parameters: 6 max per function. Group into a struct if more are needed.
- Delete dead code. Never comment it out.
- No magic numbers or strings. Extract into named constants or `constexpr`.

## Architecture

- **Single Responsibility**: one function does one thing, one file owns one domain.
- **Dependency Direction**: upper layers depend on lower layers, never the reverse.
- **Program to Interfaces**: modules communicate through abstract base classes or concepts, not concrete implementations.
- **Composition Over Inheritance**: prefer composition unless there is a clear is-a relationship.
## Avoid Over-Engineering

- Solve the current problem. Do not build for hypothetical future requirements.
- Three lines of duplication beats a premature abstraction.
- No utility functions for logic used in one place.
- No unnecessary wrappers, adapters, or intermediate layers.
- Add configuration only when flexibility is genuinely needed today.

## Code navigation

- One class per header where practical. Combining unrelated classes in one file defeats grep-based navigation.
- Limit namespace nesting to 3 levels. Deep nesting (`a::b::c::d::e`) obscures location.
- No anonymous namespaces in headers. They create silent ODR violations across translation units.
- Avoid `using namespace` in headers. It pollutes every file that includes them.

## Discipline

- No silent assumptions. When requirements are ambiguous, ask before implementing.
- No code hypertrophy. Every line must serve the stated goal. Remove speculative code.
- No collateral changes. If a function works and is not part of the task, do not touch it. Unrelated refactors go in separate commits.
- Verifiable success criteria. Define what "done" looks like before writing code: which tests pass, which benchmarks hold, which behavior changes.

## Communication

- Respond in English. Get straight to the point.
- Only output information relevant to the task. Do not echo back what the user said.
