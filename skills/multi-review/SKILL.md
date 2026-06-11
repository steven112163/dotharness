---
name: multi-review
argument-hint: "[PR_NUMBER]"
description: Use when reviewing code changes before merge — runs a four-reviewer multi-angle pass (one broad reviewer plus correctness/numerics, GPU performance, and code-quality lenses), consolidates and validates findings against source, and reports a merged severity-ranked review. Triggers include "multi review", "review my changes", "review PR <n>", "deep review". Does not post to GitHub.
---

# Multi Review

## Overview

Run a multi-angle code review and emit a consolidated, validated findings report in
the conversation. Four reviewers run in parallel — one broad generalist plus three
specialized lenses — then findings are merged, verified against the actual source,
and (for a PR) stripped of anything existing reviewers already raised. This skill
never posts to GitHub; it produces a report for the user to act on.

## Modes

Select by argument:

- **PR mode** — first argument is a PR number. Fetches the PR diff, metadata, and
  existing reviews through `gh`.
- **Local mode** — no argument. Diffs the current branch against its merge-base with
  the upstream branch (or `main`).

## Step 1: Gather context

Run the helper; it detects the mode from its argument:

```bash
REVIEW_DIR=$(skills/multi-review/scripts/gather_context.sh "$ARGS")
```

It writes into `REVIEW_DIR`: `diff.txt`, per-file `chunk-*` files, `chunks.tsv`
(a `file<TAB>chunk` map), and in PR mode `pr.json`, `reviews.json`,
`review_comments.json`.

If `diff.txt` is empty, stop and tell the user there is nothing to review. If the
argument is a PR number but `gh` is unauthenticated, report it and offer local mode.

## Step 2: Fan out four reviewers (parallel)

Compute SHAs for reviewer context:

```bash
HEAD_SHA=$(git rev-parse HEAD)
BASE_SHA=$(git merge-base HEAD "$(git rev-parse --abbrev-ref @{upstream} 2>/dev/null || echo main)")
```

Dispatch all four reviewers in a single message so they run in parallel. Give each
only crafted context — the diff in `REVIEW_DIR/diff.txt`, the SHAs, and the PR
description/requirements — never this session's history.

1. **Broad reviewer** — `general-purpose` agent, filled from the superpowers
   `requesting-code-review` reviewer template. Locate it with:

   ```bash
   ls -d ~/.claude/plugins/cache/claude-plugins-official/superpowers/*/skills/requesting-code-review/code-reviewer.md | sort -V | tail -1
   ```

   Generalist full-pass; returns Critical/Important/Minor.
2. **Correctness & numerics** — `reviewer` agent, focus per `REFERENCE.md` Lens 1.
3. **GPU performance** — `reviewer` agent, focus per `REFERENCE.md` Lens 2.
4. **Code quality** — `reviewer` agent, focus per `REFERENCE.md` Lens 3.

Each lens reviewer reviews only the diff and returns severity-prefixed findings
(`blocker:`/`suggestion:`/`question:`/`nit:`/`educational:`), each tied to
`file:line` with a concrete fix.

If a reviewer returns nothing, note it and continue with the others.

## Step 3: Consolidate

Merge all four reviewers' findings into one list. Collapse duplicates (same
`file:line` and same underlying issue) into a single entry; keep the sharpest fix
and the strongest severity. Normalize the broad reviewer's scale:
Critical → `blocker:`, Important → `suggestion:`, Minor → `nit:`.

## Step 4: Validate

Dispatch one `general-purpose` subagent to verify each consolidated finding against
the real source. For each finding, read ~50 lines around the cited line plus the
matching `chunk-*` (look it up in `chunks.tsv`); budget at most 15 tool calls. The
subagent returns a verdict per finding:

- **Confirmed** — issue is real and correctly described.
- **Wrong** — claim is incorrect; drop it.
- **Overstated** — issue exists but is exaggerated; keep and soften per the note.

Apply verdicts: drop Wrong, adjust Overstated, keep Confirmed. If nothing survives,
report "no confirmed findings" and stop.

## Step 5: Dedup against existing reviews (PR mode only)

Read `reviews.json` and `review_comments.json`. Drop any surviving finding whose
issue was already raised there. Skip this step in local mode.

## Step 6: Final report

Emit two parts and post nothing:

1. Summary table:

   ```
   | # | Severity | File:Line | Issue | Verdict |
   |---|----------|-----------|-------|---------|
   ```

2. Per-finding drafts — the cited code line in a fenced block, then the comment with
   its fix. Use normal fenced code blocks, never GitHub `suggestion` blocks.
