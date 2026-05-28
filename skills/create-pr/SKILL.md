---
name: create-pr
description: Create a pull request following the CK team's PR template (Motivation, Technical Details, Test Plan, Test Result, Submission Checklist). Use when user says "create PR", "open PR", "submit PR", or wants to push changes for review.
---

# Create PR

## Workflow

### 1. Gather context

- Run `git status`, `git log <base>..HEAD --oneline`, and `git diff --stat <base>..HEAD` to understand what changed.
- Identify the base branch (usually `develop`).
- If uncommitted changes exist, warn the user before proceeding.

### 2. Collect PR details

Ask the user (skip fields they've already provided):

- **Title**: suggest one from the commit history. Prefix with `[CK]` for composablekernel changes.
- **Motivation**: why this change exists, linked PRs/issues.
- **Technical Details**: key implementation choices (draft bullet points from the diff if the user wants help).

### 3. Collect test evidence

Ask if the user wants to run tests now or paste existing output. If running:

- Delegate test runs to a sub-agent inside the container (`docker exec styuan_dev ...`).
- Capture exact stdout for the PR body.

### 4. Format PR body

Use this template (CK team convention, see PR #6378, #7850):

```
## Motivation

[Why this change exists, link related PRs/issues]

## Technical Details

[Bullet points describing what changed and how]

## Test Plan

[How it was tested]

## Test Result

[Exact test output in a code block]

## Submission Checklist

- [x] Look over the contributing guidelines at https://github.com/ROCm/ROCm/blob/develop/CONTRIBUTING.md#pull-requests.
```

### 5. Push and create

- Show the user the draft title and body for approval before submitting.
- `git push -u origin <branch>` if not already pushed.
- `gh pr create --base <base> --title "<title>" --body "<body>"`.
- Report the PR URL.

## Notes

- Confirm with the user before pushing or creating — these are shared/visible actions.
- If the branch needs rebasing onto the base branch, suggest it but do not rebase without consent.
- Use a HEREDOC to pass the body to `gh pr create` to preserve formatting.
