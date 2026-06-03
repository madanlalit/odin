"""Parser for LLM responses to extract actions."""

import json
import re
from dataclasses import dataclass
from typing import Any

from odin.action.keys import normalize_keys
from odin.agent.actions import VALID_ACTIONS, ActionKind

ActionType = ActionKind

CONTROL_FIELDS: set[str] = {"action", "params", "thought"}


@dataclass
class ParsedAction:
    """A parsed action from LLM output."""

    thought: str
    action: ActionType
    params: dict[str, Any]
    raw_response: str

    def __post_init__(self) -> None:
        self.action = ActionKind(self.action)


class ParseError(Exception):
    """Error parsing LLM response."""


def _extract_json_object(response: str) -> dict[str, Any]:
    """Extract the most likely JSON object from model output text."""
    decoder = json.JSONDecoder()

    stripped = response.strip()
    if stripped.startswith("{"):
        try:
            parsed, _ = decoder.raw_decode(stripped)
            if isinstance(parsed, dict):
                return parsed
        except json.JSONDecodeError:
            pass

    parsed_objects: list[dict[str, Any]] = []
    first_decode_error: json.JSONDecodeError | None = None
    found_json_start = False

    for match in re.finditer(r"\{", response):
        found_json_start = True
        candidate = response[match.start() :]
        try:
            parsed, _ = decoder.raw_decode(candidate)
        except json.JSONDecodeError as exc:
            if first_decode_error is None:
                first_decode_error = exc
            continue

        if isinstance(parsed, dict):
            parsed_objects.append(parsed)

    if not parsed_objects:
        if found_json_start and first_decode_error is not None:
            raise ParseError(f"Invalid JSON: {first_decode_error}") from first_decode_error
        raise ParseError(f"No JSON found in response: {response[:200]}")

    for parsed in parsed_objects:
        if "actions" in parsed or "action" in parsed:
            return parsed

    return parsed_objects[0]


def _parse_action_object(
    data: dict[str, Any],
    *,
    raw_response: str,
    parent_thought: str = "",
) -> ParsedAction:
    """Parse one action object into a ParsedAction."""
    if "action" not in data:
        keys = [k for k in data if k not in CONTROL_FIELDS]
        if len(keys) == 1 and keys[0] in VALID_ACTIONS:
            action_type = keys[0]
            val = data[action_type]
            if isinstance(val, dict):
                data = {
                    "action": action_type,
                    "params": val,
                    **{k: v for k, v in data.items() if k in CONTROL_FIELDS}
                }
            elif isinstance(val, list) and action_type == "hotkey":
                data = {
                    "action": action_type,
                    "params": {"keys": val},
                    **{k: v for k, v in data.items() if k in CONTROL_FIELDS}
                }
            elif isinstance(val, (int, float)) and action_type == "wait":
                data = {
                    "action": action_type,
                    "params": {"seconds": val},
                    **{k: v for k, v in data.items() if k in CONTROL_FIELDS}
                }
            elif isinstance(val, str):
                if action_type == "type":
                    data = {
                        "action": action_type,
                        "params": {"text": val},
                        **{k: v for k, v in data.items() if k in CONTROL_FIELDS}
                    }
                elif action_type in ("click_element", "double_click_element", "focus_element", "press_element"):
                    data = {
                        "action": action_type,
                        "params": {"element_id": val},
                        **{k: v for k, v in data.items() if k in CONTROL_FIELDS}
                    }
                elif action_type == "scroll":
                    data = {
                        "action": action_type,
                        "params": {"direction": val},
                        **{k: v for k, v in data.items() if k in CONTROL_FIELDS}
                    }

    if "action" not in data:
        raise ParseError("Missing 'action' field in response")

    action_value = data["action"]
    if not isinstance(action_value, str):
        raise ParseError("Field 'action' must be a string")

    action = action_value.lower()

    if action not in VALID_ACTIONS:
        raise ParseError(f"Unknown action: {action}. Valid: {list(VALID_ACTIONS)}")

    params = data.get("params", {})
    if not isinstance(params, dict):
        raise ParseError("Field 'params' must be an object")
    params = params.copy()
    for key, value in data.items():
        if key not in CONTROL_FIELDS and key not in params:
            params[key] = value

    element_actions = {
        "click_element",
        "double_click_element",
        "focus_element",
        "press_element",
        "scroll_element",
        "set_text",
    }
    if action in element_actions and "element_id" not in params and "id" in params:
        params["element_id"] = params["id"]
    if action == "hotkey" and isinstance(params.get("keys"), list):
        keys = params["keys"]
        if all(isinstance(key, str) for key in keys):
            params["keys"] = normalize_keys(keys)

    return ParsedAction(
        thought=str(data.get("thought", parent_thought)),
        action=ActionKind(action),
        params=params,
        raw_response=raw_response,
    )


