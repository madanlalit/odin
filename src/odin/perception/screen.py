from __future__ import annotations

from collections import defaultdict
from typing import Any

from PIL import Image

from odin.platform.macos import MacOSBackend


class Screen:
    def __init__(self):
        self._backend = MacOSBackend()
        self.width, self.height = self._backend.screen_size()

    def get_screenshot(self) -> Image.Image:
        """
        Captures and returns a screenshot of the primary monitor.

        Uses Quartz ``CGWindowListCreateImage`` for fast, native capture.
        """
        try:
            return self._backend.screenshot()
        except PermissionError:
            raise
        except Exception as e:
            raise RuntimeError(f"Failed to capture screenshot: {e}")

    def get_focused_window_screenshot(self) -> Image.Image | None:
        """Capture only the focused application's window.

        Returns *None* when the window cannot be identified or captured.
        Falls back to a full-screen capture internally if needed.
        """
        window_id = self._backend.focused_window_id()
        if window_id is None:
            return None
        return self._backend.screenshot_window(window_id)

    def get_app_context(self) -> dict[str, Any]:
        """Return context about open apps and windows across macOS Spaces.

        The returned dict is safe for JSON serialisation and can be passed
        directly to the LLM as part of the screen context.
        """
        app = self._backend.frontmost_app()
        pid = app.get("pid")
        visible_windows = self._backend.window_list(on_screen_only=True)
        all_windows = self._backend.window_list(on_screen_only=False)
        frontmost_windows = [
            window for window in all_windows if pid and window.get("owner_pid") == int(pid)
        ]
        try:
            running_apps = self._backend.running_apps()
        except Exception:
            running_apps = []

        return {
            "frontmost_app": {
                "name": app.get("name"),
                "bundle_id": app.get("bundle_id"),
                "pid": app.get("pid"),
            },
            "windows": [_window_context(window) for window in frontmost_windows],
            "open_apps": _open_app_context(running_apps, all_windows),
            "visible_windows": [_window_context(window) for window in visible_windows],
            "all_windows": [_window_context(window) for window in all_windows],
            "window_scope": {
                "visible_windows": "current visible Space only",
                "all_windows": "all window-server windows, including fullscreen/off-Space windows when macOS reports them",
            },
        }


def _window_context(window: dict[str, object]) -> dict[str, object]:
    """Return compact prompt-safe window metadata."""
    return {
        "window_id": window.get("window_id"),
        "owner_name": window.get("owner_name"),
        "owner_pid": window.get("owner_pid"),
        "title": window.get("title"),
        "x": window.get("x"),
        "y": window.get("y"),
        "width": window.get("width"),
        "height": window.get("height"),
    }


def _open_app_context(
    running_apps: list[dict[str, str | int | bool | None]],
    all_windows: list[dict[str, object]],
) -> list[dict[str, object]]:
    """Combine running app state with all-space window metadata."""
    windows_by_pid: dict[int, list[dict[str, object]]] = defaultdict(list)
    for window in all_windows:
        pid = window.get("owner_pid")
        if isinstance(pid, int):
            windows_by_pid[pid].append(window)

    apps: list[dict[str, object]] = []
    seen_pids: set[int] = set()
    for app in running_apps:
        pid = app.get("pid")
        if not isinstance(pid, int):
            continue
        if app.get("user_facing") is False and pid not in windows_by_pid:
            continue
        seen_pids.add(pid)
        windows = windows_by_pid.get(pid, [])
        apps.append({
            "name": app.get("name"),
            "bundle_id": app.get("bundle_id"),
            "pid": pid,
            "is_active": app.get("is_active"),
            "is_hidden": app.get("is_hidden"),
            "user_facing": app.get("user_facing"),
            "window_count": len(windows),
            "windows": [_window_context(window) for window in windows],
        })

    for pid, windows in windows_by_pid.items():
        if pid in seen_pids:
            continue
        owner_name = next(
            (window.get("owner_name") for window in windows if window.get("owner_name")),
            None,
        )
        apps.append({
            "name": owner_name,
            "bundle_id": None,
            "pid": pid,
            "is_active": False,
            "is_hidden": None,
            "user_facing": None,
            "window_count": len(windows),
            "windows": [_window_context(window) for window in windows],
        })

    return apps
