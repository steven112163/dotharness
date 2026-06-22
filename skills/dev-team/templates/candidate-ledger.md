# Candidate Ledger

The lead maintains one ledger per task at `.claude/.dev-team/<task_name>/candidates.md`.
It is the single source of truth for what was tried, what was measured, and why a
candidate was promoted, revised, or rejected. The final report (Phase 6) is built
straight from it — best candidate plus the alternatives.

One row per candidate iteration. Refinements of the same lineage (v1 → v2 on the
same `<pr-branch>-cand-X` branch) get a new row with the parent set, so rejected attempts stay
inspectable without spawning extra branches.

```markdown
## Candidates — <task_name>

Baseline: <sha>   Target: <metric + value>

| id | parent | approach (1 line) | branch / worktree | build | QA | profile (headline metric) | decision | reason |
|----|--------|-------------------|-------------------|-------|----|---------------------------|----------|--------|
| cand-a-v1 | — | LDS double-buffer | feat/x-cand-a · wt/cand-a | ok | pass | 41% BW-util, latency-bound | revise | profiler: raise occupancy |
| cand-a-v2 | cand-a-v1 | + __launch_bounds__ | feat/x-cand-a · wt/cand-a | ok | pass | 63% BW-util | keep | best so far |
| cand-b-v1 | — | split-K | feat/x-cand-b · wt/cand-b | ok | fail | — | reject | correctness: tolerance |
```

Columns:

- **id / parent** — lineage; parent empty for an initial fan-out candidate.
- **approach** — the one-line distinguishing idea.
- **branch / worktree** — where it lives (for integration and cleanup).
- **build / QA** — `ok`/`fail` from the builder and the test-architect (QA).
- **profile** — the profiler's headline metric + verdict for this iteration.
- **decision** — `keep` | `revise` | `reject` | `promote`.
- **reason** — why, in a few words. **Never leave a rejection unexplained** — the
  reason is what makes the alternatives useful in the final report.

## Promotion rule

Promote a candidate only when it satisfies the contract's promotion criteria and has
evidence (QA pass + profiler numbers) that it meets or improves the target. Record
the reason for every non-promoted candidate rather than silently dropping it.
