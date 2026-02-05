"""Safety checks and validation for actions."""

import time
from dataclasses import dataclass, field

import pyautogui  # type: ignore[import-untyped]


@dataclass
class SafetyConfig:
    """Configuration for safety limits."""

    # Maximum actions per minute
    max_actions_per_minute: int = 60

    # Minimum delay between actions (seconds)
    min_action_delay: float = 0.1

    # Whether to require confirmation for dangerous actions
    require_confirmation: bool = False

    # Screen bounds margin (pixels from edge)
    bounds_margin: int = 10


@dataclass
class SafetyController:
    """
    Safety layer for action validation and rate limiting.

    Provides checks to prevent accidental damage from automated actions.
    """

    config: SafetyConfig = field(default_factory=SafetyConfig)
    _action_times: list[float] = field(default_factory=list)
    _last_action_time: float = 0.0

    def __post_init__(self):
        self.screen_width, self.screen_height = pyautogui.size()

    def validate_coordinates(self, x: int, y: int) -> tuple[bool, str | None]:
        """
        Validate that coordinates are within safe screen bounds.

        Args:
            x: X coordinate
            y: Y coordinate

        Returns:
            Tuple of (is_valid, error_message)
        """
        margin = self.config.bounds_margin

        if x < margin or x >= self.screen_width - margin:
            return False, f"X coordinate {x} is too close to screen edge"

        if y < margin or y >= self.screen_height - margin:
            return False, f"Y coordinate {y} is too close to screen edge"

        return True, None

    def check_rate_limit(self) -> tuple[bool, str | None]:
        """
        Check if we're within the rate limit.

        Returns:
            Tuple of (is_allowed, error_message)
        """
        current_time = time.time()

        # Clean up old action times (older than 1 minute)
        self._action_times = [t for t in self._action_times if current_time - t < 60]

        # Check actions per minute limit
        if len(self._action_times) >= self.config.max_actions_per_minute:
            return False, "Rate limit exceeded: too many actions per minute"

        # Check minimum delay
        if current_time - self._last_action_time < self.config.min_action_delay:
            return False, "Minimum delay between actions not met"

        return True, None

    def record_action(self):
        """Record that an action was executed."""
        current_time = time.time()
        self._action_times.append(current_time)
        self._last_action_time = current_time

    def validate_action(
        self,
        action: str,
        params: dict,
    ) -> tuple[bool, str | None]:
        """
        Validate an action before execution.

        Args:
            action: Action name
            params: Action parameters

        Returns:
            Tuple of (is_valid, error_message)
        """
        # Check rate limit
        allowed, error = self.check_rate_limit()
        if not allowed:
            return False, error

        # Validate coordinates for position-based actions
        if action in ("click", "double_click", "move"):
            x = params.get("x", 0)
            y = params.get("y", 0)
            valid, error = self.validate_coordinates(x, y)
            if not valid:
                return False, error

        # Validate drag coordinates
        if action == "drag":
            for coord_pair in [("start_x", "start_y"), ("end_x", "end_y")]:
                x = params.get(coord_pair[0], 0)
                y = params.get(coord_pair[1], 0)
                valid, error = self.validate_coordinates(x, y)
                if not valid:
                    return False, error

        return True, None

    def is_dangerous_action(self, action: str, params: dict) -> bool:
        """
        Check if an action is potentially dangerous.

        Dangerous actions might include:
        - Typing in password fields
        - Clicking on system dialogs
        - Executing hotkeys that could delete data

        Args:
            action: Action name
            params: Action parameters

        Returns:
            True if the action is potentially dangerous
        """
        if action == "hotkey":
            keys = params.get("keys", [])
            dangerous_combos = [
                {"command", "q"},  # Quit app
                {"command", "delete"},  # Delete
                {"command", "shift", "delete"},  # Empty trash
                {"control", "alt", "delete"},  # System interrupt
            ]
            key_set = set(k.lower() for k in keys)
            for combo in dangerous_combos:
                if combo.issubset(key_set):
                    return True

        return False
