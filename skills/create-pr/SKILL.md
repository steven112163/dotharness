---
name: create-pr
description: Use when creating or opening a pull request, or pushing branch work for review, in any git repository. Triggers include "create PR", "open PR", "submit PR", "make a PR", "raise a PR", or wanting to turn a branch into a reviewable pull request. Applies Composable Kernel (CK) team conventions automatically when the repo is detected as CK.
---

# Create PR

## Workflow

### 1. Gather context

```bash
~/.claude/skills/create-pr/scripts/gather_pr_context.sh [BASE_BRANCH]
```

Prints repo type (CK or generic), current branch, base branch, commits ahead,
diff stat, and a warning with `git status --short` if uncommitted changes
exist. Read the "Repo type" line first — it tells you whether to follow the
CK-specific conventions below.

Base branch defaults to `develop` in a detected CK repo, otherwise the repo's
default branch (`origin/HEAD`, falling back to `main`).

If uncommitted changes exist, warn the user before proceeding.

### 2. Collect PR details

Ask the user (skip fields they've already provided):

- **Title**: suggest one from the commit history. In a CK repo, prefix with `[CK]`.
- **Motivation**: why this change exists, linked PRs/issues.
- **Technical Details**: key implementation choices (draft bullet points from the diff if the user wants help).

In a non-CK repo, also check for a repo PR template
(`.github/PULL_REQUEST_TEMPLATE.md` or `.github/PULL_REQUEST_TEMPLATE/`) and
follow it instead of the generic template in step 4 if one exists.

### 3. Collect test evidence

Ask if the user wants to run tests now or paste existing output.

- **CK repo**: delegate test runs to a sub-agent. Run CK GPU tests with `ckRun`
  (`REPO=$(git rev-parse --show-toplevel) ckRun --arch <gfx> <cmd>`), which
  dispatches to a GPU (srun/docker/direct auto-detected); for many runs start a
  holder once with `ckHold --arch <gfx>` so each `ckRun` overlaps it instantly.
- **Generic repo**: use whatever the repo's own test/build tooling is (check
  `README.md`, `CONTRIBUTING.md`, or `CLAUDE.md` for the command). Delegate
  long-running suites to a sub-agent.

Capture exact stdout for the PR body.

### 4. Format PR body

**CK repo** — use this template (CK team convention, see PR #6378, #7850):

```text
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

**Generic repo** — use the repo's PR template if one was found in step 2;
otherwise use the same template above minus the CK-specific Submission
Checklist section.

### 5. Push and create

- Show the user the draft title and body for approval before submitting.
- `git push -u origin <branch>` if not already pushed.
- `gh pr create --base <base> --title "<title>" --body "<body>"`.
- Report the PR URL.

## Notes

- Confirm with the user before pushing or creating — these are shared/visible actions.
- If the branch needs rebasing onto the base branch, suggest it but do not rebase without consent.
- Use a HEREDOC to pass the body to `gh pr create` to preserve formatting.
