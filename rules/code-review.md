# Code Review

## Checklist

- Does the diff match the stated goal in the PR description?
- Does new or changed logic have corresponding tests?
- Are error cases handled? Look for missing try/catch, unhandled rejections, unchecked nulls.
- Is external input validated at the boundary?
- Any security red flags? SQL injection, XSS, hardcoded secrets, excessive permissions.
- Is the code readable without comments? Names and structure should be self-documenting.
- Any performance concerns? N+1 queries, unbounded loops, missing pagination, oversized payloads.
- Does it follow project conventions? Naming, file layout, import order, error handling.

## When to Approve

- CI must be green before review begins.
- At least one code owner approval for the changed area.
- Two approvals for: database migrations, auth changes, payment logic, infra changes.
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
- Include screenshots or recordings for UI changes.
- Link the related issue or ticket.
- Respond to all review comments within one business day.

## Automation

- Lint and format in CI (ESLint, Prettier, Ruff, Clippy).
- Type checking in CI (TypeScript, mypy, pyright).
- Test suite with coverage thresholds.
- Bundle size check for frontend changes.
- Migration safety check for schema changes on large tables.