def parse_llm_actions(
    response: str,
    *,
    max_actions: int = 5,
) -> list[ParsedAction]:
    """
    Parse the batch-only LLM action response.

    Responses must use:
    {
        "thought": "short reasoning",
        "actions": [
            {"action": "hotkey", "params": {"keys": ["command", "l"]}},
            {"action": "type", "params": {"text": "example.com"}}
        ]
    }
    """
    data = _extract_json_object(response)
    if "actions" not in data:
        raise ParseError("Missing 'actions' field in response")

    actions = data["actions"]
    if not isinstance(actions, list):
        raise ParseError("Field 'actions' must be a list")
    if not actions:
        raise ParseError("Field 'actions' must contain at least one action")
    if len(actions) > max_actions:
        raise ParseError(f"Too many actions: {len(actions)} > {max_actions}")

    parent_thought = str(data.get("thought", ""))
    parsed_actions: list[ParsedAction] = []
    for index, item in enumerate(actions, start=1):
        if not isinstance(item, dict):
            raise ParseError(f"Action #{index} must be an object")
        parsed_actions.append(
            _parse_action_object(
                item,
                raw_response=response,
                parent_thought=parent_thought,
            )
        )

    return parsed_actions


def validate_action_params(action: ParsedAction) -> tuple[bool, str | None]:
    """
    Validate that an action has the required parameters.

    Args:
        action: The parsed action to validate

    Returns:
        Tuple of (is_valid, error_message)
    """
    required_params: dict[str, list[str]] = {
        "click": ["x", "y"],
        "click_element": ["element_id"],
        "double_click": ["x", "y"],
        "double_click_element": ["element_id"],
        "drag": ["start_x", "start_y", "end_x", "end_y"],
        "focus_element": ["element_id"],
        "move": ["x", "y"],
        "press_element": ["element_id"],
        "type": ["text"],
        "set_text": ["element_id", "text"],
        "hotkey": ["keys"],
        "scroll": ["direction"],
        "scroll_element": ["element_id", "direction"],
        "wait": ["seconds"],
        "done": ["result"],
    }

    required = required_params.get(action.action, [])

    for param in required:
        if param not in action.params:
            return False, f"Missing required parameter '{param}' for {action.action}"

    if action.action in ("click", "double_click", "move"):
        x = action.params.get("x")
        y = action.params.get("y")
        if not isinstance(x, int) or not isinstance(y, int):
            return False, "Coordinates x and y must be integers"

    if action.action == "drag":
        for param in ("start_x", "start_y", "end_x", "end_y"):
            val = action.params.get(param)
            if not isinstance(val, int):
                return False, f"Coordinate {param} must be an integer"

    if action.action == "hotkey":
        keys = action.params.get("keys")
        if not isinstance(keys, list):
            return False, "Keys must be a list"
        if not all(isinstance(key, str) for key in keys):
            return False, "Keys must be a list of strings"
        action.params["keys"] = normalize_keys(keys)

    if action.action == "scroll":
        direction = action.params.get("direction", "").lower()
        if direction not in ("up", "down", "left", "right"):
            return False, "Direction must be 'up', 'down', 'left', or 'right'"

    if action.action == "scroll_element":
        direction = action.params.get("direction", "").lower()
        if direction not in ("up", "down", "left", "right"):
            return False, "Direction must be 'up', 'down', 'left', or 'right'"

    return True, None
