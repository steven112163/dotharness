---
name: council
argument-hint: "<question>"
description: Fan out a question to multiple external LLMs (GPT, DeepSeek, Gemini) in parallel, form an independent Claude position, synthesize with a subagent, then deliver a final answer. Use when a hard technical or factual question warrants multiple perspectives, when the user asks to consult multiple models, or on your own initiative when a question is high-stakes or has non-obvious answers.
---

# Council

Coordinates a multi-model discussion: fans out to external LLMs via `bin/llm`, forms an independent Claude position, synthesizes all with a subagent, then delivers a final answer weighted by argument quality — not vote count.

## When to use

- User asks a hard technical or factual question where diverse perspectives reduce error
- User says "council", "ask multiple models", "get multiple opinions", "what do GPT and Gemini think"
- On your own initiative: question is high-stakes, has conflicting priors, or your confidence is low

## When NOT to use

- Simple factual lookups (just answer directly)
- Creative or subjective tasks (debate adds noise, not signal)
- Question already well-resolved in context

## Protocol

### Phase 1 — Independent answers (parallel)

Create a temp dir under `.claude/tmp/`:

```bash
mkdir -p .claude/tmp
COUNCIL_DIR=$(mktemp -d .claude/tmp/council-XXXXXX)
```

Write the question to a file first (avoids shell injection and handles multiline questions):

```bash
printf '%s' "<question>" > "$COUNCIL_DIR/question.txt"
```

Launch 3 background Bash jobs **simultaneously** — each as its own `run_in_background` Bash tool call:

```bash
# Bash call 1
bin/llm -m gpt-5.5 --thinking --effort high < "$COUNCIL_DIR/question.txt" > "$COUNCIL_DIR/gpt.txt" 2>&1
```
```bash
# Bash call 2
bin/llm -m DeepSeek-V4-Flash --thinking --effort high < "$COUNCIL_DIR/question.txt" > "$COUNCIL_DIR/deepseek.txt" 2>&1
```
```bash
# Bash call 3
bin/llm -m gemini-3.5-flash --thinking --effort high < "$COUNCIL_DIR/question.txt" > "$COUNCIL_DIR/gemini.txt" 2>&1
```

Wait for all three to complete before reading any results.

**Simultaneously**, before reading any external response, write your own independent answer to `$COUNCIL_DIR/claude.txt`. This is your prior — form it before seeing the others to avoid anchoring.

### Phase 2 — Synthesis

Spawn one `reviewer` subagent with this prompt (fill in the actual question and COUNCIL_DIR path):

> Read four independent responses to: "<question>"
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

### Phase 3 — Final answer (main session)

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

User can request different models: "council with o3 and Llama". Use `bin/llm --help` for available models.

## Requirements

Same as `bin/llm`: `ANTHROPIC_BASE_URL`, `LLM_GATEWAY_KEY`, `LLM_GATEWAY_KEY_HEADER` must be set.

## Anti-sycophancy guards (active throughout)

- Claude's own position is formed **before** reading external responses.
- Synthesizer is instructed explicitly to weight by logic, not majority.
- If all external models agree but their reasoning is weak, say so in the final answer.
- If one model has a minority view with strong reasoning, surface it — do not bury it.
