"""Action types the agent can dispatch.

Centralised as a :class:`StrEnum` so the parser, executor, safety layer, and
prompt share a single source of truth. Because every member is a string, JSON
input and ``str.lower()`` round-trips keep working unchanged.
"""

from __future__ import annotations

from enum import StrEnum


class ActionKind(StrEnum):
    """All action names the agent understands."""

    CLICK = "click"
    DOUBLE_CLICK = "double_click"
    DRAG = "drag"
    MOVE = "move"
    TYPE = "type"
    HOTKEY = "hotkey"
    SCROLL = "scroll"
    CLICK_ELEMENT = "click_element"
    DOUBLE_CLICK_ELEMENT = "double_click_element"
    FOCUS_ELEMENT = "focus_element"
    PRESS_ELEMENT = "press_element"
    SCROLL_ELEMENT = "scroll_element"
    SET_TEXT = "set_text"
    WAIT = "wait"
    DONE = "done"


VALID_ACTIONS: tuple[str, ...] = tuple(member.value for member in ActionKind)


__all__ = ["VALID_ACTIONS", "ActionKind"]
