"""Tests for the main Agent class."""

import json
from unittest.mock import MagicMock, patch

import pytest
from PIL import Image

from odin.action.controller import ActionResult
from odin.action.safety import SafetyConfig
from odin.agent.core import Agent, AgentConfig, AgentStatus
from odin.agent.executor import ActionExecutor
from odin.agent.parser import ParsedAction
from odin.llm.base import LLMResponse
from odin.perception.accessibility import AccessibilitySnapshot, AXElementInfo, AXFrame


def _action(name: str, params: dict | None = None, thought: str | None = None) -> dict:
    """Build a test action object."""
    item = {"action": name, "params": params or {}}
    if thought is not None:
        item["thought"] = thought
    return item


def _batch_response(*actions: dict, thought: str = "test") -> str:
    """Build a batch-only LLM response."""
    return json.dumps({"thought": thought, "actions": list(actions)})


class FakeAccessibility:
    """Fake accessibility layer for agent tests."""

    def __init__(self):
        self._frame = AXFrame(x=100, y=200, width=80, height=40)
        self.snapshot = AccessibilitySnapshot(
            available=True,
            trusted=True,
            app="Test App",
            window="Test Window",
            elements=[
                AXElementInfo(
                    id="ax_1",
                    role="AXButton",
                    title="Submit",
                    frame=self._frame,
                    actions=["AXPress"],
                )
            ],
        )
        self.performed_actions: list[tuple[str, str]] = []
        self.focused: list[str] = []
        self.values: list[tuple[str, str]] = []

    def capture(self, *, max_depth: int = 8, max_nodes: int = 120):  # noqa: ARG002
        return self.snapshot

    def perform_action(self, element_id: str, action_name: str):
        self.performed_actions.append((element_id, action_name))
        if action_name == "press":
            return True, f"pressed {element_id}"
        return False, "unsupported action"

    def focus(self, element_id: str):
        self.focused.append(element_id)
        return True, f"focused {element_id}"

    def set_value(self, element_id: str, value: str):
        self.values.append((element_id, value))
        return True, f"set {element_id}"

    def frame(self, element_id: str):
        if element_id == "ax_1":
            return self._frame
        return None


