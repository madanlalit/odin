"""Shared helpers for the agent test suite."""

from __future__ import annotations

from collections.abc import Callable

from odin.action.elements import ElementActionHandler
from odin.action.safety import SafetyController
from odin.agent.core import Agent, AgentConfig
from odin.agent.executor import ActionExecutor
from odin.agent.parser import ParsedAction
from odin.llm.base import LLMProvider
from odin.perception.accessibility import Accessibility
from tests.agent.fakes import FakeActionController, FakeScreen


def _rewire_dependents(agent: Agent) -> None:
    agent.element_handler = ElementActionHandler(
        agent.accessibility,
        agent.action_controller,
        agent.safety,
    )
    agent.executor = ActionExecutor(
        agent.action_controller,
        agent.element_handler,
        agent.accessibility,
    )


def build_agent(
    llm: LLMProvider,
    *,
    config: AgentConfig | None = None,
    on_step: Callable[[int, ParsedAction], None] | None = None,
    action_approval_callback: Callable[[dict], bool] | None = None,
    screen: FakeScreen | None = None,
    accessibility: Accessibility | None = None,
    action_controller: FakeActionController | None = None,
    capture_config: dict | None = None,
    trace_dir=None,
) -> Agent:
    """Construct an agent with the given fakes and re-wire dependents."""
    if trace_dir is not None:
        base = config or AgentConfig()
        config = base.model_copy(update={"trace": base.trace.model_copy(update={"path": str(trace_dir / "trace.jsonl")})})
    if capture_config is not None:
        base = config or AgentConfig()
        config = base.model_copy(update={"capture": base.capture.model_copy(update=capture_config)})
    agent = Agent(
        llm,
        config=config,
        on_step=on_step,
        action_approval_callback=action_approval_callback,
    )

    if screen is not None:
        agent.screen = screen

    if accessibility is not None:
        agent.accessibility = accessibility

    if action_controller is not None:
        agent.action_controller = action_controller
        agent.safety = SafetyController.from_backend(
            action_controller._backend,
            agent.config.safety,
        )

    if action_controller is not None or accessibility is not None:
        _rewire_dependents(agent)

    return agent
