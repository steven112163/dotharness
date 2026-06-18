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
- `--temperature F` — sampling temperature
- `--stream` — stream output progressively

## Available models

| Model | Context |
|-------|---------|
| `gpt-5.5` | 1M |
| `gpt-4o` | 128k |
| `o3` | 200k |
| `gemini-2.5-pro` | 1M |
| `gemini-3-pro-preview` | 2M |
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
