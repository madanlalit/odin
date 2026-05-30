"""Tests for the LLM response parser."""

import json

import pytest

from odin.agent.parser import (
    VALID_ACTIONS,
    ParsedAction,
    ParseError,
    parse_llm_actions,
    validate_action_params,
)
from odin.llm.prompts import SYSTEM_PROMPT, build_system_prompt


def _action(name: str, params: dict | None = None, thought: str | None = None) -> dict:
    """Build a test action object."""
    item = {"action": name, "params": params or {}}
    if thought is not None:
        item["thought"] = thought
    return item


def _batch_response(*actions: dict, thought: str = "test") -> str:
    """Build a batch-only LLM response."""
    return json.dumps({"thought": thought, "actions": list(actions)})


class TestParser:
    """Tests for the LLM response parser."""

    def test_system_prompt_lists_all_registered_actions(self):
        """Prompt action list stays aligned with parser registration."""
        missing = [
            action for action in VALID_ACTIONS if f"- {action}:" not in SYSTEM_PROMPT
        ]

        assert missing == []

    def test_built_system_prompt_lists_all_registered_actions(self):
        """Built prompt action list stays aligned with parser registration."""
        prompt = build_system_prompt(max_batch_actions=5)
        missing = [action for action in VALID_ACTIONS if f"- {action}:" not in prompt]

        assert missing == []

    def test_parse_valid_click_action(self):
        """Test parsing a valid click action."""
        response = _batch_response(
            _action("click", {"x": 500, "y": 300}),
            thought="I see a button at coordinates (500, 300)",
        )
        action = parse_llm_actions(response)[0]

        assert action.action == "click"
        assert action.params["x"] == 500
        assert action.params["y"] == 300
        assert "button" in action.thought.lower()

    def test_parse_click_with_button(self):
        """Test parsing click with specific button."""
        response = _batch_response(
            _action("click", {"x": 100, "y": 200, "button": "right"}),
            thought="Right click",
        )
        action = parse_llm_actions(response)[0]

        assert action.action == "click"
        assert action.params["button"] == "right"

    def test_parse_click_element_action(self):
        """Test parsing an accessibility element click action."""
        response = _batch_response(
            _action("click_element", {"id": "ax_12"}),
            thought="Click Submit",
        )
        action = parse_llm_actions(response)[0]

        assert action.action == "click_element"
        assert action.params["element_id"] == "ax_12"

    def test_parse_action_batch(self):
        """Test parsing a bounded action batch."""
        response = """
        {
            "thought": "Focus and type",
            "actions": [
                {"action": "hotkey", "params": {"keys": ["command", "l"]}},
                {"action": "type", "params": {"text": "example.com"}}
            ]
        }
        """

        actions = parse_llm_actions(response, max_actions=3)

        assert [action.action for action in actions] == ["hotkey", "type"]
        assert actions[0].thought == "Focus and type"
        assert actions[1].params["text"] == "example.com"

    def test_parse_top_level_action_params_and_normalizes_hotkeys(self):
        """Trace-style top-level args are preserved and key aliases normalize."""
        response = """
        {
            "thought": "Open Spotlight",
            "actions": [
                {"action": "hotkey", "keys": ["cmd", "space"]},
                {"action": "wait", "seconds": 0.5},
                {"action": "type", "text": "Calculator"}
            ]
        }
        """

        actions = parse_llm_actions(response, max_actions=3)

        assert actions[0].params == {"keys": ["command", "space"]}
        assert actions[1].params == {"seconds": 0.5}
        assert actions[2].params == {"text": "Calculator"}

    def test_parse_single_action_shape_rejected(self):
        """Test single-action responses are rejected."""
        response = """{"thought": "Wait", "action": "wait", "params": {"seconds": 1}}"""

        with pytest.raises(ParseError, match="Missing 'actions'"):
            parse_llm_actions(response)

    def test_parse_action_batch_rejects_too_many_actions(self):
        """Test max batch action limit is enforced."""
        response = """
        {
            "thought": "Too many",
            "actions": [
                {"action": "wait", "params": {"seconds": 1}},
                {"action": "wait", "params": {"seconds": 1}}
            ]
        }
        """

        with pytest.raises(ParseError, match="Too many actions"):
            parse_llm_actions(response, max_actions=1)

    def test_parse_type_action(self):
        """Test parsing a type action."""
        response = _batch_response(
            _action("type", {"text": "hello world"}),
            thought="Type search query",
        )
        action = parse_llm_actions(response)[0]

        assert action.action == "type"
        assert action.params["text"] == "hello world"

    def test_parse_hotkey_action(self):
        """Test parsing a hotkey action."""
        response = _batch_response(
            _action("hotkey", {"keys": ["command", "c"]}),
            thought="Copy text",
        )
        action = parse_llm_actions(response)[0]

        assert action.action == "hotkey"
        assert action.params["keys"] == ["command", "c"]

    def test_parse_scroll_action(self):
        """Test parsing a scroll action."""
        response = _batch_response(
            _action("scroll", {"direction": "down", "amount": 5}),
            thought="Scroll down",
        )
        action = parse_llm_actions(response)[0]

        assert action.action == "scroll"
        assert action.params["direction"] == "down"
        assert action.params["amount"] == 5

    def test_parse_done_action(self):
        """Test parsing a done action."""
        response = _batch_response(
            _action("done", {"result": "Successfully completed", "success": True}),
            thought="Task complete",
        )
        action = parse_llm_actions(response)[0]

        assert action.action == "done"
        assert action.params["success"] is True
        assert "Successfully" in action.params["result"]

    def test_parse_drag_action(self):
        """Test parsing a drag action."""
        response = _batch_response(
            _action("drag", {"start_x": 100, "start_y": 200, "end_x": 300, "end_y": 400}),
            thought="Drag from start to end",
        )
        action = parse_llm_actions(response)[0]

        assert action.action == "drag"
        assert action.params["start_x"] == 100
        assert action.params["start_y"] == 200
        assert action.params["end_x"] == 300
        assert action.params["end_y"] == 400

    def test_parse_with_markdown_wrapper(self):
        """Test parsing JSON wrapped in markdown code block."""
        response = """
        Here's my analysis:
        ```json
        {"thought": "Click button", "actions": [{"action": "click", "params": {"x": 100, "y": 200}}]}
        ```
        """
        action = parse_llm_actions(response)[0]

        assert action.action == "click"
        assert action.params["x"] == 100

    def test_parse_invalid_json(self):
        """Test that invalid JSON raises ParseError."""
        response = "This is not valid JSON at all"

        with pytest.raises(ParseError) as exc_info:
            parse_llm_actions(response)

        assert "No JSON found" in str(exc_info.value)

    def test_parse_missing_action_field(self):
        """Test that missing action field raises ParseError."""
        response = """{"thought": "thinking", "actions": [{}]}"""

        with pytest.raises(ParseError) as exc_info:
            parse_llm_actions(response)

        assert "Missing 'action'" in str(exc_info.value)

    def test_parse_unknown_action(self):
        """Test that unknown action raises ParseError."""
        response = """{"thought": "test", "actions": [{"action": "unknown_action", "params": {}}]}"""

        with pytest.raises(ParseError) as exc_info:
            parse_llm_actions(response)

        assert "Unknown action" in str(exc_info.value)

    def test_parse_action_must_be_string(self):
        """Test that non-string action raises ParseError."""
        response = """{"thought": "test", "actions": [{"action": 123, "params": {"x": 1, "y": 2}}]}"""

        with pytest.raises(ParseError) as exc_info:
            parse_llm_actions(response)

        assert "action" in str(exc_info.value).lower()

    def test_parse_params_must_be_object(self):
        """Test that non-object params raises ParseError."""
        response = """{"thought": "test", "actions": [{"action": "click", "params": ["x", "y"]}]}"""

        with pytest.raises(ParseError) as exc_info:
            parse_llm_actions(response)

        assert "params" in str(exc_info.value).lower()

    def test_parse_with_trailing_braces_text(self):
        """Test parsing valid JSON followed by extra text containing braces."""
        response = (
            '{"thought": "Done", "actions": [{"action": "done", "params": {"result": "ok"}}]}\n'
            "Note: {}"
        )
        action = parse_llm_actions(response)[0]

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
            params={"x": 100},
            raw_response="",
        )
        valid, error = validate_action_params(action)

        assert valid is False
        assert error is not None
        assert "Missing required parameter 'y'" in error

    def test_validate_click_invalid_coordinate_type(self):
        """Test click with non-integer coordinates."""
        action = ParsedAction(
            thought="test",
            action="click",
            params={"x": "100", "y": 200},
            raw_response="",
        )
        valid, error = validate_action_params(action)

        assert valid is False
        assert error is not None
        assert "integers" in error.lower()

    def test_validate_type_valid(self):
        """Test valid type parameters."""
        action = ParsedAction(
            thought="test",
            action="type",
            params={"text": "hello"},
            raw_response="",
        )
        valid, _ = validate_action_params(action)

        assert valid is True

    def test_validate_set_text_valid(self):
        """Test valid accessibility set_text parameters."""
        action = ParsedAction(
            thought="test",
            action="set_text",
            params={"element_id": "ax_4", "text": "hello"},
            raw_response="",
        )
        valid, error = validate_action_params(action)

        assert valid is True
        assert error is None

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
        assert error is not None
        assert "text" in error

    def test_validate_hotkey_valid(self):
        """Test valid hotkey parameters."""
        action = ParsedAction(
            thought="test",
            action="hotkey",
            params={"keys": ["command", "v"]},
            raw_response="",
        )
        valid, _ = validate_action_params(action)

        assert valid is True

    def test_validate_hotkey_normalizes_aliases(self):
        """Test hotkey key aliases are normalized during validation."""
        action = ParsedAction(
            thought="test",
            action="hotkey",
            params={"keys": ["cmd", "control", "space"]},
            raw_response="",
        )
        valid, error = validate_action_params(action)

        assert valid is True
        assert error is None
        assert action.params["keys"] == ["command", "ctrl", "space"]

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
        assert error is not None
        assert "list" in error.lower()

    def test_validate_scroll_valid(self):
        """Test valid scroll parameters."""
        action = ParsedAction(
            thought="test",
            action="scroll",
            params={"direction": "up"},
            raw_response="",
        )
        valid, _ = validate_action_params(action)

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
        assert error is not None
        assert "Direction" in error

    def test_validate_drag_valid(self):
        """Test valid drag parameters."""
        action = ParsedAction(
            thought="test",
            action="drag",
            params={"start_x": 10, "start_y": 20, "end_x": 30, "end_y": 40},
            raw_response="",
        )
        valid, error = validate_action_params(action)

        assert valid is True
        assert error is None

    def test_validate_drag_missing_coordinate(self):
        """Test drag with missing coordinate."""
        action = ParsedAction(
            thought="test",
            action="drag",
            params={"start_x": 10, "start_y": 20, "end_x": 30},
            raw_response="",
        )
        valid, error = validate_action_params(action)

        assert valid is False
        assert error is not None
        assert "Missing required parameter 'end_y'" in error

    def test_validate_drag_invalid_coordinate_type(self):
        """Test drag with non-integer coordinates."""
        action = ParsedAction(
            thought="test",
            action="drag",
            params={"start_x": 10, "start_y": "20", "end_x": 30, "end_y": 40},
            raw_response="",
        )
        valid, error = validate_action_params(action)

        assert valid is False
        assert error is not None
        assert "integer" in error.lower()
