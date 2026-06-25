---
name: council
argument-hint: "<question>"
description: Fan out a question to multiple external LLMs (GPT, DeepSeek, Gemini) in parallel, form an independent Claude position, synthesize with a subagent, then deliver a final answer. Use when a hard technical or factual question warrants multiple perspectives, when the user asks to consult multiple models, or on your own initiative when a question is high-stakes or has non-obvious answers.
---

# Council

Coordinates a multi-model discussion: fans out to GPT/Gemini via `codex exec` and DeepSeek via `bin/llm`, forms an independent Claude position, synthesizes all with a subagent, then delivers a final answer weighted by argument quality — not vote count.

## When to use

- User asks a hard technical or factual question where diverse perspectives reduce error
- User says "council", "ask multiple models", "get multiple opinions", "what do GPT and Gemini think"
- On your own initiative: question is high-stakes, has conflicting priors, or your confidence is low

## When NOT to use

- Simple factual lookups (just answer directly)
- Creative or subjective tasks (debate adds noise, not signal)
- Question already well-resolved in context

## Protocol

### Phase 1 — Independent answers (parallel, round 0)

Create a temp dir under `.claude/tmp/`:

```bash
mkdir -p .claude/tmp
COUNCIL_DIR=$(mktemp -d .claude/tmp/council-XXXXXX)
mkdir -p "$COUNCIL_DIR/round-0"
```

Write the question to a file first (avoids shell injection and handles multiline questions):

```bash
printf '%s' "<question>" > "$COUNCIL_DIR/question.txt"
```

Launch 3 background Bash jobs **simultaneously** — each as its own `run_in_background` Bash tool call:

```bash
# Bash call 1
codex exec -m gpt-5.5 --ephemeral -o "$COUNCIL_DIR/round-0/gpt.txt" < "$COUNCIL_DIR/question.txt" > "$COUNCIL_DIR/round-0/gpt.log" 2>&1
```

```bash
# Bash call 2
bin/llm -m DeepSeek-V4-Flash --thinking --effort high < "$COUNCIL_DIR/question.txt" > "$COUNCIL_DIR/round-0/deepseek.txt" 2>&1
```

```bash
# Bash call 3
codex exec -m gemini-3.5-flash --ephemeral -o "$COUNCIL_DIR/round-0/gemini.txt" < "$COUNCIL_DIR/question.txt" > "$COUNCIL_DIR/round-0/gemini.log" 2>&1
```

Wait for all three to complete before reading any results.

**Simultaneously**, before reading any external response, write your own independent answer to `$COUNCIL_DIR/round-0/claude.txt`. This is your prior — form it before seeing the others to avoid anchoring.

### Phase 2 — Debate loop (up to 3 rounds)

Track the current round directory as `ROUND_DIR="$COUNCIL_DIR/round-0"` and a round counter `N=0`.

Repeat the following steps until the challenger emits CONVERGED or STALEMATE, or until `N` reaches 3:

#### Step A — Spawn challenger subagent

Spawn one `reviewer` subagent with this prompt (fill in COUNCIL_DIR, ROUND_DIR, and the question):

> You are a reasoning auditor, not a debate opponent. Read four independent responses to: `<QUESTION>`
>
> Files in `<ROUND_DIR>`: `claude.txt` (Claude), `gpt.txt` (GPT-5.5), `deepseek.txt` (DeepSeek-V4-Flash), `gemini.txt` (Gemini-3.5-Flash).
>
> For each model in order (GPT, DeepSeek, Gemini, Claude):
>
> 1. **Steelman:** Restate the model's position in its strongest, most logical form.
> 2. **Flaw:** Identify the single weakest load-bearing step. Restrict to: (a) unspoken premises, (b) logical non-sequiturs, (c) boundary or edge cases where the argument breaks. **Materiality filter:** Before writing the flaw, ask "If this objection is correct, would the final answer change?" If no, write `Flaw: none` and omit the Materiality field.
> 3. **Materiality:** Explain why fixing this flaw would change the final answer. Omit if Flaw is none.
>
> Then assess convergence:
>
> - CONVERGED: all four positions agree on the core claim and no material flaw remains unanswered. Emit CONVERGED even at round 0 if all models immediately agree with sound reasoning. **Do not emit CONVERGED because models sound polite or agreeable — fast consensus is a warning signal, not a success signal.**
> - STALEMATE: material disagreements remain but no model changed its position compared to the prior round — the debate is stuck. Do not emit STALEMATE at round 0.
> - CONTINUE: material disagreements remain and at least one model changed position this round.
>
> Write to `<ROUND_DIR>/challenges.txt` using **exactly** this format:
>
> ```text
> === VERDICT ===
> CONVERGED|STALEMATE|CONTINUE
> <one-line reason>
>
> === CHALLENGE: GPT ===
> Steelman: <restate GPT's position at its strongest>
> Flaw type: premise|non-sequitur|boundary
> Flaw: <specific objection>
> Materiality: <why this changes the final answer>
>
> === CHALLENGE: DEEPSEEK ===
> Steelman: ...
> Flaw type: ...
> Flaw: ...
> Materiality: ...
>
> === CHALLENGE: GEMINI ===
> ...
>
> === CHALLENGE: CLAUDE ===
> ...
>
> === END ===
> ```
>
> Return the path to challenges.txt and the verdict line.

