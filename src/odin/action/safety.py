"""Safety checks and validation for actions."""

import time
from collections.abc import Callable
from dataclasses import dataclass, field

from pydantic import BaseModel

from odin.platform.base import PlatformBackend, default_backend


class SafetyConfig(BaseModel):
    """Configuration for safety limits."""

    max_actions_per_minute: int = 60

    min_action_delay: float = 0.1

    require_confirmation: bool = False

    bounds_margin: int = 10


@dataclass(init=False)
class SafetyController:
    """
    Safety layer for action validation and rate limiting.

    Provides checks to prevent accidental damage from automated actions.
    The screen size must be supplied at construction (typically by the
    agent that owns both the :class:`ActionController` and this controller);
    call :meth:`refresh_screen_size` to re-read after a display change.
    """

    config: SafetyConfig
    screen_width: int
    screen_height: int
    _action_times: list[float] = field(default_factory=list, repr=False)
    _last_action_time: float = field(default=0.0, repr=False)
    _screen_size_provider: Callable[[], tuple[int, int]] | None = field(
        default=None, repr=False, compare=False,
    )

    def __init__(
        self,
        config: SafetyConfig | None = None,
        *,
        screen_size: tuple[int, int] | None = None,
        backend: PlatformBackend | None = None,
    ) -> None:
        """Initialize the safety controller.

        Args:
            config: Optional safety configuration.
            screen_size: Optional ``(width, height)`` for bounds checks. If
                omitted, the controller starts with ``(0, 0)`` and the
                caller is expected to populate it (or use
                :meth:`from_backend`).
            backend: Optional platform backend. When provided without
                ``screen_size``, the initial dimensions are read from it.
        """
        self.config = config or SafetyConfig()
        self._action_times = []
        self._last_action_time = 0.0
        self._screen_size_provider = None

        if screen_size is not None:
            self.screen_width, self.screen_height = screen_size
        elif backend is not None:
            self.screen_width, self.screen_height = backend.screen_size()
        else:
            self.screen_width = 0
            self.screen_height = 0

    def refresh_screen_size(
        self,
        backend: PlatformBackend | None = None,
    ) -> None:
        """Re-read the screen dimensions from ``backend`` (or the default)."""
        provider = self._screen_size_provider
        if provider is not None:
            self.screen_width, self.screen_height = provider()
            return
        if backend is None:
            backend = default_backend()
        self.screen_width, self.screen_height = backend.screen_size()

    @classmethod
    def from_backend(
        cls,
        backend: PlatformBackend,
        config: SafetyConfig | None = None,
    ) -> "SafetyController":
        """Construct a controller that lazily reads its screen size from ``backend``."""
        controller = cls(config=config, backend=backend)
        controller._screen_size_provider = backend.screen_size
        return controller

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

        self._action_times = [t for t in self._action_times if current_time - t < 60]

        if len(self._action_times) >= self.config.max_actions_per_minute:
            return False, "Rate limit exceeded: too many actions per minute"

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
        allowed, error = self.check_rate_limit()
        if not allowed:
            return False, error

        if action in ("click", "double_click", "move"):
            x = params.get("x", 0)
            y = params.get("y", 0)
            valid, error = self.validate_coordinates(x, y)
            if not valid:
                return False, error

        if action == "drag":
            for coord_pair in [("start_x", "start_y"), ("end_x", "end_y")]:
                x = params.get(coord_pair[0], 0)
                y = params.get(coord_pair[1], 0)
                valid, error = self.validate_coordinates(x, y)
                if not valid:
                    return False, error

        return True, None

