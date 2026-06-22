"""Call an external LLM via the Anthropic SDK.

Usage: llm [options] [message]
       echo "message" | llm [options]

Environment:
  ANTHROPIC_BASE_URL       Gateway URL (SDK reads this automatically)
  LLM_GATEWAY_KEY          API key
  LLM_GATEWAY_KEY_HEADER   Header name for the subscription key (value is LLM_GATEWAY_KEY)

--thinking enables reasoning before the final response; intermediate thought is
never shown — only the final text output is printed.

Effort mapping per model family:
  Claude 4.6 (manual):    budget_tokens  low=1024 medium=4096 high=16000 xhigh=32768
                           (clamped to max(1024, max_tokens-1024) if too large)
  Claude 4.7+ (adaptive): output_config via extra_body, effort low/medium/high/xhigh
  o-series:               reasoning_effort  low/medium/high  (xhigh→high)
  gpt-5.*:                reasoning_effort  low/medium/high/xhigh
  DeepSeek:               reasoning_effort  low/medium/high→high, xhigh→max
  Gemini:                 thinkingBudget    low=512 medium=4096 high=16384 xhigh=32768
"""

import os
import re
import sys
import argparse
import anthropic

# ponytail: gateway proxies non-Anthropic model names over the Anthropic wire protocol
DEFAULT_MODEL = "gpt-5.5"
DEFAULT_MAX_TOKENS = 32768

CLAUDE_MANUAL_BUDGETS = {"low": 1024, "medium": 4096, "high": 16000, "xhigh": 32768}
GEMINI_BUDGETS = {"low": 512, "medium": 4096, "high": 16384, "xhigh": 32768}
THINKING_BETA = "interleaved-thinking-2025-05-14"


def require_env(k: str) -> str:
    v = os.environ.get(k)
    if not v:
        print(f"{k} not set", file=sys.stderr)
        sys.exit(1)
    return v


def _model_family(model: str) -> str:
    m = model.lower()
    if m.startswith("claude"):
        version = re.search(r"(\d+)\.(\d+)", m)
        if version:
            major, minor = int(version.group(1)), int(version.group(2))
            if major >= 5 or (major == 4 and minor >= 7):
                return "claude-adaptive"
        return "claude-manual"
    if re.match(r"o\d[\s\-_.]|o\d$", m):
        return "o-series"
    if re.match(r"gpt-5(\.|$|-)", m):
        return "gpt5"
    if m.startswith("deepseek"):
        return "deepseek"
    if m.startswith("gemini"):
        return "gemini"
    return "other"


