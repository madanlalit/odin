"""Tests for the Agent class and the ReAct loop."""

from __future__ import annotations

import json
from typing import Any

import pytest

from odin.action.safety import SafetyConfig
from odin.agent.actions import ActionKind
from odin.agent.core import Agent, AgentConfig, AgentStatus
from odin.agent.parser import ParsedAction
from odin.llm.base import LLMResponse
from odin.perception.accessibility import AccessibilitySnapshot, AXElementInfo, AXFrame
from tests.agent.fakes import (
    FakeAccessibility,
    FakeActionController,
    FakeLLM,
    FakeScreen,
)
from tests.agent.helpers import build_agent


def _action(
    name: str | ActionKind,
    params: dict | None = None,
    thought: str | None = None,
) -> dict:
    """Build a test action object for LLM responses."""
    item: dict[str, Any] = {
        "action": str(name),
        "params": params or {},
    }
    if thought is not None:
        item["thought"] = thought
    return item


def _batch_response(*actions: dict, thought: str = "test") -> str:
    """Build a batch-only LLM response."""
    return json.dumps({"thought": thought, "actions": list(actions)})


_AX_FRAME = AXFrame(x=100, y=200, width=80, height=40)
_AX_SNAPSHOT = AccessibilitySnapshot(
    available=True,
    trusted=True,
    app="Test App",
    window="Test Window",
    elements=[
        AXElementInfo(
            id="ax_1", role="AXButton", title="Submit",
            frame=_AX_FRAME, actions=["AXPress"],
        ),
    ],
)


class TestAgentLifecycle:
    """Basic agent construction and the ``run`` happy path."""

    def test_agent_initialization_is_idle(self):
        """A freshly-constructed agent is idle and uses the default config."""
        agent = Agent(FakeLLM('{"thought": "x", "actions": []}'))

        assert agent.status is AgentStatus.IDLE
        assert agent.config.loop.max_steps == 100

    def test_agent_with_custom_loop_config(self):
        """Custom loop config overrides defaults."""
        agent = Agent(
            FakeLLM('{"thought": "x", "actions": []}'),
            config=AgentConfig(loop=AgentConfig().loop.model_copy(update={
                "max_steps": 10, "step_delay": 0.25,
            })),
        )

        assert agent.config.loop.max_steps == 10
        assert agent.config.loop.step_delay == 0.25

    def test_agent_run_immediate_done_succeeds(self):
        """An LLM that replies with ``done`` short-circuits to success."""
        llm = FakeLLM(_batch_response(
            _action(ActionKind.DONE, {"result": "Task complete", "success": True}),
        ))
        agent = build_agent(
            llm,
            screen=FakeScreen(),
            accessibility=FakeAccessibility(_AX_SNAPSHOT),
            action_controller=FakeActionController(),
        )

        result = agent.run("Test task")

        assert result.success is True
        assert result.message == "Task complete"
        assert agent.status is AgentStatus.COMPLETED


class TestAgentScreenContext:
    """The screen context sent to the LLM is correct."""

    def test_sends_accessibility_context_to_llm(self):
        """Accessibility and coordinate context reach the LLM call."""
        llm = FakeLLM(_batch_response(
            _action(ActionKind.DONE, {"result": "ok", "success": True}),
        ))
        agent = build_agent(
            llm,
            screen=FakeScreen(),
            accessibility=FakeAccessibility(_AX_SNAPSHOT),
            action_controller=FakeActionController(
                screen_width=1920, screen_height=1080,
                mouse_position=(960, 540),
            ),
        )

        result = agent.run("Use accessibility")
        assert result.success is True

        screen_context = llm.calls[0]["screen_context"]
        assert screen_context["accessibility"]["available"] is True
        assert screen_context["accessibility"]["elements"][0]["id"] == "ax_1"
        assert (
            screen_context["coordinate_system"]["type"]
            == "screenshot_coordinates_for_raw_xy_actions"
        )
        assert screen_context["mouse"]["screen_position"] == {"x": 960, "y": 540}


