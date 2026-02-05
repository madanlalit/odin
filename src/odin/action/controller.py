"""Action controller for GUI automation using pyautogui."""

import time
from dataclasses import dataclass
from typing import Literal

import pyautogui  # type: ignore[import-untyped]

# Configure pyautogui safety features
pyautogui.FAILSAFE = True  # Move mouse to corner to abort
pyautogui.PAUSE = 0.1  # Small pause between actions


@dataclass
class ActionResult:
    """Result of an executed action."""

    success: bool
    action: str
    message: str | None = None
    error: str | None = None


class ActionController:
    """
    Controller for executing GUI actions using pyautogui.

    Provides methods for mouse movements, clicks, keyboard input,
    and other UI interactions.
    """

    def __init__(self):
        """Initialize the action controller."""
        self.screen_width, self.screen_height = pyautogui.size()

    def _validate_coordinates(self, x: int, y: int) -> bool:
        """Check if coordinates are within screen bounds."""
        return 0 <= x < self.screen_width and 0 <= y < self.screen_height

    def click(
        self,
        x: int,
        y: int,
        button: Literal["left", "right", "middle"] = "left",
    ) -> ActionResult:
        """
        Click at the specified coordinates.

        Args:
            x: X coordinate
            y: Y coordinate
            button: Mouse button to click

        Returns:
            ActionResult indicating success or failure
        """
        if not self._validate_coordinates(x, y):
            return ActionResult(
                success=False,
                action="click",
                error=f"Coordinates ({x}, {y}) out of screen bounds",
            )

        try:
            pyautogui.click(x, y, button=button)
            return ActionResult(
                success=True,
                action="click",
                message=f"Clicked {button} at ({x}, {y})",
            )
        except Exception as e:
            return ActionResult(success=False, action="click", error=str(e))

    def double_click(self, x: int, y: int) -> ActionResult:
        """
        Double-click at the specified coordinates.

        Args:
            x: X coordinate
            y: Y coordinate

        Returns:
            ActionResult indicating success or failure
        """
        if not self._validate_coordinates(x, y):
            return ActionResult(
                success=False,
                action="double_click",
                error=f"Coordinates ({x}, {y}) out of screen bounds",
            )

        try:
            pyautogui.doubleClick(x, y)
            return ActionResult(
                success=True,
                action="double_click",
                message=f"Double-clicked at ({x}, {y})",
            )
        except Exception as e:
            return ActionResult(success=False, action="double_click", error=str(e))

    def right_click(self, x: int, y: int) -> ActionResult:
        """
        Right-click at the specified coordinates.

        Args:
            x: X coordinate
            y: Y coordinate

        Returns:
            ActionResult indicating success or failure
        """
        return self.click(x, y, button="right")

    def move(self, x: int, y: int, duration: float = 0.25) -> ActionResult:
        """
        Move the mouse cursor to the specified coordinates.

        Args:
            x: X coordinate
            y: Y coordinate
            duration: Time to take for the movement (seconds)

        Returns:
            ActionResult indicating success or failure
        """
        if not self._validate_coordinates(x, y):
            return ActionResult(
                success=False,
                action="move",
                error=f"Coordinates ({x}, {y}) out of screen bounds",
            )

        try:
            pyautogui.moveTo(x, y, duration=duration)
            return ActionResult(
                success=True,
                action="move",
                message=f"Moved cursor to ({x}, {y})",
            )
        except Exception as e:
            return ActionResult(success=False, action="move", error=str(e))

    def drag(
        self,
        start_x: int,
        start_y: int,
        end_x: int,
        end_y: int,
        duration: float = 0.5,
    ) -> ActionResult:
        """
        Drag from one position to another.

        Args:
            start_x: Starting X coordinate
            start_y: Starting Y coordinate
            end_x: Ending X coordinate
            end_y: Ending Y coordinate
            duration: Time to take for the drag (seconds)

        Returns:
            ActionResult indicating success or failure
        """
        if not self._validate_coordinates(start_x, start_y):
            return ActionResult(
                success=False,
                action="drag",
                error=f"Start coordinates ({start_x}, {start_y}) out of bounds",
            )
        if not self._validate_coordinates(end_x, end_y):
            return ActionResult(
                success=False,
                action="drag",
                error=f"End coordinates ({end_x}, {end_y}) out of bounds",
            )

        try:
            pyautogui.moveTo(start_x, start_y)
            pyautogui.drag(
                end_x - start_x,
                end_y - start_y,
                duration=duration,
            )
            return ActionResult(
                success=True,
                action="drag",
                message=f"Dragged from ({start_x}, {start_y}) to ({end_x}, {end_y})",
            )
        except Exception as e:
            return ActionResult(success=False, action="drag", error=str(e))

    def type_text(self, text: str, interval: float = 0.02) -> ActionResult:
        """
        Type text using the keyboard.

        Args:
            text: Text to type
            interval: Delay between keypresses (seconds)

        Returns:
            ActionResult indicating success or failure
        """
        try:
            pyautogui.write(text, interval=interval)
            return ActionResult(
                success=True,
                action="type",
                message=f"Typed: {text[:50]}{'...' if len(text) > 50 else ''}",
            )
        except Exception as e:
            return ActionResult(success=False, action="type", error=str(e))

    def hotkey(self, *keys: str) -> ActionResult:
        """
        Press a keyboard shortcut.

        Args:
            *keys: Keys to press together (e.g., "command", "c" for Cmd+C)

        Returns:
            ActionResult indicating success or failure
        """
        try:
            pyautogui.hotkey(*keys)
            return ActionResult(
                success=True,
                action="hotkey",
                message=f"Pressed: {'+'.join(keys)}",
            )
        except Exception as e:
            return ActionResult(success=False, action="hotkey", error=str(e))

    def scroll(
        self,
        clicks: int = 3,
        direction: Literal["up", "down", "left", "right"] = "down",
        x: int | None = None,
        y: int | None = None,
    ) -> ActionResult:
        """
        Scroll the page.

        Args:
            clicks: Number of scroll units
            direction: Scroll direction
            x: X coordinate to scroll at (optional)
            y: Y coordinate to scroll at (optional)

        Returns:
            ActionResult indicating success or failure
        """
        try:
            # Determine scroll amount based on direction
            if direction == "up":
                scroll_amount = clicks
            elif direction == "down":
                scroll_amount = -clicks
            else:
                # Horizontal scrolling (if supported)
                scroll_amount = clicks if direction == "right" else -clicks
                pyautogui.hscroll(scroll_amount, x=x, y=y)
                return ActionResult(
                    success=True,
                    action="scroll",
                    message=f"Scrolled {direction} by {clicks}",
                )

            pyautogui.scroll(scroll_amount, x=x, y=y)
            return ActionResult(
                success=True,
                action="scroll",
                message=f"Scrolled {direction} by {clicks}",
            )
        except Exception as e:
            return ActionResult(success=False, action="scroll", error=str(e))

    def wait(self, seconds: float) -> ActionResult:
        """
        Wait for a specified time.

        Args:
            seconds: Time to wait

        Returns:
            ActionResult indicating success
        """
        time.sleep(seconds)
        return ActionResult(
            success=True,
            action="wait",
            message=f"Waited {seconds} seconds",
        )

    def get_mouse_position(self) -> tuple[int, int]:
        """Get the current mouse position."""
        return pyautogui.position()
