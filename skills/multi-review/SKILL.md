---
name: multi-review
argument-hint: "[PR_NUMBER]"
description: Use when reviewing a diff or pull request before merge and a single review pass is not enough. Triggers include "multi review", "multi-angle review", "review my changes", "review my diff", "review PR <n>", "deep review", or wanting a thorough independent review of local uncommitted/branch changes or a GitHub PR. Reports findings in the conversation; does not post to GitHub.
---

# Multi Review

## Overview

Run a multi-angle code review and emit a consolidated, validated findings report in
the conversation. Eight reviewers run in parallel — four Claude subagents (one broad
generalist plus three specialized lenses) and four external model reviews via
`bin/llm` — then a spawned consolidator agent merges their findings, a validation
subagent verifies each against the actual source, and (for a PR) anything existing
reviewers already raised is stripped. This skill never posts to GitHub; it produces
a report for the user to act on.

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

## Step 2: Fan out reviewers (parallel — Claude lenses + external models)

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

Dispatch all reviewers in a single message so they run in parallel. Each lens runs
two reviewers simultaneously: a Claude subagent (deep context, tool access) and an
external model via `bin/llm` (independent perspective, different training). Give
each only the diff and lens-specific instructions — never this session's history.

### Claude lens subagents (4 agents)

1. **Broad** — `general-purpose` agent, filled from the superpowers
   `requesting-code-review` template:

   ```bash
   ls -d ~/.claude/plugins/cache/claude-plugins-official/superpowers/*/skills/requesting-code-review/code-reviewer.md | sort -V | tail -1
   ```

   Returns Critical/Important/Minor. Writes to `review-broad.md`.

2. **Correctness & numerics** — `reviewer` agent, Lens 1 per `REFERENCE.md`.
   Writes to `review-correctness.md`.

3. **GPU performance** — `reviewer` agent, Lens 2 per `REFERENCE.md`.
   Writes to `review-gpu.md`.

4. **Code quality** — `reviewer` agent, Lens 3 per `REFERENCE.md` (includes YAGNI pass).
   Writes to `review-quality.md`.

### External model reviews (4 parallel Bash calls)

Run simultaneously with the Claude agents. Dispatch each as its own **background
Bash tool call** (`run_in_background: true`) in the same message as the Claude
subagents. Four separate Bash calls, one per reviewer:

```bash
# Bash call 1 — broad generalist (GPT-5.5)
bin/llm -m gpt-5.5 --thinking --effort high \
  -s "You are a senior code reviewer. Review this diff for correctness, security, performance, and readability. One finding per line: file:line: <blocker|suggestion|nit>: <issue>. <fix>." \
  < "$REVIEW_DIR/diff.txt" > "$REVIEW_DIR/review-broad-ext.md" 2>&1
```

```bash
# Bash call 2 — correctness (DeepSeek)
bin/llm -m DeepSeek-V4-Flash --thinking --effort high \
  -s "You are a code correctness reviewer. Focus on: logic errors, unchecked returns, null/dangling pointers, off-by-one, integer overflow, error paths, security at boundaries. One finding per line: file:line: <blocker|suggestion|nit>: <issue>. <fix>." \
  < "$REVIEW_DIR/diff.txt" > "$REVIEW_DIR/review-correctness-ext.md" 2>&1
```

```bash
# Bash call 3 — GPU performance (Gemini)
bin/llm -m gemini-3.5-flash --thinking --effort high \
  -s "You are a GPU performance reviewer. Focus on: memory coalescing, LDS bank conflicts, occupancy, wavefront divergence, kernel launch bounds, unnecessary host-device transfers, missed parallelism. One finding per line: file:line: <blocker|suggestion|nit>: <issue>. <fix>." \
  < "$REVIEW_DIR/diff.txt" > "$REVIEW_DIR/review-gpu-ext.md" 2>&1
```

```bash
# Bash call 4 — readability/simplicity (GPT-5.5, different lens from call 1)
# Same model as call 1 but focused on code quality rather than correctness/security.
bin/llm -m gpt-5.5 --thinking --effort high \
  -s "You are a code quality reviewer focused on readability and simplicity. Flag: dead code, magic numbers, premature abstractions, naming issues, functions over 100 lines, nesting over 3 levels, YAGNI violations. One finding per line: file:line: <blocker|suggestion|nit>: <issue>. <fix>." \
  < "$REVIEW_DIR/diff.txt" > "$REVIEW_DIR/review-quality-ext.md" 2>&1
```

Wait for all background Bash calls to complete before proceeding to Step 3.

All eight outputs feed the consolidator. If an external call fails (env vars not
set, gateway down), note it and continue with the Claude-only findings.

## Step 3: Consolidate

Do not merge the reviews yourself. Spawn one `reviewer` agent as the
**consolidator**: it forms its own opinion, then synthesizes all eight reviews
(four Claude lenses + four external model reviews) into one. Give it all eight
review file paths, `REVIEW_DIR/diff.txt`, and `rules/code-review.md` as the
standard. Instruct it to:

- Read all eight review files and the diff, and apply `rules/code-review.md`.
- Merge findings into one list. Collapse duplicates (same `file:line` and same
  underlying issue) into a single entry, keeping the sharpest fix. When a Claude
  subagent and an external model flag the same issue, merge into one entry and note
  both sources. When only an external model flags something, verify it is real before
  keeping it — external models lack tool access and may misread context.
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

   ```text
   | # | Severity | File:Line | Issue | Verdict |
   |---|----------|-----------|-------|---------|
   ```

2. Per-finding drafts — the cited code line in a fenced block, then the comment with
   its fix. Use normal fenced code blocks, never GitHub `suggestion` blocks.

After delivering the report, clean up: `rm -rf "$REVIEW_DIR"`.
