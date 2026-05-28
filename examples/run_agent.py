#!/usr/bin/env python
"""
Real-time agent execution example.

Run with:
    uv run python examples/run_agent.py "Open Safari and search for weather"

Requirements:
    1. Install a provider extra: odin[openrouter] or odin[bedrock]
    2. Create .env file with OPENROUTER_API_KEY=your-key, or configure AWS
       credentials for --provider bedrock
    3. Grant Screen Recording permission (System Settings → Privacy → Screen Recording)
    4. Grant Accessibility permission (System Settings → Privacy → Accessibility)
"""

import argparse
import os
import sys
from datetime import datetime

from dotenv import load_dotenv
from odin import Agent, AgentConfig, create_client
from odin.agent.parser import ParsedAction
from odin.llm.prompts import build_system_prompt


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
    load_dotenv()

    parser = argparse.ArgumentParser(
        description="Run the Odin AI agent to automate computer tasks",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
    %(prog)s "Open Safari and search for weather"
    %(prog)s "Open Notes app and create a new note" --max-steps 20
        """,
    )
    parser.add_argument(
        "task",
        help="Natural language description of the task to accomplish",
    )
    parser.add_argument(
        "--provider",
        choices=["openrouter", "bedrock"],
        default=os.environ.get("ODIN_LLM_PROVIDER", "openrouter"),
        help="LLM provider to use (default: openrouter)",
    )
    parser.add_argument(
        "--model",
        default=None,
        help="Provider-specific model to use",
    )
    parser.add_argument(
        "--max-steps",
        type=int,
        default=AgentConfig().max_steps,
        help=f"Maximum steps before stopping (default: {AgentConfig().max_steps})",
    )
    parser.add_argument(
        "--show-system-prompt",
        action="store_true",
        help="Print the exact system prompt and exit",
    )
    parser.add_argument(
        "--max-batch-actions",
        type=int,
        default=AgentConfig().max_batch_actions,
        help=(
            "Maximum actions accepted per LLM response "
            f"(default: {AgentConfig().max_batch_actions})"
        ),
    )
    parser.add_argument(
        "--save-screenshots",
        action="store_true",
        help="Save screenshots to ./screenshots/ directory",
    )
    parser.add_argument(
        "--trace-path",
        default=None,
        help="Write structured JSONL trace events to this path",
    )
    parser.add_argument(
        "--trace-screenshots",
        action="store_true",
        help="Save screenshot PNG artifacts alongside the trace file",
    )

    args = parser.parse_args()

    if args.show_system_prompt:
        print(
            build_system_prompt(
                max_batch_actions=max(1, args.max_batch_actions),
            )
        )
        return

    if args.provider == "openrouter" and not os.environ.get("OPENROUTER_API_KEY"):
        print("ERROR: OPENROUTER_API_KEY environment variable not set")
        print("\nTo set it, run:")
        print('  export OPENROUTER_API_KEY="your-api-key-here"')
        print("\nGet an API key from: https://openrouter.ai/")
        sys.exit(1)

    if args.save_screenshots:
        os.makedirs("screenshots", exist_ok=True)

    print("=" * 60)
    print("🔱 Odin Agent")
    print("=" * 60)
    print(f"Task: {args.task}")
    print(f"Provider: {args.provider}")
    print(f"Model: {args.model or 'default'}")
    print(f"Max steps: {args.max_steps}")
    print(f"Max batch actions: {args.max_batch_actions}")
    print("=" * 60)
    print("\n⚠️  Move mouse to screen corner to abort (failsafe)")
    print("Starting in 3 seconds...\n")

    import time

    time.sleep(3)

    try:
        llm = create_client(provider=args.provider, model=args.model)
    except (ImportError, ValueError) as e:
        print(f"\n\n❌ Error: {e}")
        sys.exit(1)

    config = AgentConfig(
        max_steps=args.max_steps,
        trace_path=args.trace_path,
        trace_screenshots=args.trace_screenshots,
        max_batch_actions=max(1, args.max_batch_actions),
    )

    agent = Agent(llm, config=config, on_step=on_step)

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

    print("\n" + "=" * 60)
    if result:
        status = "✅ SUCCESS" if result.success else "❌ FAILED"
        print(f"Result: {status}")
        print(f"Message: {result.message}")
        print(f"Total steps: {result.total_steps}")
        print(f"Actions executed: {result.actions_executed}")
        print(f"Duration: {result.duration_seconds:.1f}s")
        if result.llm_usage:
            print(f"LLM requests: {result.llm_usage.get('requests', 0)}")
            print(f"Input tokens: {result.llm_usage.get('input_tokens', 0)}")
            print(f"Output tokens: {result.llm_usage.get('output_tokens', 0)}")
            print(f"Total tokens: {result.llm_usage.get('total_tokens', 0)}")
            estimated_cost = result.llm_usage.get("estimated_cost_usd")
            if estimated_cost is not None:
                print(f"Estimated LLM cost: ${estimated_cost:.6f}")
        if result.trace_path:
            print(f"Trace: {result.trace_path}")

        if args.save_screenshots and result.final_screenshot:
            path = f"screenshots/final_{datetime.now().strftime('%Y%m%d_%H%M%S')}.png"
            result.final_screenshot.save(path)
            print(f"Final screenshot saved: {path}")
    else:
        print("Agent did not complete")
    print("=" * 60)


if __name__ == "__main__":
    main()
