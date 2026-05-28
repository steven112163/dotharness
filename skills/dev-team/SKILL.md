---
name: dev-team
description: Use when tackling complex development tasks that benefit from parallel research, implementation, code review, building, and testing by a coordinated agent team. Triggers include kernel development, performance-sensitive code, tasks requiring both correctness verification and performance profiling, or any workload where a single agent would struggle with scope.
---

# Dev Team

## Overview

Orchestrate a hierarchical agent team for complex development tasks. The lead (you, the current session) coordinates five specialized groups — researchers, implementer, reviewers, builder, and QA — through six phases: startup, implementation loop, testing, verification, reporting, and post-mortem.

**Core principle:** Group leaders (professor, staff engineer, QA head) are both participants and gatekeepers. They contribute their own expertise, aggregate group input, and deliver a single consolidated response. No agent outside a group contacts group members directly.

## When to Use

- Complex features requiring research, implementation, review, and testing
- Performance-sensitive code requiring benchmarking and profiling
- Tasks large enough to benefit from parallel research and implementation
- Work needing both correctness verification and performance validation

**Do not use for:** Single-file fixes, documentation updates, simple refactors, or tasks completable by one agent in a few iterations.

## Team Structure

```
Lead (you)
├── Implementer
├── Professor (research gatekeeper)
│   ├── PHD-1
│   ├── PHD-2
│   └── PHD-3
├── Staff Engineer (review gatekeeper)
│   ├── Senior-1
│   ├── Senior-2
│   └── Senior-3
├── Builder
└── QA Head (test gatekeeper)
    ├── Tester-1
    ├── ...
    └── Tester-N
```

### Roles

| Agent | Responsibility | Spawned by | Contactable by |
|-------|---------------|------------|----------------|
| **Lead** | Orchestrate all groups, decompose user task, gate phase transitions, compile final report | User | Everyone |
| **Implementer** | Write code in the worktree, fix bugs from builder, fix issues from review feedback | Lead | Lead, builder, staff-engineer, professor |
| **Professor** | Receive research questions from any agent. Route to PHDs, contribute own research, aggregate all opinions, deliver final answer. Professor makes the final call. | Lead | Any agent in the team |
| **PHD-1, PHD-2, PHD-3** | Answer research questions assigned by professor | Professor | Professor only |
| **Staff Engineer** | Review code personally, assign reviews to seniors, aggregate all feedback (including own), deliver consolidated feedback to implementer. Staff engineer makes the final call. | Lead | Lead, implementer |
| **Senior-1, Senior-2, Senior-3** | Review code assigned by staff engineer | Staff Engineer | Staff engineer only |
| **Builder** | Build implementer's code, report compilation errors/warnings to implementer | Lead | Lead, implementer |
| **QA Head** | Receive task context from lead. Design test plan (or receive one from user via lead). Spawn testers, assign test tasks, aggregate results, report to lead. | Lead | Lead |
| **Tester-1 ... N** | Execute assigned tests, report results to QA head. Count decided by QA head. | QA Head | QA head only |

### Role Prompts

Each agent receives a role-specific prompt when spawned. Read the corresponding file from `roles/` and include its content in the Agent tool's `prompt` parameter:

```
roles/
  implementer.md
  professor.md
  phd.md
  staff-engineer.md
  senior-engineer.md
  builder.md
  qa-head.md
  tester.md
```

Sub-leads (professor, staff engineer, QA head) read the role files for their group members and include them when spawning.

### Communication Rules

These are strict. Violating them defeats the purpose of the hierarchy.

- **Research group:** Only the professor is contactable from outside. PHDs talk only to the professor.
- **Review group:** Only the staff engineer is contactable from outside. Seniors talk only to the staff engineer.
- **QA group:** Only the QA head is contactable from outside. Testers talk only to the QA head.
- **Professor is open:** Any agent can send research questions to the professor. This is the one cross-group channel.
- **The lead does NOT write code.** The implementer writes all code. The lead orchestrates.

## Workflow

