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
matching set of external GPT-5.5 general-purpose subagents (one per active lens). A spawned
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
REVIEW_DIR=$(~/.claude/skills/multi-review/scripts/gather_context.sh "$ARGS")
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

**In a single message**, dispatch all active Claude subagents AND all active external model subagents so they run in parallel. Each active lens runs two reviewers simultaneously: a Claude subagent (deep context, tool access) and a `general-purpose` subagent running `codex review` (independent perspective, different model). Give each only the diff and lens-specific instructions — never this session's history.

**Do not dispatch a lens that was marked inactive in 2a.**

**Path substitution rule:** Every subagent prompt must contain the literal expanded value of `$REVIEW_DIR` (e.g. `/home/user/repo/.claude/tmp/multi-review-XXXXXX`), never the shell variable `$REVIEW_DIR`. Subagents run in isolated contexts where that variable is not set — they need the actual path to write files.

#### Claude lens subagents (active lenses only)

1. **Broad** (always) — `general-purpose` agent, filled from the superpowers
   `requesting-code-review` template:

   ```bash
   ls -d ~/.claude/plugins/cache/claude-plugins-official/superpowers/*/skills/requesting-code-review/code-reviewer.md | sort -V | tail -1
   ```

   Returns Critical/Important/Minor. Instruct it to write findings to `<REVIEW_DIR>/review-broad.md` (substitute the literal path).

2. **Correctness & numerics** (if active) — `reviewer` agent, Lens 1 per `~/.claude/skills/multi-review/REFERENCE.md`.
   Instruct it to write findings to `<REVIEW_DIR>/review-correctness.md` (substitute the literal path).

3. **GPU performance** (if active) — `reviewer` agent, Lens 2 per `~/.claude/skills/multi-review/REFERENCE.md`.
   Instruct it to write findings to `<REVIEW_DIR>/review-gpu.md` (substitute the literal path).

4. **Code quality** (if active) — `reviewer` agent, Lens 3 per `~/.claude/skills/multi-review/REFERENCE.md` (includes YAGNI pass).
   Instruct it to write findings to `<REVIEW_DIR>/review-quality.md` (substitute the literal path).

#### External model reviews (active lenses only, each a separate subagent)

For each active lens, spawn a `general-purpose` subagent. Substitute `<REVIEW_DIR>` and `<BASE_SHA>` with literal expanded values in every prompt. Each subagent runs `codex review` from the repo root and writes the output file.

`codex review` operates on the git repo directly. `gather_context.sh` writes `CODEX_REVIEW_FLAGS` to `shas.env` — it is either `--uncommitted` (dirty working tree) or `--base <SHA>` (committed branch work). Source `shas.env` to get the correct flags. Run from the repo root (the directory containing `.git`).

**Broad (always):**

> Run these commands from the repo root (cd to it first if needed):
>
> ```bash
> source "<REVIEW_DIR>/shas.env"
> codex review $CODEX_REVIEW_FLAGS \
>   'Senior code review: correctness, security, performance, readability. One finding per line: file:line: <blocker|suggestion|nit>: <issue>. <fix>.' \
>   > "<REVIEW_DIR>/review-broad-ext.md" 2>"<REVIEW_DIR>/review-broad-ext.log"
> ```
>
> Return: "done" if `<REVIEW_DIR>/review-broad-ext.md` is non-empty, otherwise the last 10 lines of the log.

**Correctness (if active):**

> ```bash
> source "<REVIEW_DIR>/shas.env"
> codex review $CODEX_REVIEW_FLAGS \
>   'Correctness review: logic errors, unchecked returns, null/dangling pointers, off-by-one, integer overflow, error paths, security at boundaries. One finding per line: file:line: <blocker|suggestion|nit>: <issue>. <fix>.' \
>   > "<REVIEW_DIR>/review-correctness-ext.md" 2>"<REVIEW_DIR>/review-correctness-ext.log"
> ```
>
> Return: "done" if `<REVIEW_DIR>/review-correctness-ext.md` is non-empty, otherwise the last 10 lines of the log.

