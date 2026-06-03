"""Platform abstraction for input simulation and screen capture.

Define a :class:`PlatformBackend` protocol that all platform-specific
implementations (e.g. :class:`odin.platform.macos.MacOSBackend`) conform to.
Higher-level components such as :class:`odin.action.controller.ActionController`
and :class:`odin.perception.screen.Screen` accept a backend via constructor
injection so they can be tested with fakes and reused on other platforms.
"""

from __future__ import annotations

from typing import Any, Literal, Protocol, runtime_checkable

from PIL import Image


@runtime_checkable
class PlatformBackend(Protocol):
    """Cross-platform interface for input simulation and screen capture."""

    def screen_size(self) -> tuple[int, int]:
        """Return ``(width, height)`` of the primary display in points."""
        ...

    def mouse_position(self) -> tuple[int, int]:
        """Return the current mouse ``(x, y)`` in screen coordinates."""
        ...

    def click(
        self,
        x: int,
        y: int,
        button: Literal["left", "right", "middle"] = "left",
    ) -> None:
        """Click at ``(x, y)`` with the given mouse button."""
        ...

    def double_click(self, x: int, y: int) -> None:
        """Double-click at ``(x, y)``."""
        ...

    def move(self, x: int, y: int) -> None:
        """Move the mouse pointer to ``(x, y)``."""
        ...

    def drag(
        self,
        start_x: int,
        start_y: int,
        end_x: int,
        end_y: int,
        duration: float = 0.5,
    ) -> None:
        """Drag from the start to the end position over ``duration`` seconds."""
        ...

    def type_text(self, text: str) -> None:
        """Type ``text`` as keyboard input."""
        ...

    def hotkey(self, *keys: str) -> None:
        """Press a key combination (e.g. ``"command"``, ``"c"``)."""
        ...

    def scroll(
        self,
        direction: Literal["up", "down", "left", "right"],
        clicks: int = 3,
        x: int | None = None,
        y: int | None = None,
    ) -> None:
        """Scroll ``clicks`` units in ``direction``, optionally at ``(x, y)``."""
        ...

    def screenshot(self) -> Image.Image:
        """Capture the primary display and return a PIL Image."""
        ...

    def frontmost_app(self) -> dict[str, Any]:
        """Return info about the frontmost application (``name``, ``bundle_id``, ``pid``)."""
        ...

    def running_apps(self) -> list[dict[str, Any]]:
        """Return a list of running applications and their activation state."""
        ...

    def window_list(
        self,
        *,
        on_screen_only: bool = True,
        for_pid: int | None = None,
    ) -> list[dict[str, Any]]:
        """Return a list of visible windows with bounds and owner info."""
        ...


def default_backend() -> PlatformBackend:
    """Return the platform backend appropriate for the current OS.

    Currently only macOS is supported; raises ``RuntimeError`` elsewhere.
    """
    import sys

    if sys.platform != "darwin":
        raise RuntimeError(
            f"Odin is not supported on '{sys.platform}'. "
            "Only macOS is currently implemented."
        )

    from odin.platform.macos import MacOSBackend

    return MacOSBackend()


__all__ = ["PlatformBackend", "default_backend"]
