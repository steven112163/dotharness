---
name: council
argument-hint: "<question>"
description: Fan out a question to Claude and GPT-5.6-sol in parallel, run up to 3 rounds of adversarial debate where each model challenges the other's weakest argument and updates its position, assess convergence after each round with a dedicated subagent, then synthesize and deliver a final answer weighted by argument quality — not consensus.
---

# Council

Coordinates an adversarial two-model debate: Claude and GPT-5.6-sol generate independent positions, challenge each other directly for up to 3 rounds, and converge on the strongest answer by argument quality — not agreement.

## When to use

- User asks a hard technical or factual question where a second perspective reduces error
- User says "council", "ask GPT", "get a second opinion", "debate this"
- On your own initiative: question is high-stakes, has conflicting priors, or your confidence is low

## When NOT to use

- Simple factual lookups (just answer directly)
- Creative or subjective tasks (debate adds noise, not signal)
- Question already well-resolved in context

## Protocol

### Phase 1 — Independent answers (parallel, round 0)

Create a temp dir under the repo's `tmp/` (gitignored, not in `/tmp`):

```bash
_repo_root=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
mkdir -p "$_repo_root/tmp"
COUNCIL_DIR=$(mktemp -d "$_repo_root/tmp/council-XXXXXX")
mkdir -p "$COUNCIL_DIR/round-0"
```

Write the question to a file first (avoids shell injection and handles multiline questions):

```bash
printf '%s' "<question>" > "$COUNCIL_DIR/question.txt"
```

**Write your own independent answer to `$COUNCIL_DIR/round-0/claude.txt` first.** Form and commit your position before spawning the GPT subagent — this is the anti-anchoring guarantee.

Then spawn a `general-purpose` subagent to get GPT's response. Provide the literal expanded path values in the prompt (subagents do not inherit shell variables):

> Run this command:
>
> ```bash
> codex exec -m gpt-5.6-sol --ephemeral -o "<COUNCIL_DIR>/round-0/gpt.txt" < "<COUNCIL_DIR>/question.txt" > "<COUNCIL_DIR>/round-0/gpt.log" 2>&1
> ```
>
> Return: "done" if `<COUNCIL_DIR>/round-0/gpt.txt` exists and is non-empty, otherwise the error from the log.

**Do not proceed until the subagent returns.**

**Output file note:** For `codex exec` runs, `-o <file>.txt` is the model's response; the log (`<file>.log`) is the codex session transcript and should not be read for content.

### Phase 2 — Debate loop (up to 3 rounds)

Track the current round directory as `ROUND_DIR="$COUNCIL_DIR/round-0"` and a round counter `N=0`.

Repeat the following steps until the convergence checker emits CONVERGED, or until `N` reaches 3:

#### Step A — Check convergence

Spawn one `reviewer` subagent as the **convergence checker** with this fully self-contained prompt (substitute literal values for `<QUESTION>`, `<ROUND_DIR>`):

> You are a convergence checker for a two-model debate. Read the two responses to: `<QUESTION>`
>
> Files in `<ROUND_DIR>`: `claude.txt` (Claude), `gpt.txt` (GPT-5.6-sol).
>
> For each model:
>
> 1. **Steelman:** Restate the model's position in its strongest, most logical form.
> 2. **Flaw:** Identify the single weakest load-bearing step. Restrict to: (a) unspoken premises, (b) logical non-sequiturs, (c) boundary or edge cases where the argument breaks. **Materiality filter:** If fixing this flaw would not change the final answer, write `Flaw: none`.
> 3. **Materiality:** Why fixing this flaw would change the final answer. Omit if Flaw is none.
>
> Then assess convergence:
>
> - CONVERGED: both positions agree on the core claim **and** you cannot find a material flaw in either after a genuine attack. Fast consensus is a warning signal — if both models agreed quickly with thin reasoning, do NOT emit CONVERGED.
> - CONTINUE: material disagreements remain or you found a material flaw that has not been addressed.
>
> Write to `<ROUND_DIR>/convergence.txt` using **exactly** this format:
>
> ```text
> === VERDICT ===
> CONVERGED|STALEMATE|CONTINUE
> <one-line reason>
>
> === ASSESSMENT: CLAUDE ===
> Steelman: <restate Claude's position at its strongest>
> Flaw type: premise|non-sequitur|boundary|none
> Flaw: <specific objection, or "none">
> Materiality: <why this changes the final answer, or "none" if Flaw is none>
>
> === ASSESSMENT: GPT ===
> Steelman: <restate GPT's position at its strongest>
> Flaw type: premise|non-sequitur|boundary|none
> Flaw: <specific objection, or "none">
> Materiality: <why this changes the final answer, or "none" if Flaw is none>
>
> === END ===
> ```
>
> Return the path to convergence.txt and the verdict line.

