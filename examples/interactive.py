#!/usr/bin/env python
"""
Interactive agent REPL - run multiple tasks in sequence.

Run with:
    uv run python examples/interactive.py
"""

import os
import sys

from dotenv import load_dotenv
from odin import Agent, AgentConfig, create_client
from odin.agent.parser import ParsedAction


def on_step(step: int, action: ParsedAction) -> None:
    """Print each step."""
    print(f"  [{step}] {action.action}: {action.params}")


def main():
    load_dotenv()

    provider = os.environ.get("ODIN_LLM_PROVIDER", "openrouter")
    model = os.environ.get("ODIN_LLM_MODEL")

    if provider == "openrouter" and not os.environ.get("OPENROUTER_API_KEY"):
        print("ERROR: Set OPENROUTER_API_KEY environment variable")
        sys.exit(1)

    print("🔱 Odin Interactive Agent")
    print("Type a task and press Enter. Type 'quit' to exit.\n")

    try:
        llm = create_client(provider=provider, model=model)
    except (ImportError, ValueError) as e:
        print(f"ERROR: {e}")
        sys.exit(1)

    config = AgentConfig()
    agent = Agent(llm, config=config, on_step=on_step)

    try:
        while True:
            try:
                task = input("\n📝 Task: ").strip()
            except EOFError:
                break

            if not task:
                continue
            if task.lower() in ("quit", "exit", "q"):
                break

            print(f"\n🚀 Running: {task}")
            print("-" * 40)

            result = agent.run(task)

            print("-" * 40)
            status = "✅" if result.success else "❌"
            print(f"{status} {result.message}")
            print(
                f"   Steps: {result.total_steps}, Duration: {result.duration_seconds:.1f}s"
            )

    except KeyboardInterrupt:
        print("\n\nGoodbye!")
    finally:
        llm.close()


if __name__ == "__main__":
    main()
