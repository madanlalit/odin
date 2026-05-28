"""Tests for screen context assembly."""

from odin.perception.screen import Screen


class FakeBackend:
    """Backend with one fullscreen/off-Space Firefox window."""

    def __init__(self):
        self.window_list_calls: list[dict[str, object]] = []
        self.visible_windows = [
            {
                "window_id": 1,
                "owner_name": "Codex",
                "owner_pid": 100,
                "title": "Codex",
                "x": 10,
                "y": 20,
                "width": 1200,
                "height": 800,
            }
        ]
        self.all_windows = [
            *self.visible_windows,
            {
                "window_id": 2,
                "owner_name": "Firefox",
                "owner_pid": 200,
                "title": "Dynamic Array Code Implementation",
                "x": 0,
                "y": 39,
                "width": 1800,
                "height": 1130,
            },
        ]

    def frontmost_app(self):
        return {
            "name": "Firefox",
            "bundle_id": "org.mozilla.firefox",
            "pid": 200,
        }

    def window_list(self, *, on_screen_only=True, for_pid=None):
        self.window_list_calls.append({
            "on_screen_only": on_screen_only,
            "for_pid": for_pid,
        })
        windows = self.visible_windows if on_screen_only else self.all_windows
        if for_pid is None:
            return windows
        return [window for window in windows if window["owner_pid"] == for_pid]

    def running_apps(self):
        return [
            {
                "name": "Codex",
                "bundle_id": "com.openai.codex",
                "pid": 100,
                "is_active": False,
                "is_hidden": False,
                "user_facing": True,
            },
            {
                "name": "Firefox",
                "bundle_id": "org.mozilla.firefox",
                "pid": 200,
                "is_active": True,
                "is_hidden": False,
                "user_facing": True,
            },
        ]


def test_app_context_includes_all_space_windows_and_open_apps():
    """Fullscreen/off-Space windows should be available to the agent."""
    screen = object.__new__(Screen)
    screen._backend = FakeBackend()

    context = screen.get_app_context()

    assert {
        "on_screen_only": False,
        "for_pid": None,
    } in screen._backend.window_list_calls
    assert context["frontmost_app"] == {
        "name": "Firefox",
        "bundle_id": "org.mozilla.firefox",
        "pid": 200,
    }
    assert context["windows"][0]["title"] == "Dynamic Array Code Implementation"
    assert context["all_windows"][1]["owner_name"] == "Firefox"

    firefox = next(app for app in context["open_apps"] if app["name"] == "Firefox")
    assert firefox["window_count"] == 1
    assert firefox["windows"][0]["title"] == "Dynamic Array Code Implementation"