Wait for the subagent to complete. Extract the verdict — the non-blank line immediately after `=== VERDICT ===`.

If verdict is CONVERGED, exit the loop and proceed to Phase 3.
If `N` equals 3, set `VERDICT="CONTINUE (round cap reached)"`, exit the loop, and proceed to Phase 3.
Otherwise, proceed to Step B.

#### Step B — Adversarial debate round

Increment the round counter: `N=$((N + 1))`. Set `NEXT_DIR="$COUNCIL_DIR/round-$N"`.

```bash
mkdir -p "$NEXT_DIR"
```

Build each model's debate prompt. Each model receives: the original question, both previous-round responses (anonymized as Position A/B to prevent identity bias), its own prior response identified, and instructions to challenge the opponent's weakest argument then state its updated position.

```bash
# Build anonymized peer context (Claude=A, GPT=B)
{
  printf "Position A:\n"; cat "<ROUND_DIR>/claude.txt"
  printf "\nPosition B:\n"; cat "<ROUND_DIR>/gpt.txt"
} > "$NEXT_DIR/positions.txt"

DEBATE_INSTRUCTIONS='Identify the single weakest argument in the opposing position and explain why it fails — be specific about which premise is unspoken, which step is a non-sequitur, or which boundary case breaks the argument. Then state your own updated position. Rules:
- Challenge only arguments that materially affect the conclusion.
- Concede points only when the opponent introduced a verified factual contradiction — not merely an alternative framing.
- If you are maintaining your position, explain why the challenge does not change the conclusion.
- Do not begin with agreement or praise. State your challenge directly.'

# Claude prompt (Claude was Position A)
{
  printf 'Original question:\n'; cat "<COUNCIL_DIR>/question.txt"
  printf '\nBoth positions from the previous round (evaluate arguments on logic, not identity):\n'
  cat "$NEXT_DIR/positions.txt"
  printf '\nYour previous response (you were Position A):\n'
  cat "<ROUND_DIR>/claude.txt"
  printf '\nOpponent flaw identified by the convergence checker:\n'
  awk '/=== ASSESSMENT: GPT ===/,/^=== /' "<ROUND_DIR>/convergence.txt" | grep -v "^==="
  printf '\nInstructions:\n%s\n' "$DEBATE_INSTRUCTIONS"
} > "$NEXT_DIR/prompt-claude.txt"

# GPT prompt (GPT was Position B)
{
  printf 'Original question:\n'; cat "<COUNCIL_DIR>/question.txt"
  printf '\nBoth positions from the previous round (evaluate arguments on logic, not identity):\n'
  cat "$NEXT_DIR/positions.txt"
  printf '\nYour previous response (you were Position B):\n'
  cat "<ROUND_DIR>/gpt.txt"
  printf '\nOpponent flaw identified by the convergence checker:\n'
  awk '/=== ASSESSMENT: CLAUDE ===/,/^=== /' "<ROUND_DIR>/convergence.txt" | grep -v "^==="
  printf '\nInstructions:\n%s\n' "$DEBATE_INSTRUCTIONS"
} > "$NEXT_DIR/prompt-gpt.txt"
```

