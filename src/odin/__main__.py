"""Command-line entrypoint for running the Odin agent."""

import argparse
import os
import sys

from dotenv import load_dotenv

from odin import Agent, AgentConfig, create_client


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
        "--model",
        default="google/gemini-2.0-flash-001",
        help="OpenRouter model identifier.",
    )
    parser.add_argument(
        "--max-steps",
        type=int,
        default=30,
        help="Maximum number of agent steps.",
    )
    parser.add_argument(
        "--no-grid",
        action="store_true",
        help="Disable grid overlay on screenshots.",
    )
    parser.add_argument(
        "--grid-step",
        type=int,
        default=100,
        help="Grid cell size in pixels.",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    """Run the Odin CLI."""
    load_dotenv()
    parser = _build_parser()
    args = parser.parse_args(argv)

    if not args.task:
        parser.print_help()
        print('\nExample: python -m odin "Open Safari and search for weather"')
        return 0

    if not os.environ.get("OPENROUTER_API_KEY"):
        print("OPENROUTER_API_KEY is not set.")
        print("Set it in the environment or in a local .env file.")
        return 1

    llm = create_client(model=args.model)
    config = AgentConfig(
        max_steps=args.max_steps,
        use_grid=not args.no_grid,
        grid_step=args.grid_step,
    )
    agent = Agent(llm, config=config)

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
    return 0 if result.success else 1


if __name__ == "__main__":
    sys.exit(main())
