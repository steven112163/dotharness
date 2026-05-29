# Task Brief

Append a filled copy of this brief to the `prompt` of every Agent spawn, after the
role file content. The role file says who the agent is; the brief says what this
specific assignment is.

```markdown
## Task brief

**Task name:** <task_name>
**Team:** dev-team
**Report to:** <lead | professor | staff-engineer | qa-head>

**Objective:** What this agent must accomplish. One or two sentences, concrete.

**Inputs:** Where to find what you need — worktree path, files, prior reports under
`.claude/.dev-team/<task_name>/`, the user's spec.

**Output format:** Exactly what to return and how.
- Short answer (a spec value, pass/fail): reply inline in your message.
- Long output (review, deep report, test report): write to
  `.claude/.dev-team/<task_name>/<role>-<kind>.md` and reply with the path plus a
  summary of three lines or fewer.

**Boundaries:** What NOT to touch or do. Files outside scope, agents you must not
contact directly, decisions reserved for the lead.

**Done-criteria:** How both of us know the task is finished. The verifiable
condition, not a feeling ("review covers every applicable checklist section and
states a blocker/approve verdict", "benchmark reports TFLOPS against the stated
target").

**Budget (optional):** A soft ceiling on effort for narrow tasks — e.g. tool-call
or iteration cap — so the agent scales effort to the question.
```

## Why each field exists

- **Objective + done-criteria** turn the assignment into a contract. Specification
  ambiguity and unclear roles are the dominant cause of duplicated and misdirected
  work in agent teams.
- **Output format** is what makes artifact returns actually happen: it tells the
  agent when to write a file and return a pointer instead of pasting a wall of text.
- **Boundaries** prevent collateral edits and cross-group contact violations.
- **Budget** lets the lead scale effort to complexity rather than over-researching a
  one-line question.