class TestAgentCoordinateMapping:
    """Screenshot coordinates are mapped to screen coordinates before dispatch."""

    def test_click_coordinates_are_mapped(self):
        """A model click at (841, 1049) is mapped before reaching the backend."""
        llm = FakeLLM([
            _batch_response(
                _action(ActionKind.CLICK, {"x": 841, "y": 1049}),
                thought="Click Firefox in dock",
            ),
            _batch_response(
                _action(ActionKind.DONE, {"result": "Clicked", "success": True}),
            ),
        ])
        action_controller = FakeActionController(
            screen_width=1800, screen_height=1169,
        )
        agent = build_agent(
            llm,
            screen=FakeScreen(width=3600, height=2338),
            accessibility=FakeAccessibility(),
            action_controller=action_controller,
        )
        agent.safety.screen_width = 1800
        agent.safety.screen_height = 1169

        result = agent.run("Open Firefox")
        assert result.success is True

        click = action_controller.find_call("click")
        assert click == {"action": "click", "x": 910, "y": 1135, "button": "left"}

    def test_drag_coordinates_are_mapped(self):
        """Both endpoints of a drag are mapped from screenshot to screen space."""
        llm = FakeLLM([
            _batch_response(
                _action(ActionKind.DRAG, {
                    "start_x": 841, "start_y": 1049,
                    "end_x": 1000, "end_y": 500,
                }),
            ),
            _batch_response(
                _action(ActionKind.DONE, {"result": "Dragged", "success": True}),
            ),
        ])
        action_controller = FakeActionController(
            screen_width=1800, screen_height=1169,
        )
        agent = build_agent(
            llm,
            screen=FakeScreen(width=3600, height=2338),
            accessibility=FakeAccessibility(),
            action_controller=action_controller,
        )
        agent.safety.screen_width = 1800
        agent.safety.screen_height = 1169

        result = agent.run("Drag file")
        assert result.success is True
        assert action_controller.find_call("drag") == {
            "action": "drag",
            "start_x": 910, "start_y": 1135,
            "end_x": 1082, "end_y": 541,
            "duration": 0.5,
        }


class TestAgentActionExecution:
    """Actions are executed via the executor and respect batch order."""

    def test_runs_batch_of_keyboard_actions(self):
        """A batch of hotkey+type actions runs in order and uses the system prompt."""
        llm = FakeLLM([
            """
            {
                "thought": "Focus and type",
                "actions": [
                    {"action": "hotkey", "params": {"keys": ["command", "l"]}},
                    {"action": "type", "params": {"text": "example.com"}}
                ]
            }
            """,
            _batch_response(
                _action(ActionKind.DONE, {"result": "Typed URL", "success": True}),
            ),
        ])
        action_controller = FakeActionController()
        agent = build_agent(
            llm,
            screen=FakeScreen(),
            accessibility=FakeAccessibility(),
            action_controller=action_controller,
        )
        agent.config = agent.config.model_copy(update={
            "loop": agent.config.loop.model_copy(update={"max_batch_actions": 3}),
            "safety": SafetyConfig(min_action_delay=0),
        })

        result = agent.run("Type a URL")

        assert result.success is True
        hotkey_call = action_controller.find_call("hotkey")
        type_call = action_controller.find_call("type_text")
        assert hotkey_call["keys"] == ["command", "l"]
        assert type_call["text"] == "example.com"
        assert '"actions":[' in llm.calls[0]["system_prompt"]

    def test_press_element_uses_native_ax_action(self):
        """Native accessibility actions are recorded."""
        llm = FakeLLM([
            _batch_response(
                _action(ActionKind.PRESS_ELEMENT, {"element_id": "ax_1"}),
            ),
            _batch_response(
                _action(ActionKind.DONE, {"result": "ok", "success": True}),
            ),
        ])
        ax = FakeAccessibility(_AX_SNAPSHOT)
        agent = build_agent(
            llm,
            screen=FakeScreen(),
            accessibility=ax,
            action_controller=FakeActionController(),
        )
        agent.config = agent.config.model_copy(update={
            "loop": agent.config.loop.model_copy(update={"step_delay": 0}),
        })

        result = agent.run("Press Submit")
        assert result.success is True
        assert result.total_steps == 2
        assert ax.performed_actions == [("ax_1", "press")]


