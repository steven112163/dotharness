---
name: multi-review
argument-hint: "[PR_NUMBER]"
description: Use when reviewing a diff or pull request before merge and a single review pass is not enough. Triggers include "multi review", "multi-angle review", "review my changes", "review my diff", "review PR <n>", "deep review", or wanting a thorough independent review of local uncommitted/branch changes or a GitHub PR. Reports findings in the conversation; does not post to GitHub.
---

# Multi Review

## Overview

Run a multi-angle code review and emit a consolidated, validated findings report in
the conversation. Up to eight reviewers run in parallel — up to four Claude subagents
(broad generalist plus up to three specialized lenses selected from the diff) and a
matching set of external model background Bash calls via `bin/llm` — then a spawned
consolidator agent merges their findings into one file, a validation subagent verifies
each finding against the actual source and writes a final validated report, and (for a
PR) anything existing reviewers already raised is stripped. The orchestrator reads only
the final validated report in normal flow (individual reviewer files are available for
investigation at the Step 6 reporting stage only). This skill never posts to GitHub;
it produces a report for the user to act on.

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

## Step 2: Select lenses and fan out reviewers (parallel)

### 2a: Determine which lenses apply

Read `diff.txt` and decide which of the three specialized lenses are relevant to this
diff. The broad lens always runs. Activate specialized lenses only when warranted:

| Lens | Activate when |
|------|--------------|
| **Broad** (always) | All diffs |
| **Correctness & numerics** | Logic-heavy code, arithmetic, data structures, error handling, API contracts, security boundaries |
| **GPU performance** | Files with `.hip`, `.cu`, `.cpp`/`.hpp` touching GPU kernels, HIP/CUDA calls, memory coalescing, occupancy |
| **Code quality** | Any code change (skip only for trivial doc-only or comment-only diffs) |

Skip a lens entirely if the diff has no content that the lens covers. For example: a
shell script adding a new flag does not need the GPU performance lens. A documentation-
only change needs only the broad lens. Record which lenses are active.

### 2b: Read SHAs

`gather_context.sh` writes `REVIEW_DIR/shas.env` with `HEAD_SHA` and `BASE_SHA`
already computed to match the base the diff was actually taken against. Read it:

```bash
# shellcheck disable=SC1090
source "$REVIEW_DIR/shas.env"
```

### 2c: Dispatch reviewers

**In a single message**, dispatch all active Claude subagents AND all active external
background Bash calls so they run in parallel. Each active lens runs two reviewers
simultaneously: a Claude subagent (deep context, tool access) and an external model
via `bin/llm` (independent perspective, different training). Give each only the diff
and lens-specific instructions — never this session's history.

**Do not dispatch a lens that was marked inactive in 2a.**

#### Claude lens subagents (active lenses only)

1. **Broad** (always) — `general-purpose` agent, filled from the superpowers
   `requesting-code-review` template:

   ```bash
   ls -d ~/.claude/plugins/cache/claude-plugins-official/superpowers/*/skills/requesting-code-review/code-reviewer.md | sort -V | tail -1
   ```

   Returns Critical/Important/Minor. Writes to `review-broad.md`.

2. **Correctness & numerics** (if active) — `reviewer` agent, Lens 1 per `REFERENCE.md`.
   Writes to `review-correctness.md`.

3. **GPU performance** (if active) — `reviewer` agent, Lens 2 per `REFERENCE.md`.
   Writes to `review-gpu.md`.

4. **Code quality** (if active) — `reviewer` agent, Lens 3 per `REFERENCE.md` (includes YAGNI pass).
   Writes to `review-quality.md`.

#### External model reviews (active lenses only, each a separate background Bash call)

```bash
# Broad — GPT-5.5 (always)
bin/llm -m gpt-5.5 --thinking --effort high \
  -s "You are a senior code reviewer. Review this diff for correctness, security, performance, and readability. One finding per line: file:line: <blocker|suggestion|nit>: <issue>. <fix>." \
  < "$REVIEW_DIR/diff.txt" > "$REVIEW_DIR/review-broad-ext.md" 2>&1
```

```bash
# Correctness — DeepSeek (if correctness lens active)
bin/llm -m DeepSeek-V4-Flash --thinking --effort high \
  -s "You are a code correctness reviewer. Focus on: logic errors, unchecked returns, null/dangling pointers, off-by-one, integer overflow, error paths, security at boundaries. One finding per line: file:line: <blocker|suggestion|nit>: <issue>. <fix>." \
  < "$REVIEW_DIR/diff.txt" > "$REVIEW_DIR/review-correctness-ext.md" 2>&1
```

