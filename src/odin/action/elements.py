"""Accessibility element action helpers.

This module bridges the accessibility tree (read-only capture) with the
action controller, providing higher-level element actions that try native
AX operations first and fall back to coordinate-based clicks.
"""

from typing import Literal, cast

from odin.action.controller import ActionController, ActionResult
from odin.action.safety import SafetyController
from odin.perception.accessibility import Accessibility


class ElementActionHandler:
    """Execute actions on accessibility elements with coordinate fallbacks."""

    def __init__(
        self,
        accessibility: Accessibility,
        action_controller: ActionController,
        safety: SafetyController,
    ):
        self.accessibility = accessibility
        self.action_controller = action_controller
        self.safety = safety

    def press_element(self, element_id: str, action_name: str = "press") -> ActionResult:
        """Invoke a native accessibility action, falling back to center click."""
        success, message = self.accessibility.perform_action(element_id, action_name)
        if success:
            return ActionResult(
                success=True,
                action="press_element",
                message=message,
            )

        frame = self.accessibility.frame(element_id)
        if frame is None:
            return ActionResult(
                success=False,
                action="press_element",
                error=message,
            )

        x, y = frame.center
        safe, safety_error = self.safety.validate_coordinates(x, y)
        if not safe:
            return ActionResult(
                success=False,
                action="press_element",
                error=safety_error,
            )

        fallback = self.action_controller.click(x=x, y=y)
        return ActionResult(
            success=fallback.success,
            action="press_element",
            message=f"{message}; fallback {fallback.message}" if fallback.success else None,
            error=None if fallback.success else f"{message}; fallback {fallback.error}",
        )

    def click_element(self, element_id: str, button: str = "left") -> ActionResult:
        """Click an accessibility element center."""
        frame = self.accessibility.frame(element_id)
        if frame is None:
            return ActionResult(
                success=False,
                action="click_element",
                error=f"Unknown or unframed accessibility element: {element_id}",
            )

        x, y = frame.center
        safe, safety_error = self.safety.validate_coordinates(x, y)
        if not safe:
            return ActionResult(
                success=False,
                action="click_element",
                error=safety_error,
            )

        if button not in ("left", "right", "middle"):
            button = "left"
        mouse_button = cast(Literal["left", "right", "middle"], button)
        result = self.action_controller.click(x=x, y=y, button=mouse_button)
        return ActionResult(
            success=result.success,
            action="click_element",
            message=result.message,
            error=result.error,
        )

    def double_click_element(self, element_id: str) -> ActionResult:
        """Double-click an accessibility element center."""
        frame = self.accessibility.frame(element_id)
        if frame is None:
            return ActionResult(
                success=False,
                action="double_click_element",
                error=f"Unknown or unframed accessibility element: {element_id}",
            )

        x, y = frame.center
        safe, safety_error = self.safety.validate_coordinates(x, y)
        if not safe:
            return ActionResult(
                success=False,
                action="double_click_element",
                error=safety_error,
            )

        result = self.action_controller.double_click(x=x, y=y)
        return ActionResult(
            success=result.success,
            action="double_click_element",
            message=result.message,
            error=result.error,
        )

    def focus_element(self, element_id: str) -> ActionResult:
        """Focus an accessibility element, falling back to click."""
        success, message = self.accessibility.focus(element_id)
        if success:
            return ActionResult(
                success=True,
                action="focus_element",
                message=message,
            )

        click_result = self.click_element(element_id)
        return ActionResult(
            success=click_result.success,
            action="focus_element",
            message=f"{message}; fallback {click_result.message}"
            if click_result.success
            else None,
            error=None if click_result.success else f"{message}; fallback {click_result.error}",
        )

    def set_text_element(self, element_id: str, text: str) -> ActionResult:
        """Set text via AX, falling back to focus and typing."""
        success, message = self.accessibility.set_value(element_id, text)
        if success:
            return ActionResult(
                success=True,
                action="set_text",
                message=message,
            )

        focus_result = self.focus_element(element_id)
        if not focus_result.success:
            return ActionResult(
                success=False,
                action="set_text",
                error=f"{message}; fallback {focus_result.error}",
            )

        type_result = self.action_controller.type_text(text)
        return ActionResult(
            success=type_result.success,
            action="set_text",
            message=f"{message}; fallback {type_result.message}"
            if type_result.success
            else None,
            error=None if type_result.success else f"{message}; fallback {type_result.error}",
        )

    def scroll_element(
        self,
        element_id: str,
        *,
        direction: str,
        amount: int = 3,
    ) -> ActionResult:
        """Scroll an element natively or at its center."""
        ax_action = f"scroll_{direction}"
        success, message = self.accessibility.perform_action(element_id, ax_action)
        if success:
            return ActionResult(
                success=True,
                action="scroll_element",
                message=message,
            )

        frame = self.accessibility.frame(element_id)
        if frame is None:
            return ActionResult(
                success=False,
                action="scroll_element",
                error=message,
            )

        x, y = frame.center
        safe, safety_error = self.safety.validate_coordinates(x, y)
        if not safe:
            return ActionResult(
                success=False,
                action="scroll_element",
                error=safety_error,
            )

        result = self.action_controller.scroll(
            direction=direction,  # type: ignore[arg-type]
            clicks=amount,
            x=x,
            y=y,
        )
        return ActionResult(
            success=result.success,
            action="scroll_element",
            message=f"{message}; fallback {result.message}" if result.success else None,
            error=None if result.success else f"{message}; fallback {result.error}",
        )
