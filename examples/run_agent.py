#!/usr/bin/env python
"""Programmatic Odin agent execution example.

Shows how to configure and run the Odin agent directly from Python code.

Run with:
    uv run python examples/run_agent.py
"""

import os
from dotenv import load_dotenv

from odin import Agent, AgentConfig, create_client
from odin.agent.parser import ParsedAction


def on_step(step: int, action: ParsedAction) -> None:
    """Callback for each step - prints execution progress."""
    print(f"\nStep {step}")
    print(f"  Thought: {action.thought}")
    print(f"  Action: {action.action}")
    print(f"  Params: {action.params}")


def main():
    load_dotenv()

    provider = os.environ.get("ODIN_LLM_PROVIDER", "openrouter")
    model = os.environ.get("ODIN_LLM_MODEL")
    if provider == "openrouter" and not os.environ.get("OPENROUTER_API_KEY"):
        print("ERROR: OPENROUTER_API_KEY environment variable not set.")
        return

    print("=" * 60)
    print("🔱 Odin Programmatic Example")
    print("=" * 60)

    try:
        # Create client (defaults to OpenRouter, using environment variables)
        llm = create_client(provider=provider, model=model)
    except (ImportError, ValueError) as e:
        print(f"Initialization failed: {e}")
        return

    # Configure the agent
    config = AgentConfig(
        loop=AgentConfig().loop.model_copy(update={
            "max_steps": 5,
            "max_batch_actions": 2,
        }),
    )

    # Initialize agent
    agent = Agent(llm, config=config, on_step=on_step)

    # Run a simple check/automation task
    task = "Open Finder"
    print(f"Running task: '{task}'...\n")

    try:
        result = agent.run(task)
        print("\n" + "=" * 60)
        print(f"Result Success: {result.success}")
        print(f"Message: {result.message}")
        print(f"Steps: {result.total_steps}")
        print(f"Actions Executed: {result.actions_executed}")
        print("=" * 60)
    except KeyboardInterrupt:
        print("\nInterrupted by user.")
    except Exception as e:
        print(f"\nExecution error: {e}")
    finally:
        llm.close()


if __name__ == "__main__":
    main()
