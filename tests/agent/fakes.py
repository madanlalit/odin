"""Test fakes for the agent.

Replaces ``unittest.mock.MagicMock`` with hand-written fakes so tests
read like the production code they exercise. The fakes are deliberately
small: they record what they were called with and return canned data.
"""

from __future__ import annotations

from collections.abc import Callable
from typing import Any

from PIL import Image

from odin.action.controller import ActionResult
from odin.llm.base import LLMResponse
from odin.perception.accessibility import AccessibilitySnapshot


class FakeLLM:
    """A scripted LLM client.

    ``responses`` is a list of strings or :class:`LLMResponse` objects
    consumed in order. Strings are wrapped with a small usage payload;
    pre-built responses are returned as-is. After the list is exhausted
    the final response is repeated (or ``default_response`` is used) so
    the agent can keep running.
    """

    def __init__(
        self,
        responses: list[str | LLMResponse] | str | LLMResponse | None = None,
        *,
        default_response: str | LLMResponse | None = None,
    ) -> None:
        normalized: list[LLMResponse] = []
        if responses is not None:
            items = responses if isinstance(responses, list) else [responses]
            for item in items:
                if isinstance(item, LLMResponse):
                    normalized.append(item)
                else:
                    normalized.append(self._wrap(item))
        self.responses: list[LLMResponse] = normalized
        if isinstance(default_response, LLMResponse):
            self.default_response: LLMResponse | None = default_response
        elif default_response is not None:
            self.default_response = self._wrap(default_response)
        else:
            self.default_response = None
        self.calls: list[dict[str, Any]] = []
        self.model = "fake-model"
        self.closed = False

    @staticmethod
    def _wrap(content: str) -> LLMResponse:
        return LLMResponse(
            content=content,
            usage={"inputTokens": 1, "outputTokens": 1},
        )

    def analyze_screen(
        self,
        *,
        image: Image.Image,
        task: str,
        system_prompt: str,
        history: list[dict[str, Any]] | None = None,
        screen_context: dict[str, Any] | None = None,
    ) -> LLMResponse:
        self.calls.append({
            "task": task,
            "system_prompt": system_prompt,
            "history": list(history or []),
            "screen_context": screen_context,
            "image_size": image.size,
        })
        if self.responses:
            return self.responses.pop(0)
        if self.default_response is not None:
            return self.default_response
        raise AssertionError("FakeLLM ran out of scripted responses")

    def close(self) -> None:
        self.closed = True


class FakeScreen:
    """Captures a fixed-size screenshot and a canned app context."""

    def __init__(
        self,
        *,
        width: int = 1920,
        height: int = 1080,
        app_context: dict[str, Any] | None = None,
    ) -> None:
        self.width = width
        self.height = height
        self._app_context = app_context or {"frontmost_app": None, "windows": []}
        self.get_screenshot_calls = 0

    def get_screenshot(self) -> Image.Image:
        self.get_screenshot_calls += 1
        return Image.new("RGB", (self.width, self.height), color="white")

    def get_app_context(self) -> dict[str, Any]:
        return self._app_context


class FakeAccessibility:
    """Returns a pre-canned accessibility snapshot and records AX calls."""

    def __init__(
        self,
        snapshot: AccessibilitySnapshot | list[AccessibilitySnapshot] | None = None,
    ) -> None:
        if snapshot is None:
            self._snapshots: list[AccessibilitySnapshot] = [AccessibilitySnapshot(available=False)]
        elif isinstance(snapshot, list):
            self._snapshots = list(snapshot)
        else:
            self._snapshots = [snapshot]
        self.snapshot = self._snapshots[0]
        self.capture_calls = 0
        self.performed_actions: list[tuple[str, str]] = []
        self.focused: list[str] = []
        self.set_values: list[tuple[str, str]] = []
        self._frames: dict[str, Any] = {}

    def capture(self, *, max_depth: int, max_nodes: int) -> AccessibilitySnapshot:  # noqa: ARG002
        self.capture_calls += 1
        if len(self._snapshots) == 1:
            return self._snapshots[0]
        return self._snapshots.pop(0)

    def perform_action(self, element_id: str, action_name: str) -> tuple[bool, str]:
        self.performed_actions.append((element_id, action_name))
        if action_name == "press":
            return True, f"pressed {element_id}"
        return False, f"unsupported action {action_name}"

    def focus(self, element_id: str) -> tuple[bool, str]:
        self.focused.append(element_id)
        return True, f"focused {element_id}"

    def set_value(self, element_id: str, value: str) -> tuple[bool, str]:
        self.set_values.append((element_id, value))
        return True, f"set {element_id}"

    def frame(self, element_id: str):
        return self._frames.get(element_id)

    def set_frame(self, element_id: str, frame) -> None:
        self._frames[element_id] = frame


