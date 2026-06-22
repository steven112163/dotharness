---
name: llm
argument-hint: "[-m MODEL] [-s SYSTEM] [-t N] [--temperature F] [--stream] <message>"
description: Query an external LLM to get a second opinion, cross-check a claim, debate a design, or consult a different model. Use when the user asks to consult another model, or on your own initiative when a second perspective would strengthen your answer. Default model is gpt-5.5 (1M context).
---

# LLM

Calls `bin/llm` to query an external LLM gateway.

## When to use

- User asks to consult another model ("what does GPT think", "get a second opinion", "ask Gemini")
- User wants to compare or debate responses across models
- On your own initiative: cross-check a non-obvious claim, validate a design decision, or get a second perspective before committing to a recommendation

## How to call

```bash
bin/llm [options] "message"
echo "message" | bin/llm [options]
```

Options:
- `-m MODEL` — model name (default: `gpt-5.5`)
- `-s "SYSTEM"` — system prompt
- `-t N` — max output tokens (default: 32768)
- `--temperature F` — sampling temperature (suppressed when `--thinking` is set)
- `--thinking` — enable reasoning before final response; intermediate thought is hidden
- `--effort low|medium|high|xhigh` — reasoning effort when `--thinking` is set (default: `high`)
- `--stream` — stream output progressively

**Reasoning effort per model family:**

| Family | Parameter | Notes |
| ------ | --------- | ----- |
| `Claude-*-4.6` and older | `budget_tokens` | low=1024 medium=4096 high=16000 xhigh=32768; clamped if near `--max-tokens` |
| `Claude-*-4.7+` | `output_config.effort` | adaptive mode via gateway |
| `o1/o3/o4-*` | `reasoning_effort` | always on; xhigh→high |
| `gpt-5.*` | `reasoning_effort` | opt-in reasoning; all levels supported |
| `DeepSeek-*` | `reasoning_effort` | low/medium/high→high, xhigh→max |
| `gemini-*` | `thinkingBudget` | low=512 medium=4096 high=16384 xhigh=32768 |

## Available models

| Model | Context |
|-------|---------|
| `gpt-5.5` | 1M |
| `gpt-4o` | 128k |
| `o3` | 200k |
| `gemini-3.5-flash` | 1M |
| `DeepSeek-V4-Flash` | 1M |
| `Llama-4-Scout-17B` | 10M |

## Requirements

- `ANTHROPIC_BASE_URL` — gateway URL (SDK reads this automatically)
- `LLM_GATEWAY_KEY` — API key (required)
- `LLM_GATEWAY_KEY_HEADER` — header name for subscription auth (value sent is `LLM_GATEWAY_KEY`)

## Examples

```bash
# Default model
bin/llm "Explain softmax numerically."

# With system prompt
bin/llm -m gpt-4o -s "You are a GPU performance expert." "Is GEMM compute- or memory-bound at batch=1?"

# Stream a long response
bin/llm --stream "Write a detailed explanation of attention mechanisms."

# Pipe context
cat some_file.py | bin/llm "Review this for correctness."
```