**Read `$NEXT_DIR/prompt-claude.txt` and write your debate response to `$NEXT_DIR/claude.txt` first.** Commit your position before spawning the GPT subagent.

Then spawn a `general-purpose` subagent for the GPT debate call. Substitute literal expanded paths:

> Run this command:
>
> ```bash
> codex exec -m gpt-5.6-sol --ephemeral -o "<NEXT_DIR>/gpt.txt" < "<NEXT_DIR>/prompt-gpt.txt" > "<NEXT_DIR>/gpt.log" 2>&1
> ```
>
> Return: "done" if `<NEXT_DIR>/gpt.txt` exists and is non-empty, otherwise the error from the log.

**Do not proceed until the subagent returns.**

Update `ROUND_DIR="$NEXT_DIR"` and return to the loop top (Step A).

### Phase 3 — Synthesis

Use the `$VERDICT` variable already set by the loop. Spawn one `reviewer` subagent with this fully self-contained prompt (substitute literal values for `<QUESTION>`, `<COUNCIL_DIR>`, `<ROUND_DIR>`, `<VERDICT>`):

> Read responses to: `<QUESTION>`
>
> **Round-0 responses** (original independent answers — historical anchor):
>
> - `<COUNCIL_DIR>/round-0/claude.txt` (Claude)
> - `<COUNCIL_DIR>/round-0/gpt.txt` (GPT-5.6-sol)
>
> **Final-round responses** (after debate):
>
> - `<ROUND_DIR>/claude.txt`
> - `<ROUND_DIR>/gpt.txt`
>
> **Debate outcome:** `<VERDICT>` (CONVERGED or CONTINUE-at-cap)
>
> Produce a structured synthesis:
>
> **Did debate improve on round-0?** Compare the final-round responses to the round-0 responses. Did the reasoning get stronger, weaker, or unchanged? Name specific improvements or regressions. If final-round agreement is shallower than round-0 reasoning, say so.
>
> **Which argument is stronger?** Assess Claude's and GPT's final positions by logical quality — soundness of reasoning, specificity of evidence, handling of edge cases. Name the stronger argument and explain why. Do NOT favor a position because both models eventually agreed on it.
>
> **What remains unresolved?** Identify any material disagreement or open question that debate did not settle.
>
> **Recommended position:** The most defensible answer given the debate record. Take a position — do not hedge without cause.
>
> Anti-sycophancy rule: fast consensus is a warning signal. Verify that round-0 responses were not already correct before treating final-round convergence as an improvement.
>
> Write synthesis to `<COUNCIL_DIR>/synthesis.txt`. Return that path and a one-line summary.

### Phase 4 — Final answer (main session)

Read `synthesis.txt`. Deliver your final answer:

- Lead with the recommended position.
- Name where the debate changed the reasoning and why that change is an improvement — or flag if debate degraded the round-0 answer.
- Surface unresolved uncertainty explicitly.
- Do NOT hedge without cause. Take a position.

After delivering the final answer, clean up: `rm -rf "$COUNCIL_DIR"`.

## Default models

| Model | Role |
| ----- | ---- |
| Claude | Main session — forms prior, debates, synthesizes |
| `gpt-5.6-sol` | External challenger via `codex exec` |

## Requirements

- `codex exec` must be on PATH in the subagent execution environment (not the orchestrator session) with a working config pointing at the gateway.

## Anti-sycophancy guards (active throughout)

- Claude's position is formed **before** reading GPT's response in Phase 1.
- In debate rounds, both positions are anonymized as A/B — models evaluate arguments, not identities.
- Convergence checker is instructed to treat fast consensus as a warning signal, not a success signal.
- Convergence checker steelmans both positions and finds material flaws before assessing CONVERGED.
- Debate instructions require evidence-gated concession: concede only on verified factual contradictions.
- Synthesizer anchors on round-0 responses and is instructed to prefer sounder reasoning over final-round agreement.
- If both models agree but their reasoning is weak, say so in the final answer.
