"""Tests for compact LLM context formatting."""

from odin.llm.context import format_screen_context


def test_format_screen_context_uses_compact_sections():
    """Large repeated context should be row-oriented, not JSON text."""
    text = format_screen_context({
        "coordinate_system": {
            "type": "screenshot_coordinates_for_raw_xy_actions",
            "origin": "top_left",
            "x_axis": "right",
            "y_axis": "down",
            "screenshot_size": {"width": 1800, "height": 1130},
            "screen_size": {"width": 1800, "height": 1169},
        },
        "mouse": {
            "available": True,
            "screen_position": {"x": 10, "y": 20},
            "screenshot_position": {"x": 10, "y": 19},
        },
        "app": {
            "frontmost_app": {
                "name": "Firefox",
                "bundle_id": "org.mozilla.firefox",
                "pid": 2002,
            },
            "open_apps": [
                {
                    "name": "Firefox",
                    "bundle_id": "org.mozilla.firefox",
                    "pid": 2002,
                    "is_active": True,
                    "is_hidden": False,
                    "user_facing": True,
                    "window_count": 1,
                }
            ],
            "all_windows": [
                {
                    "window_id": 210,
                    "owner_name": "Firefox",
                    "owner_pid": 2002,
                    "title": "Dynamic Array Code Implementation",
                    "x": 0,
                    "y": 39,
                    "width": 1800,
                    "height": 1130,
                }
            ],
        },
        "accessibility": {
            "available": True,
            "trusted": True,
            "app": "Firefox",
            "window": "Dynamic Array Code Implementation",
            "elements": [
                {
                    "id": "ax_1",
                    "role": "AXWindow",
                    "title": "Dynamic Array Code Implementation",
                    "frame": {"x": 0, "y": 39, "width": 1800, "height": 1130},
                    "enabled": True,
                    "focused": True,
                    "actions": ["AXRaise"],
                    "depth": 0,
                }
            ],
        },
    })

    assert "SCREEN_CONTEXT" in text
    assert "COORDINATES:" in text
    assert "screenshot=1800x1130" in text
    assert "OPEN_APPS:" in text
    assert "Firefox | 2002 | true | false | true | 1 | org.mozilla.firefox" in text
    assert "ALL_WINDOWS:" in text
    assert "210 | Firefox | 2002 | Dynamic Array Code Implementation | 0,39,1800,1130" in text
    assert "ACCESSIBILITY:" in text
    assert "ax_1 | AXWindow | Dynamic Array Code Implementation" in text
    assert '{"coordinate_system"' not in text
