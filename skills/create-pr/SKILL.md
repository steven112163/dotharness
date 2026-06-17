---
name: create-pr
description: Use when creating or opening a pull request, or pushing branch work for review, in a Composable Kernel (CK) repository. Triggers include "create PR", "open PR", "submit PR", "make a PR", "raise a PR", or wanting to turn a branch into a reviewable pull request following the CK team's conventions.
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

- Delegate test runs to a sub-agent. Run CK GPU tests with `ckRun`
  (`REPO=$(git rev-parse --show-toplevel) ckRun --arch <gfx> <cmd>`), which
  dispatches to a GPU (srun/docker/direct auto-detected); for many runs start a
  holder once with `ckHold --arch <gfx>` so each `ckRun` overlaps it instantly.
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