class TestAgentApprovals:
    """Human-in-the-loop approval before executing non-done actions."""

    def test_approval_required_blocks_when_callback_returns_false(self):
        """A denied action stops the batch and prevents execution."""
        llm = FakeLLM([
            _batch_response(
                _action(ActionKind.HOTKEY, {"keys": ["command", "l"]}),
                _action(ActionKind.TYPE, {"text": "example.com"}),
            ),
            _batch_response(
                _action(ActionKind.DONE, {"result": "ok", "success": True}),
            ),
        ])
        action_controller = FakeActionController()
        agent = build_agent(
            llm,
            screen=FakeScreen(),
            accessibility=FakeAccessibility(),
            action_controller=action_controller,
        )
        agent.config = agent.config.model_copy(update={
            "loop": agent.config.loop.model_copy(update={
                "max_batch_actions": 2, "step_delay": 0,
            }),
            "safety": SafetyConfig(
                require_confirmation=True, min_action_delay=0,
            ),
        })

        approvals: list[str] = []

        def callback(request: dict) -> bool:
            approvals.append(request["action"])
            return False

        agent._action_approval_callback = callback
        result = agent.run("Approval test")

        assert result.success is True
        assert approvals == ["hotkey"]
        assert action_controller.calls == []


class TestAgentDelaysAndLimits:
    """Loop timing and step limits."""

    def test_step_delay_is_respected(self, monkeypatch: pytest.MonkeyPatch):
        """``step_delay`` sleeps between successful steps."""
        sleep_calls: list[float] = []
        monkeypatch.setattr(
            "odin.agent.loop.time.sleep", lambda seconds: sleep_calls.append(seconds),
        )
        llm = FakeLLM([
            _batch_response(_action(ActionKind.CLICK, {"x": 500, "y": 300})),
            _batch_response(
                _action(ActionKind.DONE, {"result": "ok", "success": True}),
            ),
        ])
        agent = build_agent(
            llm,
            screen=FakeScreen(),
            accessibility=FakeAccessibility(),
            action_controller=FakeActionController(),
        )
        agent.config = agent.config.model_copy(update={
            "loop": agent.config.loop.model_copy(update={"step_delay": 0.25}),
        })

        result = agent.run("Delay test")
        assert result.success is True
        assert sleep_calls == [0.25]

    def test_max_steps_terminates_with_failure(self):
        """Running past ``max_steps`` returns a failed result."""
        llm = FakeLLM(
            default_response=_batch_response(
                _action(ActionKind.CLICK, {"x": 100, "y": 100}),
            ),
        )
        agent = build_agent(
            llm,
            screen=FakeScreen(),
            accessibility=FakeAccessibility(),
            action_controller=FakeActionController(),
        )
        agent.config = agent.config.model_copy(update={
            "loop": agent.config.loop.model_copy(update={"max_steps": 3}),
        })

        result = agent.run("Endless task")
        assert result.success is False
        assert "Max steps" in result.message
        assert result.total_steps == 3

    def test_stop_short_circuits_the_loop(self):
        """``stop()`` requests termination before the next step."""
        agent = Agent(FakeLLM('{"thought":"x","actions":[]}'))
        agent.stop()
        assert agent._stop_requested is True


class TestAgentErrorHandling:
    """Failure modes the agent must recover from gracefully."""

    def test_parse_error_recovers_on_next_step(self):
        """A bad response is treated as a recoverable parse error."""
        llm = FakeLLM([
            "This is not valid JSON",
            _batch_response(
                _action(ActionKind.DONE, {"result": "ok", "success": True}),
            ),
        ])
        agent = build_agent(
            llm,
            screen=FakeScreen(),
            accessibility=FakeAccessibility(),
            action_controller=FakeActionController(),
        )

        result = agent.run("Parse error test")
        assert result.success is True
        assert result.total_steps == 2


