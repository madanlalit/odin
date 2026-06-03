"""Map screenshot-coordinate actions to screen coordinates.

LLM responses are produced against a (possibly compressed) screenshot, but
the platform backend expects screen points. This module performs the
linear mapping and reports the substitutions made so the loop can record
them in the structured trace.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any

from odin.agent.actions import ActionKind
from odin.agent.parser import ParsedAction


@dataclass(frozen=True)
class CoordinateMapping:
    """A single ``(screenshot, screen)`` coordinate pair after mapping."""

    x_key: str
    y_key: str
    input_x: int
    input_y: int
    mapped_x: int
    mapped_y: int


_KEY_ACTIONS: frozenset[ActionKind] = frozenset(
    {ActionKind.CLICK, ActionKind.DOUBLE_CLICK, ActionKind.MOVE}
)

_DRAG_KEYS: tuple[tuple[str, str], ...] = (
    ("start_x", "start_y"),
    ("end_x", "end_y"),
)

_CLICK_KEYS: tuple[tuple[str, str], ...] = (("x", "y"),)

_SCROLL_KEYS: tuple[tuple[str, str], ...] = (("x", "y"),)


def _keys_for(action_kind: ActionKind) -> tuple[tuple[str, str], ...] | None:
    if action_kind in _KEY_ACTIONS:
        return _CLICK_KEYS
    if action_kind == ActionKind.DRAG:
        return _DRAG_KEYS
    if action_kind == ActionKind.SCROLL:
        return _SCROLL_KEYS
    return None


def map_action_coordinates(
    action: ParsedAction,
    *,
    screenshot_size: tuple[int, int] | None,
    screen_width: int,
    screen_height: int,
) -> tuple[ParsedAction, list[CoordinateMapping]]:
    """Map an action's raw coordinates from screenshot to screen space.

    Returns the (possibly mutated) action and the list of mappings that
    were applied. When the input is non-coordinate, or the size is unknown,
    the action is returned unchanged with an empty mapping list.
    """
    keys = _keys_for(action.action)
    if keys is None:
        return action, []

    if screenshot_size is None or screen_width <= 0 or screen_height <= 0:
        return action, []

    screenshot_width, screenshot_height = screenshot_size
    if screenshot_width <= 0 or screenshot_height <= 0:
        return action, []

    mapped_params: dict[str, Any] = dict(action.params)
    mappings: list[CoordinateMapping] = []
    for x_key, y_key in keys:
        x = mapped_params.get(x_key)
        y = mapped_params.get(y_key)
        if not isinstance(x, int) or not isinstance(y, int):
            continue

        mapped_x = round(x * screen_width / screenshot_width)
        mapped_y = round(y * screen_height / screenshot_height)
        mapped_params[x_key] = mapped_x
        mapped_params[y_key] = mapped_y
        mappings.append(
            CoordinateMapping(
                x_key=x_key,
                y_key=y_key,
                input_x=x,
                input_y=y,
                mapped_x=mapped_x,
                mapped_y=mapped_y,
            )
        )

    if not mappings:
        return action, []

    mapped_action = ParsedAction(
        thought=action.thought,
        action=action.action,
        params=mapped_params,
        raw_response=action.raw_response,
    )
    return mapped_action, mappings


__all__ = ["CoordinateMapping", "map_action_coordinates"]
