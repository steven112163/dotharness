---
name: multi-review
argument-hint: "[PR_NUMBER | PR_URL | repo]"
description: Use when reviewing a diff, pull request, or whole repository and a single review pass is not enough. Triggers include "multi review", "multi-angle review", "review my changes", "review my diff", "review PR <n>", "review this PR link", "review the whole repo", "deep review", or wanting a thorough independent review of a branch, a GitHub PR, or an entire codebase. Reports findings in the conversation; does not post to GitHub.
---

# Multi Review

## Overview

Run a multi-angle code review and emit a consolidated, validated findings report in
the conversation. Up to eight reviewers run in parallel — up to four Claude `reviewer`
subagents (broad generalist plus up to three specialized lenses selected from the diff)
and a matching set of external GPT-6-astra reviews (one per active lens). One spawned
`reviewer` agent then merges and validates in a single pass, and (for a PR) anything
existing reviewers already raised is stripped. The orchestrator reads only the final
validated report in normal flow (individual reviewer files are available for
investigation at the Step 5 reporting stage only). This skill never posts to GitHub;
it produces a report for the user to act on.

## Modes

Select by argument:

- **PR mode** — first argument is a PR number (`412`) or a PR URL
  (`https://github.com/owner/repo/pull/412`). Fetches the PR diff, metadata, and
  existing reviews through `gh`.
- **Repo mode** — first argument is `repo` (or `all`). Reviews every tracked file in
  the repository, presented to reviewers as newly added code. Expect a large diff and
  a correspondingly long run on a big repository.
- **Local mode** — no argument. Diffs the current branch against its merge-base with
  upstream (or `main`), with the working tree included, so committed and uncommitted
  work are reviewed together. New untracked files are appended as new-file diffs.

## Step 1: Gather context

Run the helper; it detects the mode from its argument:

```bash
REVIEW_DIR=$(~/.claude/skills/multi-review/scripts/gather_context.sh "$ARGS")
```

It writes into `REVIEW_DIR`: `diff.txt`, per-file `chunk-*` files, `chunks.tsv`
(a `file<TAB>chunk` map), and in PR mode `pr.json`, `reviews.json`,
`review_comments.json`.

Local mode covers the whole branch: the diff runs from the merge-base with upstream
to the current working tree, so both committed and uncommitted work appear in one
review. Repo mode ignores git history and emits every tracked file as a new-file
diff, so the same lens pipeline works unchanged on a full codebase.

If `diff.txt` is empty, stop and tell the user there is nothing to review. If the
argument is a PR number or URL but `gh` is unauthenticated, report it and offer
local mode.

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

