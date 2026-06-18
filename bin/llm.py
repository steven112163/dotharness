"""Call an external LLM via the Anthropic SDK.

Usage: llm [options] [message]
       echo "message" | llm [options]

Environment:
  ANTHROPIC_BASE_URL       Gateway URL (SDK reads this automatically)
  LLM_GATEWAY_KEY          API key
  LLM_GATEWAY_KEY_HEADER   Header name for the subscription key (value is LLM_GATEWAY_KEY)
"""

import os
import sys
import argparse
import anthropic

# ponytail: gateway proxies non-Anthropic model names over the Anthropic wire protocol
DEFAULT_MODEL = "gpt-5.5"
DEFAULT_MAX_TOKENS = 32768


def require_env(k: str) -> str:
    v = os.environ.get(k)
    if not v:
        print(f"{k} not set", file=sys.stderr)
        sys.exit(1)
    return v


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
        "--stream", action="store_true", help="Stream output as it arrives"
    )
    parser.add_argument("message", nargs="*", help="Message (or pipe via stdin)")
    args = parser.parse_args()

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
        **({"temperature": args.temperature} if args.temperature is not None else {}),
    )

    try:
        if args.stream:
            with client.messages.stream(**kwargs) as stream:
                for text in stream.text_stream:
                    print(text, end="", flush=True)
            print()
        else:
            response = client.messages.create(**kwargs)
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