def main():
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter
    )
    parser.add_argument(
        "--model", "-m", default=DEFAULT_MODEL, help="Model name (default: gpt-5.5)"
    )
    parser.add_argument("--system", "-s", default=None, help="System prompt")
    parser.add_argument(
        "--max-tokens",
        "-t",
        type=int,
        default=DEFAULT_MAX_TOKENS,
        help="Max output tokens",
    )
    parser.add_argument(
        "--temperature", type=float, default=None, help="Sampling temperature"
    )
    parser.add_argument(
        "--thinking",
        action="store_true",
        help="Enable reasoning before final response (output hidden)",
    )
    # ponytail: --effort without --thinking is a no-op; warn rather than error to keep scripts composable
    parser.add_argument(
        "--effort",
        choices=["low", "medium", "high", "xhigh"],
        default="high",
        help="Reasoning effort level when --thinking is set (default: high)",
    )
    parser.add_argument(
        "--stream", action="store_true", help="Stream output as it arrives"
    )
    parser.add_argument("message", nargs="*", help="Message (or pipe via stdin)")
    args = parser.parse_args()

    if args.effort != "high" and not args.thinking:
        print("warning: --effort has no effect without --thinking", file=sys.stderr)

    if args.message:
        message = " ".join(args.message)
    elif not sys.stdin.isatty():
        message = sys.stdin.read().strip()
        if not message:
            print("empty input", file=sys.stderr)
            sys.exit(1)
    else:
        parser.print_help()
        sys.exit(1)

    url = require_env("ANTHROPIC_BASE_URL")
    key = require_env("LLM_GATEWAY_KEY")
    key_header = require_env("LLM_GATEWAY_KEY_HEADER")

    client = anthropic.Anthropic(
        base_url=url,
        api_key=key,
        timeout=None,
        default_headers={key_header: key},
    )

    kwargs: dict[str, object] = dict(
        model=args.model,
        max_tokens=args.max_tokens,
        messages=[{"role": "user", "content": message}],
        **({"system": args.system} if args.system else {}),
        **(
            {"temperature": args.temperature}
            if args.temperature is not None and not args.thinking
            else {}
        ),
    )

    use_beta = False

    if args.thinking:
        family = _model_family(args.model)
        effort = args.effort

        if family == "claude-manual":
            if args.max_tokens < 2048:
                print(
                    f"--max-tokens {args.max_tokens} too small for thinking (need >= 2048)",
                    file=sys.stderr,
                )
                sys.exit(1)
            budget = min(CLAUDE_MANUAL_BUDGETS[effort], args.max_tokens - 1024)
            kwargs["thinking"] = {"type": "enabled", "budget_tokens": budget}
            use_beta = True
        elif family == "claude-adaptive":
            # Adaptive thinking is gateway-specific; pass via extra_body.
            kwargs["extra_body"] = {"output_config": {"effort": effort}}
        elif family == "o-series":
            kwargs["extra_body"] = {
                "reasoning_effort": "high" if effort == "xhigh" else effort
            }
        elif family == "gpt5":
            kwargs["extra_body"] = {"reasoning_effort": effort}
        elif family == "deepseek":
            if effort in ("low", "medium"):
                print(
                    f"DeepSeek: effort '{effort}' unsupported, using 'high'",
                    file=sys.stderr,
                )
            ds_effort = "max" if effort == "xhigh" else "high"
            kwargs["extra_body"] = {"reasoning_effort": ds_effort}
        elif family == "gemini":
            kwargs["extra_body"] = {
                "thinkingConfig": {"thinkingBudget": GEMINI_BUDGETS[effort]}
            }
        else:
            kwargs["extra_body"] = {
                "reasoning_effort": "high" if effort == "xhigh" else effort
            }

    beta_kw = {"betas": [THINKING_BETA]} if use_beta else {}

    try:
        if args.stream:
            ctx = (
                client.beta.messages.stream(**kwargs, **beta_kw)
                if use_beta
                else client.messages.stream(**kwargs)
            )
            wrote = False
            with ctx as stream:
                for text in stream.text_stream:
                    print(text, end="", flush=True)
                    wrote = True
            print()
            if not wrote:
                print("no text in response", file=sys.stderr)
                sys.exit(1)
        else:
            response = (
                client.beta.messages.create(**kwargs, **beta_kw)
                if use_beta
                else client.messages.create(**kwargs)
            )
            blocks = [b for b in response.content if hasattr(b, "text")]
            if not blocks:
                print("no text in response", file=sys.stderr)
                sys.exit(1)
            print(blocks[0].text)
    except anthropic.AuthenticationError:
        print("Authentication failed — check LLM_GATEWAY_KEY", file=sys.stderr)
        sys.exit(1)
    except anthropic.RateLimitError:
        print("Rate limit hit — retry later", file=sys.stderr)
        sys.exit(1)
    except anthropic.BadRequestError as e:
        print(f"Bad request: {e}", file=sys.stderr)
        sys.exit(1)
    except anthropic.APIConnectionError as e:
        print(f"Connection error: {e}", file=sys.stderr)
        sys.exit(1)
    except anthropic.APIStatusError as e:
        print(f"API error {e.status_code}: {e.message}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