class TestAgent:
    """Tests for the main Agent class."""

    @pytest.fixture
    def mock_llm_client(self):
        """Create a mock LLM client."""
        client = MagicMock()
        client.analyze_screen.return_value = LLMResponse(
            content=_batch_response(
                _action("done", {"result": "Task complete", "success": True}),
                thought="Done",
            )
        )
        return client

    @pytest.fixture
    def mock_screenshot(self):
        """Create a mock screenshot."""
        return Image.new("RGB", (1920, 1080), color="white")

    def test_agent_initialization(self, mock_llm_client):
        """Test agent initialization."""
        agent = Agent(mock_llm_client)

        assert agent.status == AgentStatus.IDLE
        assert agent.config.max_steps == 100

    def test_agent_with_custom_config(self, mock_llm_client):
        """Test agent with custom configuration."""
        config = AgentConfig(max_steps=10, step_delay=0.25)
        agent = Agent(mock_llm_client, config=config)

        assert agent.config.max_steps == 10
        assert agent.config.step_delay == 0.25

    @patch("odin.agent.core.Screen")
    def test_agent_run_immediate_done(
        self, mock_screen_class, mock_llm_client, mock_screenshot
    ):
        """Test agent run that immediately completes."""
        mock_screen = MagicMock()
        mock_screen.get_screenshot.return_value = mock_screenshot
        mock_screen_class.return_value = mock_screen

        agent = Agent(mock_llm_client)
        result = agent.run("Test task")

        assert result.success is True
        assert result.message == "Task complete"
        assert agent.status == AgentStatus.COMPLETED

    @patch("odin.agent.core.Screen")
    def test_agent_sends_accessibility_context_to_llm(
        self, mock_screen_class, mock_llm_client, mock_screenshot
    ):
        """Test agent includes accessibility context in LLM requests."""
        mock_screen = MagicMock()
        mock_screen.get_screenshot.return_value = mock_screenshot
        mock_screen_class.return_value = mock_screen

        fake_ax = FakeAccessibility()
        agent = Agent(mock_llm_client, config=AgentConfig(step_delay=0))
        agent.accessibility = fake_ax  # type: ignore[assignment]
        agent.element_handler.accessibility = fake_ax  # type: ignore[assignment]
        agent.executor.accessibility = fake_ax  # type: ignore[assignment]
        agent.action_controller.screen_width = 1920
        agent.action_controller.screen_height = 1080
        agent.action_controller.get_mouse_position = MagicMock(return_value=(960, 540))
        result = agent.run("Use accessibility")

        assert result.success is True
        screen_context = mock_llm_client.analyze_screen.call_args.kwargs[
            "screen_context"
        ]
        assert screen_context["accessibility"]["available"] is True
        assert screen_context["accessibility"]["elements"][0]["id"] == "ax_1"
        assert (
            screen_context["coordinate_system"]["type"]
            == "screenshot_coordinates_for_raw_xy_actions"
        )
        assert screen_context["mouse"] == {
            "available": True,
            "screen_position": {
                "x": 960,
                "y": 540,
            },
            "screenshot_position": {
                "x": 960,
                "y": 540,
            },
        }

    @patch("odin.agent.core.Screen")
    def test_agent_maps_screenshot_coordinates_to_screen_coordinates(
        self, mock_screen_class, mock_llm_client, tmp_path
    ):
        """Test model screenshot coordinates are mapped before execution."""
        mock_screen = MagicMock()
        mock_screen.get_screenshot.return_value = Image.new(
            "RGB",
            (3600, 2338),
            color="white",
        )
        mock_screen_class.return_value = mock_screen

        mock_llm_client.analyze_screen.side_effect = [
            LLMResponse(
                content=_batch_response(
                    _action("click", {"x": 841, "y": 1049}),
                    thought="Click Firefox in dock",
                )
            ),
            LLMResponse(
                content=_batch_response(
                    _action("done", {"result": "Clicked", "success": True}),
                    thought="Done",
                )
            ),
        ]

        trace_path = tmp_path / "coordinate-trace.jsonl"
        config = AgentConfig(
            step_delay=0,
            max_screenshot_size=(1663, 1080),
            trace_path=trace_path,
        )
        agent = Agent(mock_llm_client, config=config)
        agent.action_controller.screen_width = 1800
        agent.action_controller.screen_height = 1169
        agent.safety.screen_width = 1800
        agent.safety.screen_height = 1169
        agent.action_controller.click = MagicMock(
            return_value=ActionResult(
                success=True,
                action="click",
                message="Clicked",
            )
        )

        result = agent.run("Open Firefox")

        assert result.success is True
        agent.action_controller.click.assert_called_once_with(
            x=910,
            y=1135,
            button="left",
        )
        events = [
            json.loads(line)
            for line in trace_path.read_text(encoding="utf-8").splitlines()
        ]
        mapping_event = next(
            event for event in events if event["event"] == "action_coordinates_mapped"
        )
        assert mapping_event["data"]["mappings"] == [
            {
                "x_key": "x",
                "y_key": "y",
                "input_x": 841,
                "input_y": 1049,
                "mapped_x": 910,
                "mapped_y": 1135,
            }
        ]

    @patch("odin.agent.core.Screen")
    def test_agent_maps_screenshot_coordinates_to_screen_coordinates_for_drag(
        self, mock_screen_class, mock_llm_client, tmp_path
    ):
        """Test model screenshot coordinates are mapped for drag actions before execution."""
        mock_screen = MagicMock()
        mock_screen.get_screenshot.return_value = Image.new(
            "RGB",
            (3600, 2338),
            color="white",
        )
        mock_screen_class.return_value = mock_screen

        mock_llm_client.analyze_screen.side_effect = [
            LLMResponse(
                content=_batch_response(
                    _action("drag", {"start_x": 841, "start_y": 1049, "end_x": 1000, "end_y": 500}),
                    thought="Drag file",
                )
            ),
            LLMResponse(
                content=_batch_response(
                    _action("done", {"result": "Dragged", "success": True}),
                    thought="Done",
                )
            ),
        ]

        trace_path = tmp_path / "drag-coordinate-trace.jsonl"
        config = AgentConfig(
            step_delay=0,
            max_screenshot_size=(1663, 1080),
            trace_path=trace_path,
        )
        agent = Agent(mock_llm_client, config=config)
        agent.action_controller.screen_width = 1800
        agent.action_controller.screen_height = 1169
        agent.safety.screen_width = 1800
        agent.safety.screen_height = 1169
        agent.action_controller.drag = MagicMock(
            return_value=ActionResult(
                success=True,
                action="drag",
                message="Dragged",
            )
        )

        result = agent.run("Drag file")

        assert result.success is True
        agent.action_controller.drag.assert_called_once_with(
            start_x=910,
            start_y=1135,
            end_x=1082,
            end_y=541,
            duration=0.5,
        )

    @patch("odin.agent.core.Screen")
    def test_agent_executes_press_element(
        self, mock_screen_class, mock_llm_client, mock_screenshot
    ):
        """Test native accessibility element actions are executed."""
        mock_screen = MagicMock()
        mock_screen.get_screenshot.return_value = mock_screenshot
        mock_screen_class.return_value = mock_screen

        mock_llm_client.analyze_screen.side_effect = [
            LLMResponse(
                content=_batch_response(
                    _action("press_element", {"element_id": "ax_1"}),
                    thought="Press Submit",
                )
            ),
            LLMResponse(
                content=_batch_response(
                    _action("done", {"result": "Submitted", "success": True}),
                    thought="Done",
                )
            ),
        ]

        fake_accessibility = FakeAccessibility()
        agent = Agent(mock_llm_client, config=AgentConfig(step_delay=0))
        agent.accessibility = fake_accessibility  # type: ignore[assignment]
        agent.element_handler.accessibility = fake_accessibility  # type: ignore[assignment]
        agent.executor.accessibility = fake_accessibility  # type: ignore[assignment]
        result = agent.run("Press submit")

        assert result.success is True
        assert fake_accessibility.performed_actions == [("ax_1", "press")]

    @patch("odin.agent.core.Screen")
    def test_agent_run_with_click(
        self, mock_screen_class, mock_llm_client, mock_screenshot
    ):
        """Test agent run with click action then done."""
        mock_screen = MagicMock()
        mock_screen.get_screenshot.return_value = mock_screenshot
        mock_screen_class.return_value = mock_screen

        mock_llm_client.analyze_screen.side_effect = [
            LLMResponse(
                content=_batch_response(
                    _action("click", {"x": 500, "y": 300}),
                    thought="Click button",
                )
            ),
            LLMResponse(
                content=_batch_response(
                    _action("done", {"result": "Clicked and done", "success": True}),
                    thought="Done",
                )
            ),
        ]

        with patch.object(ActionExecutor, "execute") as mock_execute:
            mock_execute.return_value = ActionResult(
                success=True, action="click", message="Clicked"
            )

            agent = Agent(mock_llm_client)
            result = agent.run("Click test")

        assert result.success is True
        assert result.total_steps == 2
        assert mock_execute.called

    @patch("odin.agent.core.Screen")
    def test_agent_executes_action_batch(
        self, mock_screen_class, mock_llm_client, mock_screenshot
    ):
        """Test batch mode executes multiple actions from one LLM call."""
        mock_screen = MagicMock()
        mock_screen.get_screenshot.return_value = mock_screenshot
        mock_screen_class.return_value = mock_screen

        mock_llm_client.analyze_screen.side_effect = [
            LLMResponse(
                content="""
                {
                    "thought": "Focus address bar and type URL",
                    "actions": [
                        {"action": "hotkey", "params": {"keys": ["command", "l"]}},
                        {"action": "type", "params": {"text": "example.com"}}
                    ]
                }
                """
            ),
            LLMResponse(
                content=_batch_response(
                    _action("done", {"result": "Typed URL", "success": True}),
                    thought="Done",
                )
            ),
        ]

        with patch.object(ActionExecutor, "execute") as mock_execute:
            mock_execute.return_value = ActionResult(
                success=True,
                action="batch-action",
                message="Executed",
            )

            config = AgentConfig(
                step_delay=0,
                max_batch_actions=3,
                safety=SafetyConfig(min_action_delay=0),
            )
            agent = Agent(mock_llm_client, config=config)
            result = agent.run("Type a URL")

        assert result.success is True
        assert result.total_steps == 2
        assert [call.args[0].action for call in mock_execute.call_args_list] == [
            "hotkey",
            "type",
        ]
        system_prompt = mock_llm_client.analyze_screen.call_args_list[0].kwargs[
            "system_prompt"
        ]
        assert '"actions":[' in system_prompt

    @patch("odin.agent.core.Screen")
    def test_agent_requests_approval_before_every_action(
        self, mock_screen_class, mock_llm_client, mock_screenshot, tmp_path
    ):
        """When enabled, every executable action waits for human approval."""
        mock_screen = MagicMock()
        mock_screen.get_screenshot.return_value = mock_screenshot
        mock_screen_class.return_value = mock_screen

        mock_llm_client.analyze_screen.side_effect = [
            LLMResponse(
                content=_batch_response(
                    _action("hotkey", {"keys": ["command", "l"]}),
                    _action("type", {"text": "example.com"}),
                    thought="Focus and type",
                )
            ),
            LLMResponse(
                content=_batch_response(
                    _action("done", {"result": "Approved", "success": True}),
                    thought="Done",
                )
            ),
        ]

        approvals: list[dict] = []
        order: list[str] = []

        def approve(request: dict) -> bool:
            approvals.append(request)
            order.append(f"approve:{request['action']}")
            return True

        trace_path = tmp_path / "approval-trace.jsonl"
        with patch.object(ActionExecutor, "execute") as mock_execute:
            def execute(action: ParsedAction) -> ActionResult:
                order.append(f"execute:{action.action}")
                return ActionResult(
                    success=True,
                    action="approved-action",
                    message="Executed",
                )

            mock_execute.side_effect = execute

            config = AgentConfig(
                step_delay=0,
                max_batch_actions=2,
                trace_path=trace_path,
                safety=SafetyConfig(
                    require_confirmation=True,
                    min_action_delay=0,
                ),
            )
            agent = Agent(
                mock_llm_client,
                config=config,
                action_approval_callback=approve,
            )
            result = agent.run("Approval test")

        assert result.success is True
        assert [request["action"] for request in approvals] == ["hotkey", "type"]
        assert [call.args[0].action for call in mock_execute.call_args_list] == [
            "hotkey",
            "type",
        ]
        assert order == [
            "approve:hotkey",
            "approve:type",
            "execute:hotkey",
            "execute:type",
        ]

        events = [
            json.loads(line)
            for line in trace_path.read_text(encoding="utf-8").splitlines()
        ]
        event_names = [event["event"] for event in events]
        assert event_names.count("action_approval_requested") == 2
        assert event_names.count("action_approval_received") == 2
        assert all(
            event["data"]["approved"]
            for event in events
            if event["event"] == "action_approval_received"
        )

    @patch("odin.agent.core.Screen")
    def test_agent_applies_step_delay(
        self, mock_screen_class, mock_llm_client, mock_screenshot
    ):
        """Test agent uses configured delay between steps."""
        mock_screen = MagicMock()
        mock_screen.get_screenshot.return_value = mock_screenshot
        mock_screen_class.return_value = mock_screen

        mock_llm_client.analyze_screen.side_effect = [
            LLMResponse(
                content=_batch_response(
                    _action("click", {"x": 500, "y": 300}),
                    thought="Click button",
                )
            ),
            LLMResponse(
                content=_batch_response(
                    _action("done", {"result": "Clicked and done", "success": True}),
                    thought="Done",
                )
            ),
        ]

        with (
            patch.object(ActionExecutor, "execute") as mock_execute,
            patch("odin.agent.core.time.sleep") as mock_sleep,
        ):
            mock_execute.return_value = ActionResult(
                success=True, action="click", message="Clicked"
            )

            config = AgentConfig(step_delay=0.25)
            agent = Agent(mock_llm_client, config=config)
            result = agent.run("Delay test")

        assert result.success is True
        mock_sleep.assert_called_once_with(0.25)

    @patch("odin.agent.core.Screen")
    def test_agent_max_steps(self, mock_screen_class, mock_llm_client, mock_screenshot):
        """Test agent stops after max_steps."""
        mock_screen = MagicMock()
        mock_screen.get_screenshot.return_value = mock_screenshot
        mock_screen_class.return_value = mock_screen

        mock_llm_client.analyze_screen.return_value = LLMResponse(
            content=_batch_response(
                _action("click", {"x": 100, "y": 100}),
                thought="Keep clicking",
            )
        )

        with patch.object(ActionExecutor, "execute") as mock_execute:
            mock_execute.return_value = ActionResult(
                success=True, action="click", message="Clicked"
            )

            config = AgentConfig(max_steps=3)
            agent = Agent(mock_llm_client, config=config)
            result = agent.run("Endless task")

        assert result.success is False
        assert "Max steps" in result.message
        assert result.total_steps == 3

    @patch("odin.agent.core.Screen")
    def test_agent_stop(self, mock_screen_class, mock_llm_client, mock_screenshot):
        """Test agent can be stopped."""
        mock_screen = MagicMock()
        mock_screen.get_screenshot.return_value = mock_screenshot
        mock_screen_class.return_value = mock_screen

        agent = Agent(mock_llm_client)
        agent.stop()

        assert agent._stop_requested is True

    @patch("odin.agent.core.Screen")
    def test_agent_handles_parse_error(
        self, mock_screen_class, mock_llm_client, mock_screenshot
    ):
        """Test agent handles parse errors gracefully."""
        mock_screen = MagicMock()
        mock_screen.get_screenshot.return_value = mock_screenshot
        mock_screen_class.return_value = mock_screen

        mock_llm_client.analyze_screen.side_effect = [
            LLMResponse(content="This is not valid JSON"),
            LLMResponse(
                content=_batch_response(
                    _action("done", {"result": "Done", "success": True}),
                    thought="Done",
                )
            ),
        ]

        agent = Agent(mock_llm_client)
        result = agent.run("Parse error test")

        assert result.success is True
        assert result.total_steps == 2

    def test_agent_on_step_callback(self, mock_llm_client):
        """Test that on_step callback is called."""
        callback_calls = []

        def on_step(step: int, action: ParsedAction):
            callback_calls.append((step, action.action))

        with patch("odin.agent.core.Screen") as mock_screen_class:
            mock_screen = MagicMock()
            mock_screen.get_screenshot.return_value = Image.new("RGB", (100, 100))
            mock_screen_class.return_value = mock_screen

            mock_llm_client.analyze_screen.side_effect = [
                LLMResponse(
                    content=_batch_response(
                        _action("click", {"x": 50, "y": 50}),
                        thought="Click",
                    )
                ),
                LLMResponse(
                    content=_batch_response(
                        _action("done", {"result": "Done", "success": True}),
                        thought="Done",
                    )
                ),
            ]

            with patch.object(ActionExecutor, "execute") as mock_execute:
                mock_execute.return_value = ActionResult(success=True, action="click")

                agent = Agent(mock_llm_client, on_step=on_step)
                agent.run("Callback test")

        assert len(callback_calls) == 1
        assert callback_calls[0] == (1, "click")

    @patch("odin.agent.core.Screen")
    def test_agent_writes_structured_trace(
        self, mock_screen_class, mock_llm_client, mock_screenshot, tmp_path
    ):
        """Test JSONL tracing captures the main run lifecycle."""
        mock_screen = MagicMock()
        mock_screen.get_screenshot.return_value = mock_screenshot
        mock_screen_class.return_value = mock_screen

        mock_llm_client.model = "test-model"
        mock_llm_client.analyze_screen.side_effect = [
            LLMResponse(
                content=_batch_response(
                    _action("click", {"x": 500, "y": 300}),
                    thought="Click",
                ),
                usage={"inputTokens": 10, "outputTokens": 5, "totalTokens": 15},
            ),
            LLMResponse(
                content=_batch_response(
                    _action("done", {"result": "Done", "success": True}),
                    thought="Done",
                ),
                usage={"inputTokens": 8, "outputTokens": 4, "totalTokens": 12},
            ),
        ]

        trace_path = tmp_path / "agent-trace.jsonl"
        with patch.object(ActionExecutor, "execute") as mock_execute:
            mock_execute.return_value = ActionResult(
                success=True,
                action="click",
                message="Clicked",
            )

            config = AgentConfig(
                max_steps=3,
                step_delay=0,
                trace_path=trace_path,
                trace_screenshots=True,
            )
            agent = Agent(mock_llm_client, config=config)
            result = agent.run("Trace test")

        assert result.success is True
        assert result.trace_id is not None
        assert result.trace_path == str(trace_path)
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
            for line in trace_path.read_text(encoding="utf-8").splitlines()
        ]
        event_names = [event["event"] for event in events]

        assert event_names[0] == "run_started"
        assert "screenshot_captured" in event_names
        assert "llm_request_started" in event_names
        assert "llm_response_received" in event_names
        assert "mouse_position_captured" in event_names
        assert "action_parsed" in event_names
        assert "safety_checked" in event_names
        assert "action_execution_started" in event_names
        assert "action_executed" in event_names
        assert "task_done" in event_names
        assert event_names[-1] == "run_finished"

        action_started = next(
            event for event in events if event["event"] == "action_execution_started"
        )
        assert action_started["data"]["thought"] == "Click"
        assert action_started["data"]["target"] == {
            "x": action_started["data"]["params"]["x"],
            "y": action_started["data"]["params"]["y"],
            "source": "coordinates",
        }

        screenshot_event = next(
            event for event in events if event["event"] == "screenshot_captured"
        )
        screenshot_path = screenshot_event["data"]["screenshot_path"]
        assert screenshot_path
        assert (tmp_path / "agent-trace_screenshots").exists()
        assert screenshot_path.endswith(".png")

        response_event = next(
            event for event in events if event["event"] == "llm_response_received"
        )
        assert response_event["data"]["usage"] == {
            "inputTokens": 10,
            "outputTokens": 5,
            "totalTokens": 15,
        }
        assert response_event["data"]["usage_totals"]["input_tokens"] == 10

    @patch("odin.agent.core.Screen")
    def test_agent_traces_parse_errors(
        self, mock_screen_class, mock_llm_client, mock_screenshot, tmp_path
    ):
        """Test parse failures are recorded as structured trace events."""
        mock_screen = MagicMock()
        mock_screen.get_screenshot.return_value = mock_screenshot
        mock_screen_class.return_value = mock_screen

        mock_llm_client.analyze_screen.side_effect = [
            LLMResponse(content="not json"),
            LLMResponse(
                content=_batch_response(
                    _action("done", {"result": "Done", "success": True}),
                    thought="Done",
                )
            ),
        ]

        trace_path = tmp_path / "parse-trace.jsonl"
        config = AgentConfig(
            max_steps=3,
            step_delay=0,
            trace_path=trace_path,
        )
        agent = Agent(mock_llm_client, config=config)
        result = agent.run("Parse trace test")

        assert result.success is True
        events = [
            json.loads(line)
            for line in trace_path.read_text(encoding="utf-8").splitlines()
        ]
        parse_error = next(event for event in events if event["event"] == "parse_error")
        assert parse_error["step"] == 1
        assert parse_error["data"]["content"] == "not json"
