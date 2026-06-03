"""Command-line entrypoint for running the Odin agent."""

import argparse
import os
import sys

from dotenv import load_dotenv

from odin import Agent, AgentConfig, create_client
from odin.action.safety import SafetyConfig
from odin.llm.prompts import build_system_prompt


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run the Odin vision automation agent.",
    )
    parser.add_argument(
        "task",
        nargs="?",
        help="Natural-language task to execute.",
    )
    parser.add_argument(
        "--provider",
        choices=["openrouter", "bedrock"],
        default=os.environ.get("ODIN_LLM_PROVIDER", "openrouter"),
        help="LLM provider to use.",
    )
    parser.add_argument(
        "--model",
        default=None,
        help="Provider-specific model identifier.",
    )
    parser.add_argument(
        "--max-steps",
        type=int,
        default=AgentConfig().max_steps,
        help="Maximum number of agent steps.",
    )
    parser.add_argument(
        "--show-system-prompt",
        action="store_true",
        help="Print the exact system prompt and exit.",
    )
    parser.add_argument(
        "--max-batch-actions",
        type=int,
        default=AgentConfig().max_batch_actions,
        help="Maximum actions accepted per LLM response.",
    )
    parser.add_argument(
        "--trace-path",
        default=None,
        help="Write structured JSONL trace events to this path.",
    )
    parser.add_argument(
        "--trace-screenshots",
        action="store_true",
        help="Save screenshot PNG artifacts alongside the trace file.",
    )
    parser.add_argument(
        "--require-action-approval",
        action="store_true",
        help="Prompt before executing every non-done action.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """Run the Odin CLI."""
    load_dotenv()
    parser = _build_parser()
    args = parser.parse_args(argv)

    if args.show_system_prompt:
        print(
            build_system_prompt(
                max_batch_actions=max(1, args.max_batch_actions),
            )
        )
        return 0

    if not args.task:
        parser.print_help()
        print('\nExample: python -m odin "Open Safari and search for weather"')
        return 0

    if args.provider == "openrouter" and not os.environ.get("OPENROUTER_API_KEY"):
        print("OPENROUTER_API_KEY is not set.")
        print("Set it in the environment or in a local .env file.")
        return 1

    try:
        llm = create_client(provider=args.provider, model=args.model)
    except (ImportError, ValueError) as e:
        print(e)
        return 1

    config = AgentConfig(
        max_steps=args.max_steps,
        trace_path=args.trace_path,
        trace_screenshots=args.trace_screenshots,
        max_batch_actions=max(1, args.max_batch_actions),
        safety=SafetyConfig(require_confirmation=args.require_action_approval),
    )
    agent = Agent(
        llm,
        config=config,
        action_approval_callback=_terminal_action_approval
        if args.require_action_approval
        else None,
    )

    try:
        result = agent.run(args.task)
    except KeyboardInterrupt:
        print("Interrupted by user.")
        return 130
    finally:
        llm.close()

    print(f"Success: {result.success}")
    print(f"Message: {result.message}")
    print(f"Total steps: {result.total_steps}")
    print(f"Actions executed: {result.actions_executed}")
    print(f"Duration: {result.duration_seconds:.2f}s")
    if result.llm_usage:
        print(f"LLM requests: {result.llm_usage.get('requests', 0)}")
        print(f"Input tokens: {result.llm_usage.get('input_tokens', 0)}")
        print(f"Output tokens: {result.llm_usage.get('output_tokens', 0)}")
        print(f"Total tokens: {result.llm_usage.get('total_tokens', 0)}")
    if result.trace_path:
        print(f"Trace: {result.trace_path}")
    return 0 if result.success else 1


def _terminal_action_approval(request: dict) -> bool:
    """Ask CLI users before executing an action."""
    print("\nApproval required before executing action:")
    print(f"Thought: {request.get('thought') or '-'}")
    print(f"Action: {request.get('action')}")
    print(f"Params: {request.get('params')}")
    answer = input("Execute this action? [y/N] ").strip().lower()
    return answer in {"y", "yes"}


if __name__ == "__main__":
    sys.exit(main())