**GPU performance (if active):**

> ```bash
> source "<REVIEW_DIR>/shas.env"
> codex review $CODEX_REVIEW_FLAGS \
>   'GPU performance review: memory coalescing, LDS bank conflicts, occupancy, wavefront divergence, kernel launch bounds, unnecessary host-device transfers, missed parallelism. One finding per line: file:line: <blocker|suggestion|nit>: <issue>. <fix>.' \
>   > "<REVIEW_DIR>/review-gpu-ext.md" 2>"<REVIEW_DIR>/review-gpu-ext.log"
> ```
>
> Return: "done" if `<REVIEW_DIR>/review-gpu-ext.md` is non-empty, otherwise the last 10 lines of the log.

**Code quality (if active):**

> ```bash
> source "<REVIEW_DIR>/shas.env"
> codex review $CODEX_REVIEW_FLAGS \
>   'Code quality review: dead code, magic numbers, premature abstractions, naming issues, functions over 100 lines, nesting over 3 levels, YAGNI violations. One finding per line: file:line: <blocker|suggestion|nit>: <issue>. <fix>.' \
>   > "<REVIEW_DIR>/review-quality-ext.md" 2>"<REVIEW_DIR>/review-quality-ext.log"
> ```
>
> Return: "done" if `<REVIEW_DIR>/review-quality-ext.md` is non-empty, otherwise the last 10 lines of the log.

### 2d: Wait for all reviewers

**Do not proceed to Step 3 until every active Claude lens subagent and external model subagent has returned.**

If an external call fails (env vars not set, gateway down), note it and continue with
the Claude-only findings.

## Step 3: Consolidate

Do not merge the reviews yourself. Spawn one `reviewer` agent as the
**consolidator**. In the prompt, substitute all `<REVIEW_DIR>` placeholders with the
literal expanded path. Pass it: the literal review file paths for all active lenses
(e.g. `/home/user/repo/.claude/tmp/multi-review-XXXXXX/review-broad.md` — only files
that were actually written), the literal path to `<REVIEW_DIR>/diff.txt`, and
`~/.claude/rules/code-review.md`. Instruct it to:

- Read all active review files and the diff, and apply `~/.claude/rules/code-review.md`.
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
- Write the consolidated review to `<REVIEW_DIR>/review-consolidated.md` (literal path).

The consolidator returns only the file path and a one-line summary. Do not read
`review-consolidated.md` yourself — pass its literal path to the validator in Step 4.

If the consolidator finds nothing, report "no findings" and stop.

## Step 4: Validate

Spawn one `general-purpose` subagent as the **validator**. Substitute all
`<REVIEW_DIR>` placeholders with the literal expanded path before sending the prompt.
Pass it the literal paths to `<REVIEW_DIR>/review-consolidated.md`,
`<REVIEW_DIR>/diff.txt`, and `<REVIEW_DIR>/chunks.tsv`. Instruct it to:

1. Read `<REVIEW_DIR>/review-consolidated.md` first to extract each cited `file:line` reference.
2. For each finding, read ~50 lines around the cited line in the source and the
   matching `chunk-*` file (look up via `<REVIEW_DIR>/chunks.tsv`). The validator may read any
   file in the repository — it should use its own tool access to locate source files
   from the paths cited in the consolidated review.
3. Budget at most 15 tool calls total.
4. Report any finding it cannot verify (file not found, line missing) as unverifiable
   rather than silently skipping it.
5. Write a final validated report to `<REVIEW_DIR>/review-validated.md` (literal path) with verdicts
   applied:

- **Confirmed** — issue is real and correctly described. Keep.
- **Wrong** — claim is incorrect. Drop with a note.
- **Overstated** — issue exists but is exaggerated. Keep and soften.

The validator writes `<REVIEW_DIR>/review-validated.md` and returns its path. Do not read any
other review file. Read only `<REVIEW_DIR>/review-validated.md` (literal path) to produce the final
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
