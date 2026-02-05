"""Tests for the agent module."""

from unittest.mock import MagicMock, patch

import pytest
from PIL import Image

from odin.action.controller import ActionResult
from odin.agent.core import Agent, AgentConfig, AgentStatus
from odin.agent.memory import AgentMemory
from odin.agent.parser import (
    ParsedAction,
    ParseError,
    parse_llm_response,
    validate_action_params,
)
from odin.llm.client import LLMResponse


# =============================================================================
# Parser Tests
# =============================================================================


class TestParser:
    """Tests for the LLM response parser."""

    def test_parse_valid_click_action(self):
        """Test parsing a valid click action."""
        response = """
        {
            "thought": "I see a button at coordinates (500, 300)",
            "action": "click",
            "params": {"x": 500, "y": 300}
        }
        """
        action = parse_llm_response(response)

        assert action.action == "click"
        assert action.params["x"] == 500
        assert action.params["y"] == 300
        assert "button" in action.thought.lower()

    def test_parse_click_with_button(self):
        """Test parsing click with specific button."""
        response = """{"thought": "Right click", "action": "click", "params": {"x": 100, "y": 200, "button": "right"}}"""
        action = parse_llm_response(response)

        assert action.action == "click"
        assert action.params["button"] == "right"

    def test_parse_type_action(self):
        """Test parsing a type action."""
        response = """{"thought": "Type search query", "action": "type", "params": {"text": "hello world"}}"""
        action = parse_llm_response(response)

        assert action.action == "type"
        assert action.params["text"] == "hello world"

    def test_parse_hotkey_action(self):
        """Test parsing a hotkey action."""
        response = """{"thought": "Copy text", "action": "hotkey", "params": {"keys": ["command", "c"]}}"""
        action = parse_llm_response(response)

        assert action.action == "hotkey"
        assert action.params["keys"] == ["command", "c"]

    def test_parse_scroll_action(self):
        """Test parsing a scroll action."""
        response = """{"thought": "Scroll down", "action": "scroll", "params": {"direction": "down", "amount": 5}}"""
        action = parse_llm_response(response)

        assert action.action == "scroll"
        assert action.params["direction"] == "down"
        assert action.params["amount"] == 5

    def test_parse_done_action(self):
        """Test parsing a done action."""
        response = """{"thought": "Task complete", "action": "done", "params": {"result": "Successfully completed", "success": true}}"""
        action = parse_llm_response(response)

        assert action.action == "done"
        assert action.params["success"] is True
        assert "Successfully" in action.params["result"]

    def test_parse_with_markdown_wrapper(self):
        """Test parsing JSON wrapped in markdown code block."""
        response = """
        Here's my analysis:
        ```json
        {"thought": "Click button", "action": "click", "params": {"x": 100, "y": 200}}
        ```
        """
        action = parse_llm_response(response)

        assert action.action == "click"
        assert action.params["x"] == 100

    def test_parse_invalid_json(self):
        """Test that invalid JSON raises ParseError."""
        response = "This is not valid JSON at all"

        with pytest.raises(ParseError) as exc_info:
            parse_llm_response(response)

        assert "No JSON found" in str(exc_info.value)

    def test_parse_missing_action_field(self):
        """Test that missing action field raises ParseError."""
        response = """{"thought": "thinking", "params": {}}"""

        with pytest.raises(ParseError) as exc_info:
            parse_llm_response(response)

        assert "Missing 'action'" in str(exc_info.value)

    def test_parse_unknown_action(self):
        """Test that unknown action raises ParseError."""
        response = """{"thought": "test", "action": "unknown_action", "params": {}}"""

        with pytest.raises(ParseError) as exc_info:
            parse_llm_response(response)

        assert "Unknown action" in str(exc_info.value)

    def test_parse_action_must_be_string(self):
        """Test that non-string action raises ParseError."""
        response = """{"thought": "test", "action": 123, "params": {"x": 1, "y": 2}}"""

        with pytest.raises(ParseError) as exc_info:
            parse_llm_response(response)

        assert "action" in str(exc_info.value).lower()

    def test_parse_params_must_be_object(self):
        """Test that non-object params raises ParseError."""
        response = """{"thought": "test", "action": "click", "params": ["x", "y"]}"""

        with pytest.raises(ParseError) as exc_info:
            parse_llm_response(response)

        assert "params" in str(exc_info.value).lower()

    def test_parse_with_trailing_braces_text(self):
        """Test parsing valid JSON followed by extra text containing braces."""
        response = (
            '{"thought": "Done", "action": "done", "params": {"result": "ok"}}\n'
            "Note: {}"
        )
        action = parse_llm_response(response)

        assert action.action == "done"
        assert action.params["result"] == "ok"


