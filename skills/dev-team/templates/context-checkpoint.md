# Context Checkpoint

```markdown
# Context Checkpoint: <agent-name>

**Role:** <role>
**Timestamp:** <ISO 8601>
**Type:** checkpoint | handoff
**Context remaining:** ~<N>%

## Current task

What I am working on right now. One sentence.

## Work completed

- <item>: <outcome>
- ...

## Work remaining

- <item>: <what needs to happen>
- ...

## Key decisions

| Decision | Rationale |
|----------|-----------|
| <what was decided> | <why> |

## Blockers

- <blocker>: <who/what is blocking, what would unblock it>

(Write "None" if no blockers.)

## Role-specific state

Fill in the section that matches your role. Delete the others.

### Implementer
- **Files created/modified:** <list>
- **Current code state:** compiles / broken at <error>
- **Uncommitted changes:** yes/no

### Builder
- **Build configuration:** <cmake flags, targets>
- **Last build status:** pass / fail at <error>
- **Warnings:** <count and summary>

### Principal Researcher
- **Questions answered:** <list with one-line findings>
- **Ongoing research threads:** <list>
- **Researcher states:** researcher-1: <status>, researcher-2: <status>, ...

### Software Architect
- **Reviews completed:** <list with outcomes>
- **Outstanding feedback:** <list>
- **Reviewer states:** reviewer-1: <status>, reviewer-2: <status>, ...

### Test Architect
- **Test plan:** <summary or file path>
- **Testers spawned:** <count and assignments>
- **Results so far:** <pass/fail counts, notable failures>
- **Remaining tests:** <list>

### Profiler
- **Candidates profiled:** <id: verdict + headline metric>
- **Modes run / pending:** <ck-profile modes done, what is queued>
- **Ranked directions returned:** <per candidate, top direction>
- **In-flight profiling run:** <candidate or "none" — only one at a time>

### Researcher
- **Assigned focus:** <research question or sub-topic>
- **Findings so far:** <list>
- **Unfinished work:** <what remains>

### Reviewer
- **Assigned focus:** <review domain>
- **Findings so far:** <list>
- **Unfinished work:** <what remains>

### Tester
- **Assigned tests:** <list>
- **Results:** <pass/fail for each>
- **Tests remaining:** <list>

## Checkpoint file reference

(Handoff only) Path to earlier 60% checkpoint, if one exists: <path or "N/A">
```

## Usage

### 60% checkpoint

1. Copy the template above into `.claude/.dev-team/<task_name>/<role>-checkpoint.md`.
2. Fill in the common sections and your role-specific section.
3. Set **Type** to `checkpoint`.
4. Continue working. Do not message the lead.
5. After this point, check context usage before every heavy operation (large file reads, long code generation, verbose tool output). If below 40%, skip the operation and proceed to handoff.

### 40% handoff

1. Stop current work.
2. Copy the template into `.claude/.dev-team/<task_name>/<role>-handoff.md`.
3. Fill in all sections, including **Work remaining** and **Blockers**.
4. Set **Type** to `handoff`.
5. Reference the earlier checkpoint file if one exists.
6. Message the lead with the file path and ask for a replacement.
