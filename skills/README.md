# Skills

## Own skills

Located in `skills/`, symlinked individually to `~/.claude/skills/`.

- **dev-team** — evidence-driven agent team. The lead (the only spawner) spawns native worker agents (researcher, implementer, reviewer, tester, builder, profiler) and synthesis coordinators (principal-researcher, software-architect, test-architect) as teammates, on demand, and stops them once they deliver. 8-phase candidate workflow: clarify a task contract, draft/plan, fan out 2–3 candidate implementations in worktrees, refine on profiling evidence, QA, verify, and report the best candidate plus alternatives.
- **research** — four-mode research skill (socratic, direct, deep, adversarial) with anti-sycophancy safeguards. Usable by both humans and agents. Integrated into dev-team role prompts.
- **survey** — literature survey skill. Discovers papers from arXiv, Semantic Scholar, Crossref (DOI metadata for published IEEE/ACM venues), and OpenReview, or works from a curated set, then synthesizes a full report: summary, PRISMA-style audit trail, thematic synthesis, comparison table, and gaps. A stdlib `paper_search.py` helper grounds every citation in retrieved metadata; `REFERENCE.md` documents the raw source APIs.
- **create-pr** — create a pull request following the CK team's PR template (motivation, technical details, test plan, test result, submission checklist).
- **ck-profile** — profile a Composable Kernel target two ways: static compile-time resource analysis (VGPR/AGPR/SGPR, occupancy ceiling, spills, scratch, LDS) and dynamic runtime profiling with rocprofv3 (kernel timing, HBM traffic, L2 hit ratio, occupancy, VALU). Per-arch hardware specs (`gpu_specs.py`) drive a device-spec block and an occupancy-util ratio, with a roofline-lite compute/memory/latency bottleneck verdict.
- **council** — adversarial two-model debate: Claude and GPT-5.6-sol generate independent positions, challenge each other for up to 3 rounds, converge on the strongest answer by argument quality — not agreement. Anti-sycophancy guards throughout.
- **llm** — query an external LLM (GPT, Gemini, DeepSeek, Llama, etc.) for a second opinion, cross-check, or model comparison. Default model gpt-5.6-sol (1M context). Usable by humans and agents; also self-triggers when a second perspective would strengthen an answer.
- **multi-review** — multi-angle code review. Fans out up to eight reviewers in parallel (four Claude subagents: broad generalist + correctness/numerics, GPU performance, code quality lenses; plus four GPT-5.6-sol `codex exec` calls, one per active lens), consolidates and validates findings against source, dedups against existing PR reviews in PR mode, and reports a merged severity-ranked review. No GitHub posting. `REFERENCE.md` holds the per-lens checklists; `gather_context.sh` builds the diff/chunk context.

`research`, `survey`, `ck-profile`, and `multi-review` carry an `argument-hint` to guide `/`-invocation autocomplete.

## Third-party (mattpocock/skills, MIT)

Engineering and productivity skills, linked from the submodule:

- **diagnose** — disciplined diagnosis loop for hard bugs
- **grill-with-docs** — grilling session with domain model and ADR updates
- **grill-me** — relentless interview about a plan or design
- **tdd** — red-green-refactor loop
- **to-prd** — synthesize conversation into a PRD
- **to-issues** — break a plan into independent GitHub issues
- **triage** — issue triage through role-based state machine
- **improve-codebase-architecture** — find deepening opportunities in a codebase
- **zoom-out** — higher-level perspective on unfamiliar code
- **prototype** — build throwaway prototypes to flesh out a design
- **handoff** — compact conversation into a handoff doc
- **write-a-skill** — create new skills with proper structure
- **setup-matt-pocock-skills** — one-time prerequisite that records this repo's issue tracker, triage labels, and domain-doc layout for the skills above (manual only; not model-invoked)

## Plugins

Installed by `setup.sh` via the Claude CLI. The `claude-plugins-official` marketplace is registered by default; `setup.sh` adds the `anthropic-agent-skills` (`anthropics/skills`), `caveman` (`JuliusBrussee/caveman`), and `ponytail` (`DietrichGebert/ponytail`) marketplaces before installing from them.

- **superpowers** (`claude-plugins-official`) — disciplined workflows (brainstorming, TDD, debugging).
- **example-skills** (`anthropic-agent-skills`) — bundle of 12 Anthropic example skills. Used here for **skill-creator** (author/eval/optimize skills), **frontend-design** and **theme-factory** (styling the ck-profile HTML reports), **webapp-testing** (Playwright — screenshot-verify the reports), and **mcp-builder**. The rest of the bundle stays inert unless its trigger fires.
- **claude-api** (`anthropic-agent-skills`) — Claude API / Anthropic SDK reference for building LLM-powered tooling.
- **caveman** (`caveman`) — always-on ultra-compressed output (~75% fewer prose tokens), activated every session by its `SessionStart`/`UserPromptSubmit` hooks (needs `node` on `PATH`). Replaces the on-demand mattpocock caveman skill, which `setup.sh` therefore stops linking.
- **ponytail** (`ponytail`) — always-on "lazy senior dev" mode that steers generated code toward YAGNI and minimal solutions (`PONYTAIL_DEFAULT_MODE` sets the level, default `full`). Reinforces `coding-standards.md`.

Plugin granularity is per-plugin: `example-skills` is all-or-nothing, so the wanted skills arrive bundled with others. Skills are description-triggered and lazy, so unused ones cost nothing at runtime.

## Externally-managed

Installed globally by `setup.sh` via their own package managers/installers, not sourced from `skills/` or a submodule:

- **[playwright-cli](https://github.com/microsoft/playwright-cli)** — browser automation. `setup.sh` installs `@playwright/cli` via npm, then runs `playwright-cli install --skills` and `playwright-cli install-browser`.
- **[graphify](https://github.com/Graphify-Labs/graphify)** — codebase knowledge-graph generation. `setup.sh` installs `graphifyy` via pipx, then runs `graphify install` (Claude) and `graphify install --platform codex` (Codex, when present).