class TestValidateActionParams:
    """Tests for action parameter validation."""

    def test_validate_click_valid(self):
        """Test valid click parameters."""
        action = ParsedAction(
            thought="test",
            action="click",
            params={"x": 100, "y": 200},
            raw_response="",
        )
        valid, error = validate_action_params(action)

        assert valid is True
        assert error is None

    def test_validate_click_missing_coordinate(self):
        """Test click with missing coordinate."""
        action = ParsedAction(
            thought="test",
            action="click",
            params={"x": 100},  # Missing y
            raw_response="",
        )
        valid, error = validate_action_params(action)

        assert valid is False
        assert "Missing required parameter 'y'" in error

    def test_validate_click_invalid_coordinate_type(self):
        """Test click with non-integer coordinates."""
        action = ParsedAction(
            thought="test",
            action="click",
            params={"x": "100", "y": 200},  # x is string
            raw_response="",
        )
        valid, error = validate_action_params(action)

        assert valid is False
        assert "integers" in error.lower()

    def test_validate_type_valid(self):
        """Test valid type parameters."""
        action = ParsedAction(
            thought="test",
            action="type",
            params={"text": "hello"},
            raw_response="",
        )
        valid, error = validate_action_params(action)

        assert valid is True

    def test_validate_type_missing_text(self):
        """Test type with missing text."""
        action = ParsedAction(
            thought="test",
            action="type",
            params={},
            raw_response="",
        )
        valid, error = validate_action_params(action)

        assert valid is False
        assert "text" in error

    def test_validate_hotkey_valid(self):
        """Test valid hotkey parameters."""
        action = ParsedAction(
            thought="test",
            action="hotkey",
            params={"keys": ["command", "v"]},
            raw_response="",
        )
        valid, error = validate_action_params(action)

        assert valid is True

    def test_validate_hotkey_keys_not_list(self):
        """Test hotkey with keys not as list."""
        action = ParsedAction(
            thought="test",
            action="hotkey",
            params={"keys": "command+v"},
            raw_response="",
        )
        valid, error = validate_action_params(action)

        assert valid is False
        assert "list" in error.lower()

    def test_validate_scroll_valid(self):
        """Test valid scroll parameters."""
        action = ParsedAction(
            thought="test",
            action="scroll",
            params={"direction": "up"},
            raw_response="",
        )
        valid, error = validate_action_params(action)

        assert valid is True

    def test_validate_scroll_invalid_direction(self):
        """Test scroll with invalid direction."""
        action = ParsedAction(
            thought="test",
            action="scroll",
            params={"direction": "diagonal"},
            raw_response="",
        )
        valid, error = validate_action_params(action)

        assert valid is False
        assert "Direction" in error


# =============================================================================
# Memory Tests
# =============================================================================


class TestAgentMemory:
    """Tests for agent memory management."""

    def test_add_message(self):
        """Test adding messages to memory."""
        memory = AgentMemory()
        memory.add_message("user", "Hello")
        memory.add_message("assistant", "Hi there")

        assert len(memory.messages) == 2
        assert memory.messages[0]["role"] == "user"
        assert memory.messages[1]["content"] == "Hi there"

    def test_message_trimming(self):
        """Test that old messages are trimmed when limit exceeded."""
        memory = AgentMemory(max_messages=3)

        for i in range(5):
            memory.add_message("user", f"Message {i}")

        assert len(memory.messages) == 3
        assert memory.messages[-1]["content"] == "Message 4"

    def test_add_action(self):
        """Test adding action records."""
        memory = AgentMemory()
        action = ParsedAction(
            thought="test",
            action="click",
            params={"x": 100, "y": 200},
            raw_response="",
        )

        memory.add_action(action, success=True, message="Clicked successfully")

        assert len(memory.actions) == 1
        assert memory.actions[0].success is True
        assert memory.total_actions == 1
        assert memory.successful_actions == 1

    def test_add_screenshot(self):
        """Test adding screenshots to memory."""
        memory = AgentMemory(max_screenshots=2)

        for i in range(3):
            img = Image.new("RGB", (100, 100), color=f"#{i:02x}{i:02x}{i:02x}")
            memory.add_screenshot(img)

        assert len(memory.screenshots) == 2

    def test_get_action_summary(self):
        """Test getting action summary."""
        memory = AgentMemory()
        action = ParsedAction(
            thought="test",
            action="click",
            params={"x": 100, "y": 200},
            raw_response="",
        )
        memory.add_action(action, success=True, message="Clicked")

        summary = memory.get_action_summary()

        assert "click" in summary
        assert "✓" in summary

    def test_clear(self):
        """Test clearing memory."""
        memory = AgentMemory()
        memory.add_message("user", "test")
        memory.add_action(
            ParsedAction("", "click", {"x": 0, "y": 0}, ""),
            success=True,
        )

        memory.clear()

        assert len(memory.messages) == 0
        assert len(memory.actions) == 0

    def test_get_conversation_for_llm(self):
        """Test getting conversation formatted for LLM."""
        memory = AgentMemory()
        memory.add_message("user", "test1")
        memory.add_message("assistant", "test2")

        conversation = memory.get_conversation_for_llm()

        assert len(conversation) == 2
        # Should be a copy, not the original
        conversation.append({"role": "test"})
        assert len(memory.messages) == 2