```dot
digraph workflow {
    rankdir=TB;
    node [shape=box];

    startup [label="Phase 1: Startup\nCreate team, worktree, spawn agents"];
    impl [label="Implementer writes/updates code"];
    build [label="Builder builds code"];
    build_fail [label="Implementer fixes\nbuild errors"];
    review [label="Staff Engineer initiates review\n(own review + assigns seniors,\naggregates all feedback)"];
    lead_gate [label="Lead evaluates\nreview results"];
    test [label="Phase 3: Testing\nQA Head designs plan,\nspawns testers, runs tests"];
    verify [label="Phase 4: Verification\nLead spot-checks results"];
    report [label="Phase 5: Reporting\nLead compiles final report"];
    postmortem [label="Phase 6: Post-Mortem\n(optional)"];
    escalate [label="Escalate to user\n(5 iterations reached)"];

    build_ok [shape=diamond, label="Build\nOK?"];
    review_ok [shape=diamond, label="Lead\napproves?"];
    iter_check [shape=diamond, label="Iteration\n< 5?"];

    startup -> impl;
    impl -> build;
    build -> build_ok;
    build_ok -> build_fail [label="fail"];
    build_fail -> build [label="rebuild"];
    build_ok -> review [label="pass"];
    review -> lead_gate;
    lead_gate -> review_ok;
    review_ok -> test [label="approve"];
    review_ok -> iter_check [label="changes\nneeded"];
    iter_check -> impl [label="yes"];
    iter_check -> escalate [label="no"];
    test -> verify;
    verify -> report;
    report -> postmortem;
}
```

### Phase 1: Startup

1. Analyze the user's task.
2. Create the team (`dev-team`).
3. Create a worktree for code isolation.
4. Spawn top-level agents: implementer, professor, staff-engineer, builder, qa-head.
5. Professor spawns phd-1, phd-2, phd-3.
6. Staff engineer spawns senior-1, senior-2, senior-3.
7. Implementer begins working in the worktree. If it needs information, it asks the professor.

### Phase 2: Implementation Loop (max 5 iterations)

1. **Implementer** writes or updates code.
2. **Builder** builds the code.
   - On failure: builder reports errors to implementer. Implementer fixes and builder rebuilds. The build-fix sub-loop does not increment the iteration counter — only a complete implement-build-review cycle does.
   - On success: proceed to review.
3. **Staff engineer** initiates review: reviews the code personally, assigns seniors to review, aggregates all feedback (including own), and sends consolidated feedback to implementer.
4. **Lead evaluates** the review results. The lead — not the staff engineer — gates the transition to Phase 3.
   - If the lead judges the code quality sufficient: proceed to Phase 3.
   - If changes are needed: **increment iteration counter**, implementer fixes, return to step 1.
5. If 5 iterations are reached without convergence: **stop and report to the user** with the review feedback history.

**Iteration counting:** One iteration = one complete cycle through steps 1-4 that ends with "changes needed." Build-fix retries within step 2 do not count as separate iterations.

**The lead must actively evaluate review quality.** Do not rubber-stamp the staff engineer's approval. Read the consolidated feedback, assess whether the concerns are addressed, and make an independent judgment.

### Phase 3: Testing

1. Lead provides task context and implementation results to the QA head.
2. If the user provided a test plan, lead passes it to the QA head. Otherwise, the QA head designs the test plan.
3. QA head spawns tester-1 through tester-N based on the plan.
4. Each tester executes assigned tests and reports to the QA head.
5. QA head summarizes all results and reports to the lead.

**Test dimensions** (QA head selects based on the task):
- **Correctness:** unit tests, integration tests, edge cases
- **Performance:** benchmarks, profiling, bottleneck analysis
- **Compatibility:** different platforms, architectures, or configurations
- **Safety:** sanitizers, bounds checking, static analysis

**If tests fail:** Lead decides whether to send the implementer back to Phase 2 (iteration counter resets to 1 for the new fix cycle) or report to the user.

### Phase 4: Verification

Before compiling the final report, the lead independently spot-checks a subset of test results and review claims:

1. Pick 1-2 test results from the QA head's report and verify them by re-running or inspecting the output directly.
2. Check that the staff engineer's "approved" assessment matches the actual state of the code — read the final diff and confirm blockers were resolved.
3. If any spot-check fails, send the implementer back to Phase 2 (iteration counter resets) or escalate to the user.

