# Git Conventions

## Commit Discipline

- Do not commit unless explicitly asked.
- Verify the code works before committing.

## Commit Message Format

```
<type>(<scope>): <subject>
```

| type | Purpose |
|------|---------|
| feat | New feature |
| fix | Bug fix |
| docs | Documentation |
| style | Formatting, no runtime impact |
| refactor | Restructuring, no behavior change |
| perf | Performance improvement |
| test | Adding or updating tests |
| example | Adding or updating examples |
| chore | Build, tooling, or dependency changes |

When a commit covers multiple points, use a body list:

```
feat(web): implement email verification workflow

- Add token generation service
- Create verification email template
- Add API endpoint for token validation
```

## Branch conventions

- Name branches `<type>/<short-description>`: `feat/fmha-backward-kernel`, `fix/occupancy-regression`, `refactor/tile-layout`.
- One concern per branch, matching one concern per PR.
- Rebase onto the target branch before requesting review. No merge commits from the target branch.
- Delete branches after merge. Stale branches obscure active work.