# =============================================================================
# Agent Tests
# =============================================================================


class TestAgent:
    """Tests for the main Agent class."""

    @pytest.fixture
    def mock_llm_client(self):
        """Create a mock LLM client."""
        client = MagicMock()
        client.analyze_screen.return_value = LLMResponse(
            content='{"thought": "Done", "action": "done", "params": {"result": "Task complete", "success": true}}'
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
        assert agent.config.max_steps == 50

    def test_agent_with_custom_config(self, mock_llm_client):
        """Test agent with custom configuration."""
        config = AgentConfig(max_steps=10, use_grid=False)
        agent = Agent(mock_llm_client, config=config)

        assert agent.config.max_steps == 10
        assert agent.config.use_grid is False

    @patch("odin.agent.core.Screen")
    def test_agent_run_immediate_done(
        self, mock_screen_class, mock_llm_client, mock_screenshot
    ):
        """Test agent run that immediately completes."""
        # Setup mocks
        mock_screen = MagicMock()
        mock_screen.get_screenshot.return_value = mock_screenshot
        mock_screen_class.return_value = mock_screen

        agent = Agent(mock_llm_client)
        result = agent.run("Test task")

        assert result.success is True
        assert result.message == "Task complete"
        assert agent.status == AgentStatus.COMPLETED

    @patch("odin.agent.core.Screen")
    def test_agent_run_with_click(
        self, mock_screen_class, mock_llm_client, mock_screenshot
    ):
        """Test agent run with click action then done."""
        mock_screen = MagicMock()
        mock_screen.get_screenshot.return_value = mock_screenshot
        mock_screen_class.return_value = mock_screen

        # First call returns click, second returns done
        mock_llm_client.analyze_screen.side_effect = [
            LLMResponse(
                content='{"thought": "Click button", "action": "click", "params": {"x": 500, "y": 300}}'
            ),
            LLMResponse(
                content='{"thought": "Done", "action": "done", "params": {"result": "Clicked and done", "success": true}}'
            ),
        ]

        with patch.object(Agent, "_execute_action") as mock_execute:
            mock_execute.return_value = ActionResult(
                success=True, action="click", message="Clicked"
            )

            agent = Agent(mock_llm_client)
            result = agent.run("Click test")

        assert result.success is True
        assert result.total_steps == 2
        assert mock_execute.called

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
                content='{"thought": "Click button", "action": "click", "params": {"x": 500, "y": 300}}'
            ),
            LLMResponse(
                content='{"thought": "Done", "action": "done", "params": {"result": "Clicked and done", "success": true}}'
            ),
        ]

        with (
            patch.object(Agent, "_execute_action") as mock_execute,
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

        # Always return click (never done)
        mock_llm_client.analyze_screen.return_value = LLMResponse(
            content='{"thought": "Keep clicking", "action": "click", "params": {"x": 100, "y": 100}}'
        )

        with patch.object(Agent, "_execute_action") as mock_execute:
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

        # First response is invalid, second is done
        mock_llm_client.analyze_screen.side_effect = [
            LLMResponse(content="This is not valid JSON"),
            LLMResponse(
                content='{"thought": "Done", "action": "done", "params": {"result": "Done", "success": true}}'
            ),
        ]

        agent = Agent(mock_llm_client)
        result = agent.run("Parse error test")

        assert result.success is True
        assert result.total_steps == 2  # Continued after parse error

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
                    content='{"thought": "Click", "action": "click", "params": {"x": 100, "y": 100}}'
                ),
                LLMResponse(
                    content='{"thought": "Done", "action": "done", "params": {"result": "Done", "success": true}}'
                ),
            ]

            with patch.object(Agent, "_execute_action") as mock_execute:
                mock_execute.return_value = ActionResult(success=True, action="click")

                agent = Agent(mock_llm_client, on_step=on_step)
                agent.run("Callback test")

        assert len(callback_calls) == 1
        assert callback_calls[0] == (1, "click")