**Do not skip this phase.** Testers can produce false positives. Reviewers can miss regressions introduced by late fixes. Trust but verify.

### Phase 5: Reporting

Compile and present to the user:
- Implementation summary (what was built, key design decisions)
- Review outcome (staff engineer's final assessment)
- Build status (clean build, remaining warnings)
- Test results from each tester (pass/fail, metrics)
- Performance profiling data
- Verification results (what the lead spot-checked and confirmed)
- Unresolved issues or known limitations

### Phase 6: Post-Mortem (optional)

After reporting, capture lessons learned for future invocations:

1. What went well? (e.g., research group answered quickly, review caught a critical bug early)
2. What went wrong? (e.g., build failed 4 times due to missing include, iteration limit almost reached)
3. What should change next time? (e.g., ask the professor about API compatibility before implementing, assign Senior-2 to correctness instead of performance)

Save the post-mortem to `docs/post-mortems/<date>-<topic>.md` in the worktree. The lead decides whether this phase runs based on the complexity of the task — skip it for straightforward tasks that completed without issues.

## Quick Reference

| What | Who | Rule |
|------|-----|------|
| Ask a research question | Any agent → Professor | Professor routes to PHDs, aggregates, responds |
| Request code review | Lead → Staff Engineer | Staff engineer reviews + assigns seniors, aggregates, responds to implementer |
| Report build error | Builder → Implementer | Direct, no intermediary needed |
| Design test plan | Lead → QA Head | QA head designs (or receives user's plan via lead) |
| Spawn testers | QA Head | QA head decides count and assignments |
| Gate Phase 2 → Phase 3 | Lead | Lead evaluates review results, not staff engineer |
| Verify test results | Lead | Spot-check 1-2 results before reporting |
| Post-mortem | Lead | Optional, for complex tasks. Save to docs/post-mortems/ |
| Escalate on iteration limit | Lead → User | After 5 implementation loop iterations |

## Common Mistakes

**Flat team instead of hierarchy.** Without this skill, agents create 3-4 direct reports (one researcher, one tester, one reviewer). The skill requires group leaders with subordinates: professor + 3 PHDs, staff engineer + 3 seniors, QA head + N testers.

**Lead writes code.** The lead orchestrates. The implementer writes all code. If you find yourself editing files, stop — that is the implementer's job.

**Skipping the lead gate.** After the staff engineer sends review feedback, the lead must independently evaluate whether the code is ready for testing. Do not pass review approval through to Phase 3 without reading and assessing the feedback yourself.

**Direct contact with group members.** The implementer must not message PHDs or seniors directly. All cross-group requests go through the group leader (professor or staff engineer).

**Shutting down researchers early.** Keep the research group alive throughout the implementation loop. The implementer or builder may need research help at any point, not just at the start.

**No worktree.** Always create a worktree. The implementer works in the worktree so the main workspace stays clean.

## Context Management

Long-running agents will exhaust their context window. Two thresholds trigger different actions.

### 50% Checkpoint (scratchpad)

When context usage reaches ~50% remaining, the agent writes a checkpoint to a scratchpad file without requesting replacement:
1. Write current state to a file in the worktree: `.context-checkpoints/<agent-name>-checkpoint.md`.
2. Include: work completed, current task, key decisions, any state that would be expensive to reconstruct.
3. Continue working. Do not message the lead or sub-lead.

This creates a recovery point in case the agent crashes or gets stuck. The checkpoint file is available to the replacement agent if a handoff becomes necessary later.

### 30% Handoff (ask-first)

When context usage reaches ~30% remaining, the agent initiates a full handoff:
1. Agent writes a handoff summary: current state, work completed, work remaining, key decisions made, any blockers. Reference the 50% checkpoint file if one exists.
2. Agent messages its direct lead:
   - Group members (PHDs, seniors, testers) → their sub-lead (professor, staff engineer, QA head)
   - Top-level agents (implementer, professor, staff engineer, builder, QA head) → the lead
3. The lead/sub-lead reviews the handoff, spawns a fresh agent with the same role prompt plus the handoff summary appended, and shuts down the old agent.

**The agent does not self-replace.** It asks and waits. The lead/sub-lead decides when to perform the swap.
