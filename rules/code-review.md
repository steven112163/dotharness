# Code Review

## Checklist

- Does the diff match the stated goal in the PR description?
- Does new or changed logic have corresponding tests?
- Are error cases handled? Unchecked return codes, null/dangling pointers, out-of-bounds access.
- Is external input validated at the boundary?
- Any security red flags? Hardcoded secrets, buffer overflows, unchecked allocations.
- Is the code readable without comments? Names and structure should be self-documenting.
- Any performance concerns? Unnecessary copies, unbounded loops, missing parallelism, excessive synchronization.
- Does it follow project conventions? Naming, file layout, include order, error handling.

## When to Approve

- CI must be green before review begins.
- At least one code owner approval for the changed area.
- Two approvals for: build system changes, public API changes, CI/infrastructure changes.
- All comments resolved. Author responds to every comment — resolve or discuss.
- Diffs over 3000 lines should be split into smaller PRs.

## Reviewer

- Review within 4 business hours of being tagged.
- Read the PR description and linked issue first for context.
- Read the full diff before commenting. Avoid reviewing file-by-file in isolation.
- Prefix comments: `nit:`, `question:`, `suggestion:`, `blocker:`.
- Only `blocker:` prevents approval. Everything else is at the author's discretion.
- Suggest specific alternatives, not just "this is wrong."

## Author

- Write a clear description: what changed, why, how to test, known risks.
- Self-review the diff before requesting reviews.
- One concern per PR. Do not mix refactoring with feature work.
- Link the related issue or ticket.
- Respond to all review comments within one business day.

## Automation

- Format and lint in CI (clang-format, clang-tidy).
- Build with warnings-as-errors enabled.
- Test suite on target hardware (MI-series GPUs) or emulation.