class FakeActionController:
    """Records calls and returns successful :class:`ActionResult` objects."""

    def __init__(
        self,
        *,
        screen_width: int = 1920,
        screen_height: int = 1080,
        mouse_position: tuple[int, int] = (0, 0),
    ) -> None:
        self.screen_width = screen_width
        self.screen_height = screen_height
        self._mouse_position = mouse_position
        self.calls: list[dict[str, Any]] = []
        self._backend = _FakeBackend(screen_width, screen_height)

    def _record(self, action: str, **kwargs: Any) -> None:
        self.calls.append({"action": action, **kwargs})

    def click(
        self,
        *,
        x: int,
        y: int,
        button: str = "left",
    ) -> ActionResult:
        self._record("click", x=x, y=y, button=button)
        return ActionResult(
            success=True, action="click",
            message=f"Clicked {button} at ({x}, {y})",
        )

    def double_click(self, *, x: int, y: int) -> ActionResult:
        self._record("double_click", x=x, y=y)
        return ActionResult(
            success=True, action="double_click",
            message=f"Double-clicked at ({x}, {y})",
        )

    def move(self, *, x: int, y: int) -> ActionResult:
        self._record("move", x=x, y=y)
        return ActionResult(
            success=True, action="move",
            message=f"Moved to ({x}, {y})",
        )

    def drag(
        self,
        *,
        start_x: int,
        start_y: int,
        end_x: int,
        end_y: int,
        duration: float = 0.5,
    ) -> ActionResult:
        self._record(
            "drag", start_x=start_x, start_y=start_y,
            end_x=end_x, end_y=end_y, duration=duration,
        )
        return ActionResult(
            success=True, action="drag",
            message="Dragged",
        )

    def type_text(self, *, text: str) -> ActionResult:
        self._record("type_text", text=text)
        return ActionResult(success=True, action="type", message=f"Typed: {text}")

    def hotkey(self, *keys: str) -> ActionResult:
        self._record("hotkey", keys=list(keys))
        return ActionResult(
            success=True, action="hotkey",
            message=f"Pressed: {'+'.join(keys)}",
        )

    def scroll(
        self,
        *,
        direction: str,
        clicks: int = 3,
        x: int | None = None,
        y: int | None = None,
    ) -> ActionResult:
        self._record("scroll", direction=direction, clicks=clicks, x=x, y=y)
        return ActionResult(success=True, action="scroll", message="Scrolled")

    def wait(self, *, seconds: float) -> ActionResult:
        self._record("wait", seconds=seconds)
        return ActionResult(success=True, action="wait", message=f"Waited {seconds}s")

    def get_mouse_position(self) -> tuple[int, int]:
        return self._mouse_position

    def find_call(self, action: str) -> dict[str, Any] | None:
        for call in self.calls:
            if call["action"] == action:
                return call
        return None


class _FakeBackend:
    """Minimal platform backend the safety layer can call for screen size."""

    def __init__(self, width: int, height: int) -> None:
        self._width = width
        self._height = height

    def screen_size(self) -> tuple[int, int]:
        return self._width, self._height


def make_failing_action_result(action: str, error: str) -> ActionResult:
    """Build a failure ``ActionResult`` for tests that need it."""
    return ActionResult(success=False, action=action, error=error)


CallableT = Callable[..., Any]
