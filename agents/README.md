# Agents

Native subagents in `agents/`, symlinked individually to `~/.claude/agents/`. Each is reusable two ways: as a one-shot **delegated subagent** (returns a result to the caller, keeping its work out of the main context) or as an **agent-team teammate** (spawned into a team, where it also gains the coordination tools). They are worker roles — they never spawn other agents.

- **researcher** — web + codebase research; returns a short, source-cited report. Preloads the `research` skill.
- **implementer** — writes or modifies code to a spec in an isolated context.
- **reviewer** — reviews a diff against the code-review checklist; returns severity-prefixed findings.
- **tester** — authors and runs tests; reports pass/fail and benchmark-vs-target.
- **builder** — builds a CK target via `ckBuild`; reports errors and warnings.
- **profiler** — profiles a built target via the `ck-profile` skill; returns ranked optimization directions.

Each definition also carries a task-list `color`: researcher cyan, implementer green, reviewer purple, tester yellow, builder blue, profiler orange.

Each agent also references external skills where useful — for example `implementer` uses `superpowers:test-driven-development`, `superpowers:systematic-debugging`, and `superpowers:verification-before-completion`; `reviewer` uses the built-in `/review` and `/security-review`; `profiler` pairs `ck-profile` with `superpowers:systematic-debugging`.

The `dev-team` skill spawns these as teammates and pairs the research/review/QA workers with coordinators (principal-researcher, software-architect, test-architect) that synthesize their output. Because a subagent definition's `tools`/`model` apply in both modes (its `skills` preload only in delegated-subagent mode), the same six files serve solo delegation and team roles. The lead drives the workflow with orchestration skills — `superpowers:writing-plans`/`executing-plans`, `using-git-worktrees`, `dispatching-parallel-agents`, `requesting-code-review`, `verification-before-completion`, and `finishing-a-development-branch`.