**In a single message**, dispatch all Claude subagents in background so they run in parallel. After dispatching, run the external `codex exec` reviews in parallel in the background from the orchestrator (not in subagents — subagents don't inherit `permissions.allow`). Each active lens gets two perspectives: a Claude `reviewer` subagent (deep context, tool access) and a GPT-6-astra codex review (independent perspective, different training). Give each only the diff and lens-specific instructions — never this session's history.

**Do not dispatch a lens that was marked inactive in 2a.**

**Subagent write rule:** Claude subagents cannot reliably write files — `permissions.allow` does not propagate into subagent contexts (known Claude Code bug). Do **not** instruct subagents to write files. Instead, instruct each subagent to **return its findings as plain text**. After each subagent returns, the orchestrator writes its findings to the appropriate file using the Write tool.

**Path substitution rule:** Every subagent prompt must contain the literal expanded value of `$REVIEW_DIR` (e.g. `/home/user/repo/tmp/multi-review-XXXXXX`), never the shell variable `$REVIEW_DIR`. Subagents run in isolated contexts where that variable is not set.

#### Claude lens subagents (active lenses only)

1. **Broad** (always) — `reviewer` agent, filled from the superpowers
   `requesting-code-review` template:

   ```bash
   ls -d ~/.claude/plugins/cache/claude-plugins-official/superpowers/*/skills/requesting-code-review/code-reviewer.md | sort -V | tail -1
   ```

   Returns Critical/Important/Minor. Instruct it to **return findings as text** (not write a file).
   After it returns, write its response to `<REVIEW_DIR>/review-broad.md` using the Write tool.

2. **Correctness & numerics** (if active) — `reviewer` agent, Lens 1 per `~/.claude/skills/multi-review/REFERENCE.md`.
   Instruct it to **return findings as text**. After it returns, write to `<REVIEW_DIR>/review-correctness.md`.

3. **GPU performance** (if active) — `reviewer` agent, Lens 2 per `~/.claude/skills/multi-review/REFERENCE.md`.
   Instruct it to **return findings as text**. After it returns, write to `<REVIEW_DIR>/review-gpu.md`.

4. **Code quality** (if active) — `reviewer` agent, Lens 3 per `~/.claude/skills/multi-review/REFERENCE.md` (includes YAGNI pass).
   Instruct it to **return findings as text**. After it returns, write to `<REVIEW_DIR>/review-quality.md`.

#### External model reviews (active lenses only, run in parallel in background by the orchestrator)

Run each active lens directly using the Bash tool — do **not** wrap in a subagent. Subagents do not inherit `permissions.allow` (known Claude Code bug), so `codex exec` would be blocked. Run from the orchestrator's context where `Bash(codex exec *)` is allowed. Run all active lenses in parallel by passing `run_in_background: true` to each Bash tool call. Claude Code notifies you when each background task completes; collect all notifications before Step 3.

Substitute `<REVIEW_DIR>` with the literal expanded path in every command.

**Broad (always):**

```bash
codex exec -m gpt-6-astra --ephemeral \
  -o "<REVIEW_DIR>/review-broad-ext.md" \
  'Read the diff at <REVIEW_DIR>/diff.txt and do a senior code review for correctness, security, performance, and readability. One finding per line: file:line: blocker|suggestion|nit: issue. fix.' \
  > "<REVIEW_DIR>/review-broad-ext.log" 2>&1
```

**Correctness (if active):**

```bash
codex exec -m gpt-6-astra --ephemeral \
  -o "<REVIEW_DIR>/review-correctness-ext.md" \
  'Read the diff at <REVIEW_DIR>/diff.txt and review for correctness: logic errors, unchecked returns, null/dangling pointers, off-by-one, integer overflow, error paths, security at boundaries. One finding per line: file:line: blocker|suggestion|nit: issue. fix.' \
  > "<REVIEW_DIR>/review-correctness-ext.log" 2>&1
```

**GPU performance (if active):**

```bash
codex exec -m gpt-6-astra --ephemeral \
  -o "<REVIEW_DIR>/review-gpu-ext.md" \
  'Read the diff at <REVIEW_DIR>/diff.txt and review for GPU performance: memory coalescing, LDS bank conflicts, occupancy, wavefront divergence, kernel launch bounds, unnecessary host-device transfers, missed parallelism. One finding per line: file:line: blocker|suggestion|nit: issue. fix.' \
  > "<REVIEW_DIR>/review-gpu-ext.log" 2>&1
```

**Code quality (if active):**

```bash
codex exec -m gpt-6-astra --ephemeral \
  -o "<REVIEW_DIR>/review-quality-ext.md" \
  'Read the diff at <REVIEW_DIR>/diff.txt and review for code quality: dead code, magic numbers, premature abstractions, naming issues, functions over 100 lines, nesting over 3 levels, YAGNI violations. One finding per line: file:line: blocker|suggestion|nit: issue. fix.' \
  > "<REVIEW_DIR>/review-quality-ext.log" 2>&1
```

If a command fails (gateway down, codex not installed), note it and continue with Claude-only findings.

### 2d: Wait for all Claude reviewers and external model reviewers

**Do not proceed to Step 3 until every active Claude lens subagent has returned AND every background codex Bash task has sent a completion notification.**

Dispatch all Claude subagents in one message, then immediately issue all codex Bash calls with `run_in_background: true`. Claude subagents and codex tasks run concurrently. You will receive a notification for each background Bash task when it completes. Wait for all of them.

**Do not fix anything at any point during the review.** The orchestrator's only job is to run the review pipeline (Steps 1–6) and deliver the report. Whether to fix findings is the user's decision after reading the report.

## Step 3: Consolidate and validate (one pass)

Do not merge the reviews yourself. Spawn one `reviewer` agent that both merges and
validates — a single agent, not two sequential ones, since it already has the diff
and the source in context while merging. In the prompt, substitute all `<REVIEW_DIR>`
placeholders with the literal expanded path. Pass it: the literal review file paths
for all active lenses (e.g. `/home/user/repo/tmp/multi-review-XXXXXX/review-broad.md`
— only files that were actually written), the literal paths to
`<REVIEW_DIR>/diff.txt` and `<REVIEW_DIR>/chunks.tsv`, and
`~/.claude/rules/code-review.md`. Instruct it to:

**Merge:**

- Read all active review files and the diff, and apply `~/.claude/rules/code-review.md`.
- Merge findings into one list. Collapse duplicates (same `file:line` and same
  underlying issue) into a single entry, keeping the sharpest fix. When a Claude
  subagent and an external model flag the same issue, merge into one entry and note
  both sources.
- Weight by impact: correctness and security outweigh style nits; performance
  carries high weight when the change has explicit performance targets. Each lens
  finding keeps its own prefix unless this weighting clearly warrants a change; map
  the broad reviewer's scale onto the prefixes (Critical → `blocker:`, Important →
  `suggestion:`, Minor → `nit:`).
- Report dissent: if a reviewer raised a blocker the agent discounts, keep it with a
  one-line note on why, rather than silently dropping it.

**Validate, in the same pass:**

- For each merged finding, read ~50 lines around the cited line in the source and the
  matching `chunk-*` file (look up via `<REVIEW_DIR>/chunks.tsv`). It may read any file
  in the repository using its own tool access. Findings only an external model raised
  get checked first — external models lack tool access and may misread context.
- Budget at most 25 tool calls total.
- Apply a verdict to every finding: **Confirmed** (real and correctly described, keep),
  **Wrong** (incorrect, drop with a note), **Overstated** (real but exaggerated, keep
  and soften), **Unverifiable** (file not found or line missing — report as such rather
  than silently skipping).
- **Return the final merged and validated report as text** (not write a file —
  subagents cannot write).

After it returns, write its response to `<REVIEW_DIR>/review-validated.md` using the
Write tool. Read only that file to produce the final report.

If nothing survives, report "no confirmed findings" and stop.

## Step 4: Dedup against existing reviews (PR mode only)

Read `reviews.json` and `review_comments.json`. Drop any surviving finding whose
issue was already raised there. Skip this step in local and repo modes.

## Step 5: Final report

Read `REVIEW_DIR/review-validated.md` (written in Step 3). Emit two parts and post
nothing:

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
