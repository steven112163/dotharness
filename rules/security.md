---
paths:
  - "**/*.cpp"
  - "**/*.hpp"
  - "**/*.h"
  - "**/*.hip"
  - "**/CMakeLists.txt"
---

# Security

## Secrets

- Never hardcode secrets, API keys, or tokens in source code.
- Use environment variables or CI secret storage for credentials.
- Add credential files and `.env` to `.gitignore`.
- If a secret is accidentally committed, rotate it immediately.

## Memory Safety

- Check all buffer sizes before access. No out-of-bounds reads or writes.
- Initialize all variables. Undefined behavior from uninitialized memory is a security risk.
- Check return values of all allocation calls (`hipMalloc`, `malloc`).
- Free GPU memory on all exit paths, including error paths.

## Input Validation

- Validate all user-facing inputs: CLI args, config file values, tensor dimensions.
- Reject invalid input early. Do not attempt to sanitize and continue.
- Enforce bounds on dimensions, sizes, and counts to prevent integer overflow.

## Dependencies

- Pin exact versions of third-party dependencies in build scripts.
- Review new dependencies before adding: check maintenance status and known issues.
- Keep compilers and toolchains updated for security patches.
