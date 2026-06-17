---
name: multi-review
argument-hint: "[PR_NUMBER]"
description: Use when reviewing a diff or pull request before merge and a single review pass is not enough. Triggers include "multi review", "multi-angle review", "review my changes", "review my diff", "review PR <n>", "deep review", or wanting a thorough independent review of local uncommitted/branch changes or a GitHub PR. Reports findings in the conversation; does not post to GitHub.
---

# Multi Review

## Overview

Run a multi-angle code review and emit a consolidated, validated findings report in
the conversation. Four reviewers run in parallel — one broad generalist plus three
specialized lenses — then a spawned consolidator agent merges their findings, a
validation subagent verifies each against the actual source, and (for a PR) anything
existing reviewers already raised is stripped. This skill never posts to GitHub; it
produces a report for the user to act on.

## Modes

Select by argument:

- **PR mode** — first argument is a PR number. Fetches the PR diff, metadata, and
  existing reviews through `gh`.
- **Local mode** — no argument. Diffs uncommitted changes (tracked edits plus new
  untracked files) against `HEAD` when the working tree is dirty; otherwise diffs
  the branch's commits against their merge-base with upstream (or `main`).

## Step 1: Gather context

Run the helper; it detects the mode from its argument:

```bash
REVIEW_DIR=$(skills/multi-review/scripts/gather_context.sh "$ARGS")
```

It writes into `REVIEW_DIR`: `diff.txt`, per-file `chunk-*` files, `chunks.tsv`
(a `file<TAB>chunk` map), and in PR mode `pr.json`, `reviews.json`,
`review_comments.json`.

In local mode the helper picks the diff source automatically: if the working tree
has uncommitted changes (tracked edits or new untracked files), it diffs the working
tree against `HEAD`; otherwise it diffs the branch's commits against the merge-base
with upstream. This means an in-progress change is reviewed even before it is
committed. Note the scope flip: once any file is uncommitted, the review covers only
that uncommitted delta, not the branch's earlier commits. To review committed branch
work while the tree is dirty, stash first or pass the PR number.

If `diff.txt` is empty, stop and tell the user there is nothing to review. If the
argument is a PR number but `gh` is unauthenticated, report it and offer local mode.

## Step 2: Fan out four reviewers (parallel)

Compute SHAs for reviewer context. `BASE_SHA` must match the base the diff was
actually taken against, so it is `HEAD` whenever `diff.txt` is the uncommitted-delta
diff (PR mode, or local mode with a dirty tree) and the merge-base only for the
clean-tree branch diff:

```bash
HEAD_SHA=$(git rev-parse HEAD)
if [ -z "$ARGS" ] && git diff --quiet HEAD 2>/dev/null \
    && [ -z "$(git ls-files --others --exclude-standard)" ]; then
    BASE_SHA=$(git merge-base HEAD "$(git rev-parse --abbrev-ref @{upstream} 2>/dev/null || echo main)")
else
    BASE_SHA=$HEAD_SHA
fi
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

Tell each reviewer to write its full findings to its own file under `REVIEW_DIR`
(`review-broad.md`, `review-correctness.md`, `review-gpu.md`, `review-quality.md`)
and to return only that path plus a one-line summary. The consolidator in Step 3
reads these files, so the four full reviews stay out of this session's context.

If a reviewer returns nothing, note it and continue with the others.

## Step 3: Consolidate

Do not merge the four reviews yourself. Spawn one `reviewer` agent as the
**consolidator**: it forms its own opinion, then synthesizes all four reviews into
one. Give it the four review file paths, `REVIEW_DIR/diff.txt`, and
`rules/code-review.md` as the standard. Instruct it to:

- Read all four review files and the diff, and apply `rules/code-review.md`.
- Merge findings into one list. Collapse duplicates (same `file:line` and same
  underlying issue) into a single entry, keeping the sharpest fix.
- Weight by impact: correctness and security outweigh style nits; performance
  carries high weight when the change has explicit performance targets. Each lens
  finding keeps its own prefix unless this weighting clearly warrants a change; map
  the broad reviewer's scale onto the prefixes (Critical → `blocker:`, Important →
  `suggestion:`, Minor → `nit:`).
- Report dissent: if a reviewer raised a blocker the consolidator discounts, keep
  it with a one-line note on why, rather than silently dropping it.
- Write the consolidated review to `REVIEW_DIR/review-consolidated.md` and return
  that path plus a one-line summary.

If the consolidator finds nothing, report "no findings" and stop.

## Step 4: Validate

Dispatch one `general-purpose` subagent to verify each finding in
`REVIEW_DIR/review-consolidated.md` against the real source. For each finding, read
~50 lines around the cited line plus the matching `chunk-*` (look it up in
`chunks.tsv`); budget at most 15 tool calls. The subagent returns a verdict per
finding:

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
