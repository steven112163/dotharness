---
paths:
  - "**/*.cpp"
  - "**/*.hpp"
  - "**/*.h"
  - "**/*.hip"
  - "**/*.md"
  - "**/CMakeLists.txt"
---

# Documentation

## Code comments

- Default to no comments. Well-named functions and variables replace most comments.
- Comment the why, never the what. If the code needs a "what" comment, rename instead.
- Use `///` (doxygen-style) for public API functions: one line describing what the function does and any non-obvious preconditions.
- Document non-obvious template parameter constraints when concepts or `static_assert` messages are insufficient.

## Project documentation

- Each major subsystem or example directory gets a README with: purpose, build instructions, and a minimal usage example.
- Keep docs next to the code they describe. A `docs/` tree that mirrors `src/` drifts out of sync.
- Update documentation in the same PR that changes the behavior it describes.

## Anti-patterns

- Do not write comments that restate the function signature in prose.
- Do not maintain changelogs in source files. Git history is the changelog.
- Do not write `// TODO` without a linked issue. Untracked TODOs rot.
