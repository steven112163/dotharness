---
paths:
  - "**/*.cpp"
  - "**/*.hpp"
  - "**/*.h"
  - "**/*.hip"
---

# C++ idioms

## Language standard

- Target C++17. Use C++20 features only where hipcc and all CI toolchains support them.
- Prefer `constexpr` functions over macros for compile-time computation.
- Use `if constexpr` to eliminate dead branches in template code. Prefer it over SFINAE and tag dispatch.
- Use `[[nodiscard]]` on functions where ignoring the return value is always a bug.
- Use `[[maybe_unused]]` on parameters required by an interface but unused in a specific overload.
- Avoid `std::endl`. Use `'\n'` to avoid unnecessary flushes.

## Type usage

- Prefer `std::array` over C-style arrays.
- Prefer `std::span` (C++20) or explicit pointer+size pairs with clear naming over raw pointer arithmetic.
- Use `using` aliases, not `typedef`.
- Use scoped enums (`enum class`) over unscoped enums.
- Prefer `std::optional` for values that may be absent and `std::variant` for closed type sets.

## Include discipline

- Order includes: project headers, then third-party headers, then standard library headers. Separate each group with a blank line.
- Every header must be self-contained: it compiles on its own without relying on a prior include.
- Use forward declarations to break compile-time dependencies when the full definition is not needed.
- Use `#pragma once` over include guards.
- No circular includes. If A.hpp and B.hpp need each other, extract the shared type into a third header.

## Template metaprogramming

- Name template parameters descriptively: `BlockSize` not `N`, `DataType` not `T`, `Layout` not `L`.
- Limit template nesting to 3 levels. Use type aliases to flatten deeper hierarchies.
- Place `static_assert` at the top of templated functions and classes with messages that name the violated constraint.
- Constrain templates with `requires` clauses (C++20) or `std::enable_if` (C++17). Unconstrained templates produce unreadable errors.
- Keep template definitions in headers. Do not split declaration and definition across `.hpp` and `.cpp` unless using explicit instantiation.
- When a template parameter list exceeds 6 parameters, group related parameters into a policy or trait struct.

## Resource management

- Use RAII for all resources: memory, file handles, HIP streams, HIP events.
- Prefer `std::unique_ptr` for exclusive ownership and `std::shared_ptr` only when shared ownership is genuinely required.
- Mark move-only types as such: delete copy constructor and copy assignment.
- Avoid raw `new`/`delete`. Use `std::make_unique` or `std::make_shared`.
