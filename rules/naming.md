---
paths:
  - "**/*.cpp"
  - "**/*.hpp"
  - "**/*.h"
  - "**/*.hip"
  - "**/*.py"
  - "**/CMakeLists.txt"
  - "**/*.cmake"
---

# Naming Conventions

## General

- Describe what something is or does, not how it works internally.
- Use the project's established domain vocabulary; match existing names rather than inventing synonyms.
- Universally understood abbreviations are fine: `id`, `idx`, `buf`, `ctx`, `dim`. Avoid `usr`, `mgr`, `proc`.
- Stay consistent. If the codebase says `remove`, do not introduce `delete` for the same action.
- Longer names for larger scopes. Single letters only for loop counters and short lambdas.

## C++

- Variables and functions: `snake_case` (`get_block_size`, `is_valid`, `num_elements`).
- Classes and structs: `PascalCase` (`BlockGemm`, `TensorLayout`, `DeviceConv2d`).
- Template parameters: `PascalCase` (`BlockSize`, `DataType`, `Layout`).
- Constants and `constexpr`: `UPPER_SNAKE_CASE` (`MAX_TILE_SIZE`, `DEFAULT_BLOCK_DIM`).
- Namespaces: short `snake_case` (`ck`, `tensor_operation`, `device`).
- Macros: `UPPER_SNAKE_CASE` with project prefix (`CK_TILE_HOST_DEVICE`).
- Private members: trailing underscore (`buffer_`, `stride_`).
- Use `#pragma once` for all headers (see `cpp-idioms.md`).

## Python

- Variables and functions: `snake_case`.
- Classes: `PascalCase`.
- Constants: `UPPER_SNAKE_CASE`.
- Private members: single underscore prefix `_name`.
- Modules and packages: `snake_case`.

## CMake

- Functions and macros: `snake_case` (`add_kernel_target`, `set_compiler_flags`).
- Variables: `UPPER_SNAKE_CASE` for cache/option variables, `snake_case` for local.
- Options: prefix with project name (`CK_BUILD_TESTS`, `CK_USE_HIPRTC`).
