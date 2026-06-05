# Task Contract

Filled by the lead in **Phase 0** from an iterative clarification with the user
(`AskUserQuestion`). Write the result to `.claude/.dev-team/<task_name>/contract.md`.
Do not start drafting or implementing until every required field is settled — an
ambiguous contract is the dominant cause of wasted candidate builds.

```markdown
## Task contract

**Task name:** <task_name>
**Baseline commit:** <sha on the PR branch — candidates are cut from here>

**Objective:** The user-facing goal, one or two concrete sentences.

**Inputs / outputs:** Shapes, dtypes, tensors, the dispatch path(s) in scope. For a
kernel: the specific representative shapes to optimize for (not arbitrary ones).

**Correctness requirements:** Required behavior, tolerances, invariants.

**Validation command:** The exact command that proves correctness. Must be runnable
by QA on any candidate worktree.

**Performance target:** The measurable goal (e.g. TFLOPS, latency, BW-util %), and
against what reference (current baseline, a library, a prior version).

**Evaluation command:** The exact command that measures the target, if different
from validation.

**Constraints:** Allowed languages, libraries, APIs, deployment limits; anything
off-limits.

**Promotion criteria:** What must be true before a candidate is accepted — passes
validation AND meets/improves the target with profiling evidence.
```

## Why each field exists

- **Baseline commit** pins an identical starting point for every candidate worktree,
  so the profiler's before/after comparison is honest.
- **Validation + evaluation commands** are what make QA and the profiler
  reproducible across candidates — same command, every worktree.
- **Promotion criteria** turn "is it good?" into a checkable contract, so the lead
  promotes on evidence, not vibes, and records *why* rejected candidates lost.