Wait for the subagent to complete. Read the immediately following non-blank line after `=== VERDICT ===` to extract CONVERGED, STALEMATE, or CONTINUE.

If verdict is CONVERGED or STALEMATE, exit the loop and proceed to Phase 4.
If `N` equals 3, exit the loop and proceed to Phase 4 regardless of verdict.
Otherwise, proceed to Step B.

#### Step B — Prepare rebuttal context files

Increment the round counter: `N=$((N + 1))`. Create the next round directory:

```bash
mkdir -p "$COUNCIL_DIR/round-$N"
NEXT_DIR="$COUNCIL_DIR/round-$N"
```

Extract each model's challenge section from `$ROUND_DIR/challenges.txt` and write to separate files:

```bash
# Extract GPT challenge
awk '/=== CHALLENGE: GPT ===/,/=== CHALLENGE: DEEPSEEK ===/' "$ROUND_DIR/challenges.txt" | grep -v "===" > "$NEXT_DIR/challenge-gpt.txt"
# Extract DeepSeek challenge
awk '/=== CHALLENGE: DEEPSEEK ===/,/=== CHALLENGE: GEMINI ===/' "$ROUND_DIR/challenges.txt" | grep -v "===" > "$NEXT_DIR/challenge-deepseek.txt"
# Extract Gemini challenge
awk '/=== CHALLENGE: GEMINI ===/,/=== CHALLENGE: CLAUDE ===/' "$ROUND_DIR/challenges.txt" | grep -v "===" > "$NEXT_DIR/challenge-gemini.txt"
# Extract Claude challenge (=== END === is the sentinel appended by the challenger)
awk '/=== CHALLENGE: CLAUDE ===/,/=== END ===/' "$ROUND_DIR/challenges.txt" | grep -v "===" > "$NEXT_DIR/challenge-claude.txt"
```

Build an anonymized peer-responses file (model labels replaced with Response A/B/C/D so models evaluate arguments on logic, not identity):

```bash
{
  printf "Response A:\n"; cat "$ROUND_DIR/gpt.txt"
  printf "\nResponse B:\n"; cat "$ROUND_DIR/deepseek.txt"
  printf "\nResponse C:\n"; cat "$ROUND_DIR/gemini.txt"
  printf "\nResponse D:\n"; cat "$ROUND_DIR/claude.txt"
} > "$NEXT_DIR/peer-responses.txt"
```

Build each model's prompt by concatenating parts in order. All four prompts must be written before launching any rebuttal call.

```bash
# GPT rebuttal prompt
{
  printf 'Original question:\n'; cat "$COUNCIL_DIR/question.txt"
  printf '\nAll responses from the previous round (anonymized — evaluate arguments on logic, not identity):\n'
  cat "$NEXT_DIR/peer-responses.txt"
  printf '\nYour previous response:\n'; cat "$ROUND_DIR/gpt.txt"
  printf '\nChallenge to your position:\n'; cat "$NEXT_DIR/challenge-gpt.txt"
  printf '\nInstructions:\n- Defend what holds up. Concede what does not.\n- Do not begin with agreement or praise.\n- If you are conceding a point, state specifically which fact or logical step caused the concession.\n- Concede only when the counterargument introduces a verified factual contradiction — not merely an interpretive difference or alternative framing.\n- If you are maintaining your position, explain why the challenge does not change the conclusion.\n- Be specific about what changed and why.\n'
} > "$NEXT_DIR/prompt-gpt.txt"

# DeepSeek rebuttal prompt
{
  printf 'Original question:\n'; cat "$COUNCIL_DIR/question.txt"
  printf '\nAll responses from the previous round (anonymized — evaluate arguments on logic, not identity):\n'
  cat "$NEXT_DIR/peer-responses.txt"
  printf '\nYour previous response:\n'; cat "$ROUND_DIR/deepseek.txt"
  printf '\nChallenge to your position:\n'; cat "$NEXT_DIR/challenge-deepseek.txt"
  printf '\nInstructions:\n- Defend what holds up. Concede what does not.\n- Do not begin with agreement or praise.\n- If you are conceding a point, state specifically which fact or logical step caused the concession.\n- Concede only when the counterargument introduces a verified factual contradiction — not merely an interpretive difference or alternative framing.\n- If you are maintaining your position, explain why the challenge does not change the conclusion.\n- Be specific about what changed and why.\n'
} > "$NEXT_DIR/prompt-deepseek.txt"

# Gemini rebuttal prompt
{
  printf 'Original question:\n'; cat "$COUNCIL_DIR/question.txt"
  printf '\nAll responses from the previous round (anonymized — evaluate arguments on logic, not identity):\n'
  cat "$NEXT_DIR/peer-responses.txt"
  printf '\nYour previous response:\n'; cat "$ROUND_DIR/gemini.txt"
  printf '\nChallenge to your position:\n'; cat "$NEXT_DIR/challenge-gemini.txt"
  printf '\nInstructions:\n- Defend what holds up. Concede what does not.\n- Do not begin with agreement or praise.\n- If you are conceding a point, state specifically which fact or logical step caused the concession.\n- Concede only when the counterargument introduces a verified factual contradiction — not merely an interpretive difference or alternative framing.\n- If you are maintaining your position, explain why the challenge does not change the conclusion.\n- Be specific about what changed and why.\n'
} > "$NEXT_DIR/prompt-gemini.txt"

# Claude rebuttal prompt
{
  printf 'Original question:\n'; cat "$COUNCIL_DIR/question.txt"
  printf '\nAll responses from the previous round (anonymized — evaluate arguments on logic, not identity):\n'
  cat "$NEXT_DIR/peer-responses.txt"
  printf '\nYour previous response:\n'; cat "$ROUND_DIR/claude.txt"
  printf '\nChallenge to your position:\n'; cat "$NEXT_DIR/challenge-claude.txt"
  printf '\nInstructions:\n- Defend what holds up. Concede what does not.\n- Do not begin with agreement or praise.\n- If you are conceding a point, state specifically which fact or logical step caused the concession.\n- Concede only when the counterargument introduces a verified factual contradiction — not merely an interpretive difference or alternative framing.\n- If you are maintaining your position, explain why the challenge does not change the conclusion.\n- Be specific about what changed and why.\n'
} > "$NEXT_DIR/prompt-claude.txt"
```

