#!/usr/bin/env python
"""
Real-time agent execution example.

Run with:
    uv run python examples/run_agent.py "Open Safari and search for weather"

Requirements:
    1. Create .env file with OPENROUTER_API_KEY=your-key
    2. Grant Screen Recording permission (System Settings → Privacy → Screen Recording)
    3. Grant Accessibility permission (System Settings → Privacy → Accessibility)
"""

import argparse
import os
import sys
from datetime import datetime

from dotenv import load_dotenv

# Load .env file
load_dotenv()

from odin import Agent, AgentConfig, create_client
from odin.agent.parser import ParsedAction


def on_step(step: int, action: ParsedAction) -> None:
    """Callback for each step - prints progress."""
    timestamp = datetime.now().strftime("%H:%M:%S")
    print(f"\n[{timestamp}] Step {step}")
    print(
        f"  Thought: {action.thought[:100]}..."
        if len(action.thought) > 100
        else f"  Thought: {action.thought}"
    )
    print(f"  Action: {action.action}")
    print(f"  Params: {action.params}")


def main():
    parser = argparse.ArgumentParser(
        description="Run the Odin AI agent to automate computer tasks",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    %(prog)s "Open Safari and search for weather"
    %(prog)s "Open Notes app and create a new note" --max-steps 20
    %(prog)s "Click on the Finder icon in the dock" --no-grid
        """,
    )
    parser.add_argument(
        "task",
        help="Natural language description of the task to accomplish",
    )
    parser.add_argument(
        "--model",
        default="google/gemini-2.0-flash-001",
        help="OpenRouter model to use (default: google/gemini-2.0-flash-001)",
    )
    parser.add_argument(
        "--max-steps",
        type=int,
        default=30,
        help="Maximum steps before stopping (default: 30)",
    )
    parser.add_argument(
        "--no-grid",
        action="store_true",
        help="Disable grid overlay on screenshots",
    )
    parser.add_argument(
        "--grid-step",
        type=int,
        default=100,
        help="Grid cell size in pixels (default: 100)",
    )
    parser.add_argument(
        "--save-screenshots",
        action="store_true",
        help="Save screenshots to ./screenshots/ directory",
    )

    args = parser.parse_args()

    # Check for API key
    if not os.environ.get("OPENROUTER_API_KEY"):
        print("ERROR: OPENROUTER_API_KEY environment variable not set")
        print("\nTo set it, run:")
        print('  export OPENROUTER_API_KEY="your-api-key-here"')
        print("\nGet an API key from: https://openrouter.ai/")
        sys.exit(1)

    # Create screenshots directory if saving
    if args.save_screenshots:
        os.makedirs("screenshots", exist_ok=True)

    print("=" * 60)
    print("🔱 Odin Agent")
    print("=" * 60)
    print(f"Task: {args.task}")
    print(f"Model: {args.model}")
    print(f"Max steps: {args.max_steps}")
    print(f"Grid overlay: {'No' if args.no_grid else f'Yes ({args.grid_step}px)'}")
    print("=" * 60)
    print("\n⚠️  Move mouse to screen corner to abort (failsafe)")
    print("Starting in 3 seconds...\n")

    import time

    time.sleep(3)

    # Create client and agent
    llm = create_client(model=args.model)
    config = AgentConfig(
        max_steps=args.max_steps,
        use_grid=not args.no_grid,
        grid_step=args.grid_step,
    )

    agent = Agent(llm, config=config, on_step=on_step)

    # Run the agent
    try:
        result = agent.run(args.task)
    except KeyboardInterrupt:
        print("\n\n⚠️  Interrupted by user")
        result = None
    except Exception as e:
        print(f"\n\n❌ Error: {e}")
        result = None
    finally:
        llm.close()

    # Print results
    print("\n" + "=" * 60)
    if result:
        status = "✅ SUCCESS" if result.success else "❌ FAILED"
        print(f"Result: {status}")
        print(f"Message: {result.message}")
        print(f"Total steps: {result.total_steps}")
        print(f"Actions executed: {result.actions_executed}")
        print(f"Duration: {result.duration_seconds:.1f}s")

        # Save final screenshot
        if args.save_screenshots and result.final_screenshot:
            path = f"screenshots/final_{datetime.now().strftime('%Y%m%d_%H%M%S')}.png"
            result.final_screenshot.save(path)
            print(f"Final screenshot saved: {path}")
    else:
        print("Agent did not complete")
    print("=" * 60)


if __name__ == "__main__":
    main()