class TestAgentCallbacks:
    """Per-step callback wiring."""

    def test_on_step_callback_fires_for_each_action(self):
        """The ``on_step`` callback receives every executed action."""
        steps: list[tuple[int, str]] = []

        def on_step(step: int, action: ParsedAction) -> None:
            steps.append((step, str(action.action)))

        llm = FakeLLM([
            _batch_response(_action(ActionKind.CLICK, {"x": 50, "y": 50})),
            _batch_response(
                _action(ActionKind.DONE, {"result": "ok", "success": True}),
            ),
        ])
        agent = build_agent(
            llm,
            screen=FakeScreen(width=100, height=100),
            accessibility=FakeAccessibility(),
            action_controller=FakeActionController(),
            on_step=on_step,
        )
        result = agent.run("Callback test")

        assert result.success is True
        assert steps == [(1, "click")]


class TestAgentTraceRecording:
    """Structured trace events are emitted in the expected order."""

    def test_writes_run_started_run_finished_and_step_events(self, tmp_path):
        """The full ReAct lifecycle produces the expected trace events."""
        llm = FakeLLM([
            LLMResponse(
                content=_batch_response(
                    _action(ActionKind.CLICK, {"x": 500, "y": 300}),
                ),
                usage={"inputTokens": 10, "outputTokens": 5, "totalTokens": 15},
            ),
            LLMResponse(
                content=_batch_response(
                    _action(ActionKind.DONE, {"result": "ok", "success": True}),
                ),
                usage={"inputTokens": 8, "outputTokens": 4, "totalTokens": 12},
            ),
        ])
        action_controller = FakeActionController()
        agent = build_agent(
            llm,
            screen=FakeScreen(),
            accessibility=FakeAccessibility(),
            action_controller=action_controller,
        )
        agent.config = agent.config.model_copy(update={
            "loop": agent.config.loop.model_copy(update={"max_steps": 3, "step_delay": 0}),
            "trace": agent.config.trace.model_copy(update={
                "path": tmp_path / "agent-trace.jsonl",
                "save_screenshots": True,
            }),
        })
        agent.tracer = agent._create_tracer()

        result = agent.run("Trace test")
        assert result.success is True
        assert result.llm_usage == {
            "requests": 2,
            "input_tokens": 18,
            "output_tokens": 9,
            "total_tokens": 27,
            "cache_read_input_tokens": 0,
            "cache_write_input_tokens": 0,
        }

        events = [
            json.loads(line)
            for line in (tmp_path / "agent-trace.jsonl").read_text().splitlines()
        ]
        event_names = [event["event"] for event in events]

        assert event_names[0] == "run_started"
        assert event_names[-1] == "run_finished"
        assert "screenshot_captured" in event_names
        assert "llm_request_started" in event_names
        assert "llm_response_received" in event_names
        assert "action_parsed" in event_names
        assert "safety_checked" in event_names
        assert "action_execution_started" in event_names
        assert "action_executed" in event_names
        assert "task_done" in event_names

        response_event = next(
            event for event in events if event["event"] == "llm_response_received"
        )
        assert response_event["data"]["usage"] == {
            "inputTokens": 10, "outputTokens": 5, "totalTokens": 15,
        }

    def test_parse_error_is_traced(self, tmp_path):
        """Parse failures appear in the trace before the agent recovers."""
        llm = FakeLLM([
            "not json",
            _batch_response(
                _action(ActionKind.DONE, {"result": "ok", "success": True}),
            ),
        ])
        agent = build_agent(
            llm,
            screen=FakeScreen(),
            accessibility=FakeAccessibility(),
            action_controller=FakeActionController(),
        )
        agent.config = agent.config.model_copy(update={
            "loop": agent.config.loop.model_copy(update={"max_steps": 3, "step_delay": 0}),
            "trace": agent.config.trace.model_copy(update={
                "path": tmp_path / "parse-trace.jsonl",
            }),
        })
        agent.tracer = agent._create_tracer()

        result = agent.run("Parse trace test")
        assert result.success is True

        events = [
            json.loads(line)
            for line in (tmp_path / "parse-trace.jsonl").read_text().splitlines()
        ]
        parse_error = next(event for event in events if event["event"] == "parse_error")
        assert parse_error["step"] == 1
        assert parse_error["data"]["content"] == "not json"


__all__: list[str] = []