```bash
# GPU performance — Gemini (if GPU lens active)
bin/llm -m gemini-3.5-flash --thinking --effort high \
  -s "You are a GPU performance reviewer. Focus on: memory coalescing, LDS bank conflicts, occupancy, wavefront divergence, kernel launch bounds, unnecessary host-device transfers, missed parallelism. One finding per line: file:line: <blocker|suggestion|nit>: <issue>. <fix>." \
  < "$REVIEW_DIR/diff.txt" > "$REVIEW_DIR/review-gpu-ext.md" 2>&1
```

```bash
# Code quality — GPT-5.5 different lens (if quality lens active)
bin/llm -m gpt-5.5 --thinking --effort high \
  -s "You are a code quality reviewer focused on readability and simplicity. Flag: dead code, magic numbers, premature abstractions, naming issues, functions over 100 lines, nesting over 3 levels, YAGNI violations. One finding per line: file:line: <blocker|suggestion|nit>: <issue>. <fix>." \
  < "$REVIEW_DIR/diff.txt" > "$REVIEW_DIR/review-quality-ext.md" 2>&1
```

### 2d: Wait for all reviewers

**Do not proceed to Step 3 until every dispatched Claude subagent AND every background
Bash call has completed.** Claude subagents complete when their Agent tool call
returns. Background Bash calls complete when you receive a task-notification for each
task ID. Only when all active reviewers have reported — with no outstanding task
notifications — move to Step 3.

If an external call fails (env vars not set, gateway down), note it and continue with
the Claude-only findings.

## Step 3: Consolidate

Do not merge the reviews yourself. Spawn one `reviewer` agent as the
**consolidator**. Pass it: the review file paths for all active lenses (derived from
`REVIEW_DIR` and the lens names recorded in Step 2a — only files that were actually
written; do not include paths for inactive lenses), `REVIEW_DIR/diff.txt`, and
`rules/code-review.md`. Instruct it to:

- Read all active review files and the diff, and apply `rules/code-review.md`.
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
- Write the consolidated review to `REVIEW_DIR/review-consolidated.md`.

The consolidator returns only the file path and a one-line summary. Do not read
`review-consolidated.md` yourself — pass it to the validator in Step 4.

If the consolidator finds nothing, report "no findings" and stop.

## Step 4: Validate

Spawn one `general-purpose` subagent as the **validator**. Pass it
`REVIEW_DIR/review-consolidated.md`, `REVIEW_DIR/diff.txt`, and
`REVIEW_DIR/chunks.tsv`. Instruct it to:

1. Read `review-consolidated.md` first to extract each cited `file:line` reference.
2. For each finding, read ~50 lines around the cited line in the source and the
   matching `chunk-*` file (look up via `chunks.tsv`). The validator may read any
   file in the repository — it should use its own tool access to locate source files
   from the paths cited in the consolidated review.
3. Budget at most 15 tool calls total.
4. Report any finding it cannot verify (file not found, line missing) as unverifiable
   rather than silently skipping it.
5. Write a final validated report to `REVIEW_DIR/review-validated.md` with verdicts
   applied:

- **Confirmed** — issue is real and correctly described. Keep.
- **Wrong** — claim is incorrect. Drop with a note.
- **Overstated** — issue exists but is exaggerated. Keep and soften.

The validator writes `review-validated.md` and returns its path. Do not read any
other review file. Read only `REVIEW_DIR/review-validated.md` to produce the final
report.

If nothing survives validation, report "no confirmed findings" and stop.

## Step 5: Dedup against existing reviews (PR mode only)

Read `reviews.json` and `review_comments.json`. Drop any surviving finding whose
issue was already raised there. Skip this step in local mode.

## Step 6: Final report

Read `REVIEW_DIR/review-validated.md` (written by the validator in Step 4). Emit two
parts and post nothing:

1. Summary table:

   ```text
   | # | Severity | File:Line | Issue | Verdict |
   |---|----------|-----------|-------|---------|
   ```

2. Per-finding drafts — the cited code line in a fenced block, then the comment with
   its fix. Use normal fenced code blocks, never GitHub `suggestion` blocks.

If you need to investigate a specific claim further, you may read individual reviewer
files at this stage. Do not read them as part of the normal flow.

After delivering the report, clean up:

```bash
find "$REVIEW_DIR" -mindepth 1 -delete && rmdir "$REVIEW_DIR"
```