Launch 3 background rebuttal calls **simultaneously**:

```bash
# Bash call 1 — GPT rebuttal
codex exec -m gpt-5.5 --ephemeral -o "$NEXT_DIR/gpt.txt" < "$NEXT_DIR/prompt-gpt.txt" > "$NEXT_DIR/gpt.log" 2>&1
```

```bash
# Bash call 2 — DeepSeek rebuttal
bin/llm -m DeepSeek-V4-Flash --thinking --effort high < "$NEXT_DIR/prompt-deepseek.txt" > "$NEXT_DIR/deepseek.txt" 2>&1
```

```bash
# Bash call 3 — Gemini rebuttal
codex exec -m gemini-3.5-flash --ephemeral -o "$NEXT_DIR/gemini.txt" < "$NEXT_DIR/prompt-gemini.txt" > "$NEXT_DIR/gemini.log" 2>&1
```

Wait for all three to complete. Then write Claude's rebuttal inline (main session): read the full contents of `"$NEXT_DIR/prompt-claude.txt"`, compose your rebuttal following its instructions, and write the rebuttal text (not the prompt) to `"$NEXT_DIR/claude.txt"`.

Update `ROUND_DIR="$NEXT_DIR"` and return to the loop top (Step A challenger).

### Phase 3 — Synthesis

Spawn one `reviewer` subagent with this prompt (fill in the actual question and COUNCIL_DIR path):

> Read four independent responses to: `QUESTION`
>
> Files in <COUNCIL_DIR>: claude.txt (Claude), gpt.txt (GPT-5.5), deepseek.txt (DeepSeek-V4-Flash), gemini.txt (Gemini-3.5-Flash).
>
> Produce a structured synthesis:
>
> **Agreements** — claims all or most models share.
> **Conflicts** — where models disagree; state each position and its reasoning.
> **Unique insights** — points raised by only one model, worth preserving.
> **Logical strength** — which positions have the soundest reasoning (not the most popular).
> **Recommended position** — the most defensible answer by argument quality.
>
> Anti-sycophancy rule: do NOT favor a position because more models hold it. A minority view with strong logic beats a majority with weak logic. Weight by reasoning quality, not vote count.
>
> Write synthesis to <COUNCIL_DIR>/synthesis.txt. Return that path and a one-line summary.

### Phase 4 — Final answer (main session)

Read `synthesis.txt`. Deliver your final answer:

- Lead with the recommended position.
- State where models disagreed and how you resolve it — name the reasoning, not just the conclusion.
- Surface unresolved uncertainty explicitly.
- Do NOT average the models or hedge without cause. Take a position.

After delivering the final answer, clean up: `rm -rf "$COUNCIL_DIR"`.

## Default models

| Model | Strength |
| ----- | -------- |
| `gpt-5.5` | General frontier reasoning |
| `DeepSeek-V4-Flash` | Math, code, open-source perspective |
| `gemini-3.5-flash` | Broad knowledge, 1M context, strong factual recall |

User can request different models: "council with o3 and Llama". GPT and Gemini variants use `codex exec`; DeepSeek uses `bin/llm` (not routed through the Codex gateway).

## Requirements

- GPT/Gemini legs: `codex exec` must be on PATH with a working config pointing at the gateway.
- DeepSeek leg: `ANTHROPIC_BASE_URL`, `LLM_GATEWAY_KEY`, `LLM_GATEWAY_KEY_HEADER` must be set.

## Anti-sycophancy guards (active throughout)

- Claude's own position is formed **before** reading external responses.
- Synthesizer is instructed explicitly to weight by logic, not majority.
- If all external models agree but their reasoning is weak, say so in the final answer.
- If one model has a minority view with strong reasoning, surface it — do not bury it.
