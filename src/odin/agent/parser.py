"""Parser for LLM responses to extract actions."""

import json
import re
from dataclasses import dataclass
from typing import Any, Literal


ActionType = Literal[
    "click",
    "double_click",
    "move",
    "type",
    "hotkey",
    "scroll",
    "wait",
    "done",
]


@dataclass
class ParsedAction:
    """A parsed action from LLM output."""

    thought: str
    action: ActionType
    params: dict[str, Any]
    raw_response: str


class ParseError(Exception):
    """Error parsing LLM response."""

    pass


def _extract_json_object(response: str) -> dict[str, Any]:
    """Extract the most likely JSON object from model output text."""
    decoder = json.JSONDecoder()
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
        if "action" in parsed:
            return parsed

    return parsed_objects[0]


def parse_llm_response(response: str) -> ParsedAction:
    """
    Parse the LLM response to extract the action.

    The LLM is expected to return JSON in this format:
    {
        "thought": "reasoning about what to do",
        "action": "action_name",
        "params": { ... }
    }

    Args:
        response: Raw LLM response text

    Returns:
        ParsedAction with extracted action details

    Raises:
        ParseError: If the response cannot be parsed
    """
    data = _extract_json_object(response)

    # Validate required fields
    if "action" not in data:
        raise ParseError("Missing 'action' field in response")

    action_value = data["action"]
    if not isinstance(action_value, str):
        raise ParseError("Field 'action' must be a string")

    action = action_value.lower()
    valid_actions = [
        "click",
        "double_click",
        "move",
        "type",
        "hotkey",
        "scroll",
        "wait",
        "done",
    ]

    if action not in valid_actions:
        raise ParseError(f"Unknown action: {action}. Valid: {valid_actions}")

    params = data.get("params", {})
    if not isinstance(params, dict):
        raise ParseError("Field 'params' must be an object")

    return ParsedAction(
        thought=str(data.get("thought", "")),
        action=action,  # type: ignore
        params=params,
        raw_response=response,
    )


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
        "double_click": ["x", "y"],
        "move": ["x", "y"],
        "type": ["text"],
        "hotkey": ["keys"],
        "scroll": ["direction"],
        "wait": ["seconds"],
        "done": ["result"],
    }

    required = required_params.get(action.action, [])

    for param in required:
        if param not in action.params:
            return False, f"Missing required parameter '{param}' for {action.action}"

    # Type-specific validation
    if action.action in ("click", "double_click", "move"):
        x = action.params.get("x")
        y = action.params.get("y")
        if not isinstance(x, int) or not isinstance(y, int):
            return False, "Coordinates x and y must be integers"

    if action.action == "hotkey":
        keys = action.params.get("keys")
        if not isinstance(keys, list):
            return False, "Keys must be a list"

    if action.action == "scroll":
        direction = action.params.get("direction", "").lower()
        if direction not in ("up", "down", "left", "right"):
            return False, "Direction must be 'up', 'down', 'left', or 'right'"

    return True, None
