# Rules

User-level rules loaded automatically by Claude Code. Tailored for C++ / HIP / GPU kernel development. Symlinked to `~/.claude/rules/` by `setup.sh`.

**Always loaded:**

- `writing-style.md` — prose clarity and LLM anti-patterns
- `coding-standards.md` — size limits, naming, architecture, error handling
- `code-review.md` — review checklist, approval criteria, author/reviewer guidelines
- `git.md` — conventional commits format

**Path-scoped** (loaded only when touching matching files):

- `naming.md` — C++, Python, CMake naming conventions
- `cpp-idioms.md` — language standard, type usage, include discipline
- `gpu-kernels.md` — annotation discipline, occupancy, LDS, wavefront rules
- `security.md` — memory safety, input validation, secrets
- `error-handling.md` — fail-fast principles, RAII, HIP error checking
- `performance.md` — algorithmic, memory, GPU/HIP optimization
- `testing.md` — test design, organization, anti-patterns
- `documentation.md` — comment policy, project docs, doc anti-patterns
- `observability.md` — logging, metrics, CI observability
