# Git Conventions

## Commit Discipline

- Do not commit unless explicitly asked.
- Verify the code works before committing.
- Do not add a `Co-Authored-By` trailer or any other tool attribution to commit messages.

## Commit Message Format

Subject line format (enforced by `commit-lint` hook):

```
<type>(<scope>): <subject>
```

Scope is optional. Subject uses imperative mood ("add", not "adds" or "added"), starts lowercase, and has no trailing period.

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

Subject line limits:
- Maximum 72 characters (type + scope + separator + subject combined).
- Separate subject from body with a blank line.

When a commit covers multiple points, use a body list:

```
feat(web): implement email verification workflow

- Add token generation service
- Create verification email template
- Add API endpoint for token validation
```

Bad examples (rejected by hook):

```
Update files                          # missing type
feat - add login                      # wrong separator
Feat(web): Add login                  # type must be lowercase
feat(web): Add login.                 # no trailing period
feat(web):add login                   # missing space after colon
```

## Branch conventions

- Name branches `<type>/<short-description>`: `feat/fmha-backward-kernel`, `fix/occupancy-regression`, `refactor/tile-layout`.
- One concern per branch, matching one concern per PR.
- Rebase onto the target branch before requesting review. No merge commits from the target branch.
- Delete branches after merge. Stale branches obscure active work.
