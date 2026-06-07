"""Compact text formatting for LLM screen context input."""

from __future__ import annotations

from typing import Any


def format_screen_context(screen_context: dict[str, Any]) -> str:
    """Format screen context as compact, schema-guided text for the LLM."""
    lines: list[str] = ["SCREEN_CONTEXT"]

    coordinate_system = screen_context.get("coordinate_system")
    if isinstance(coordinate_system, dict):
        lines.extend(_format_coordinate_system(coordinate_system))

    mouse = screen_context.get("mouse")
    if isinstance(mouse, dict):
        lines.extend(_format_mouse(mouse))

    app = screen_context.get("app")
    if isinstance(app, dict):
        lines.extend(_format_app_context(app))

    accessibility = screen_context.get("accessibility")
    if isinstance(accessibility, dict):
        lines.extend(_format_accessibility(accessibility))

    guidance = screen_context.get("interaction_guidance")
    if guidance:
        lines.extend(["", "GUIDANCE:", str(guidance)])

    known_keys = {
        "coordinate_system",
        "mouse",
        "app",
        "accessibility",
        "interaction_guidance",
    }
    extra_lines = _format_extra_context(screen_context, known_keys)
    if extra_lines:
        lines.extend(["", "EXTRA:", *extra_lines])

    return "\n".join(lines)


def _format_coordinate_system(data: dict[str, Any]) -> list[str]:
    screenshot = _size(data.get("screenshot_size"))
    screen = _size(data.get("screen_size"))
    parts = [
        f"type={_scalar(data.get('type'))}",
        f"origin={_scalar(data.get('origin'))}",
        f"x_axis={_scalar(data.get('x_axis'))}",
        f"y_axis={_scalar(data.get('y_axis'))}",
        f"screenshot={screenshot}",
        f"screen={screen}",
    ]
    lines = ["", "COORDINATES:", " ".join(parts)]
    notes = data.get("notes")
    if notes:
        lines.append(f"notes={_scalar(notes)}")
    return lines


def _format_mouse(data: dict[str, Any]) -> list[str]:
    screen = _point(data.get("screen_position"))
    screenshot = _point(data.get("screenshot_position"))
    parts = [
        f"available={_scalar(data.get('available'))}",
        f"screen={screen}",
        f"screenshot={screenshot}",
    ]
    if data.get("error"):
        parts.append(f"error={_scalar(data.get('error'))}")
    return ["", "MOUSE:", " ".join(parts)]


def _format_app_context(data: dict[str, Any]) -> list[str]:
    lines: list[str] = ["", "APP_CONTEXT:"]

    frontmost = data.get("frontmost_app")
    if isinstance(frontmost, dict):
        lines.append(
            "frontmost "
            f"name={_scalar(frontmost.get('name'))} "
            f"bundle={_scalar(frontmost.get('bundle_id'))} "
            f"pid={_scalar(frontmost.get('pid'))}"
        )

    open_apps = data.get("open_apps")
    if isinstance(open_apps, list) and open_apps:
        lines.extend([
            "",
            "OPEN_APPS:",
            "name | pid | active | hidden | user_facing | windows | bundle",
        ])
        for app in open_apps:
            if isinstance(app, dict):
                lines.append(
                    " | ".join([
                        _cell(app.get("name")),
                        _cell(app.get("pid")),
                        _cell(app.get("is_active")),
                        _cell(app.get("is_hidden")),
                        _cell(app.get("user_facing")),
                        _cell(app.get("window_count")),
                        _cell(app.get("bundle_id")),
                    ])
                )

    lines.extend(_format_windows("FRONTMOST_WINDOWS", data.get("windows")))
    lines.extend(_format_windows("VISIBLE_WINDOWS", data.get("visible_windows")))
    lines.extend(_format_windows("ALL_WINDOWS", data.get("all_windows")))

    window_scope = data.get("window_scope")
    if isinstance(window_scope, dict):
        lines.extend(["", "WINDOW_SCOPE:"])
        for key, value in window_scope.items():
            lines.append(f"{_scalar(key)}={_scalar(value)}")

    return lines


def _format_windows(section: str, value: Any) -> list[str]:
    if not isinstance(value, list) or not value:
        return []

    lines = [
        "",
        f"{section}:",
        "id | app | pid | title | frame",
    ]
    for window in value:
        if not isinstance(window, dict):
            continue
        lines.append(
            " | ".join([
                _cell(window.get("window_id")),
                _cell(window.get("owner_name")),
                _cell(window.get("owner_pid")),
                _cell(window.get("title")),
                _cell(_frame(window)),
            ])
        )
    return lines


def _format_accessibility(data: dict[str, Any]) -> list[str]:
    delta = data.get("delta")
    if isinstance(delta, dict):
        return _format_accessibility_delta(data, delta)
    return _format_accessibility_full(data)


def _format_accessibility_full(data: dict[str, Any]) -> list[str]:
    lines = [
        "",
        "ACCESSIBILITY:",
        (
            f"available={_scalar(data.get('available'))} "
            f"trusted={_scalar(data.get('trusted'))} "
            f"app={_scalar(data.get('app'))} "
            f"window={_scalar(data.get('window'))}"
        ),
    ]
    if data.get("error"):
        lines.append(f"error={_scalar(data.get('error'))}")

    elements = data.get("elements")
    if isinstance(elements, list) and elements:
        lines.append(
            "id | role | title | value | desc | placeholder | frame | "
            "enabled | focused | actions | depth"
        )
        for element in elements:
            if isinstance(element, dict):
                lines.append(_element_row(element))
    return lines


def _format_accessibility_delta(
    data: dict[str, Any],
    delta: dict[str, Any],
) -> list[str]:
    unchanged = delta.get("unchanged") or []
    added = delta.get("added") or []
    changed = delta.get("changed") or []
    removed = delta.get("removed") or []

    lines = [
        "",
        "ACCESSIBILITY_DELTA:",
        (
            f"available={_scalar(data.get('available'))} "
            f"trusted={_scalar(data.get('trusted'))} "
            f"app={_scalar(data.get('app'))} "
            f"window={_scalar(data.get('window'))} "
            f"(unchanged since previous step; changed/added/removed below)"
        ),
    ]

    if unchanged:
        parts: list[str] = []
        for item in unchanged:
            if not isinstance(item, dict):
                continue
            element_id = _cell(item.get("id"))
            role = _cell(item.get("role")) or "-"
            title = _cell(item.get("title")) or "-"
            parts.append(f"{element_id}:{role}:{title}")
        if parts:
            lines.append(f"UNCHANGED ({len(parts)}): {', '.join(parts)}")

    for label, items in (("CHANGED", changed), ("ADDED", added)):
        if not items:
            continue
        lines.append(f"{label} ({len(items)}):")
        lines.append(
            "id | role | title | value | desc | placeholder | frame | "
            "enabled | focused | actions | depth"
        )
        for element in items:
            if isinstance(element, dict):
                lines.append(_element_row(element))

    if removed:
        lines.append(f"REMOVED ({len(removed)}): {', '.join(_cell(eid) for eid in removed)}")

    return lines


def _element_row(element: dict[str, Any]) -> str:
    return " | ".join([
        _cell(element.get("id")),
        _cell(element.get("role")),
        _cell(element.get("title")),
        _cell(element.get("value")),
        _cell(element.get("description")),
        _cell(element.get("placeholder")),
        _cell(_frame(element.get("frame"))),
        _cell(element.get("enabled")),
        _cell(element.get("focused")),
        _cell(",".join(map(str, element.get("actions", [])))),
        _cell(element.get("depth")),
    ])


def _format_extra_context(
    data: dict[str, Any],
    known_keys: set[str],
) -> list[str]:
    lines: list[str] = []
    for key in sorted(set(data) - known_keys):
        value = data.get(key)
        if isinstance(value, str | int | float | bool) or value is None:
            lines.append(f"{_scalar(key)}={_scalar(value)}")
    return lines


def _size(value: Any) -> str:
    if not isinstance(value, dict):
        return "-"
    width = value.get("width")
    height = value.get("height")
    if width is None or height is None:
        return "-"
    return f"{width}x{height}"


def _point(value: Any) -> str:
    if not isinstance(value, dict):
        return "-"
    x = value.get("x")
    y = value.get("y")
    if x is None or y is None:
        return "-"
    return f"{x},{y}"


def _frame(value: Any) -> str:
    if not isinstance(value, dict):
        return "-"
    x = value.get("x")
    y = value.get("y")
    width = value.get("width")
    height = value.get("height")
    if None in (x, y, width, height):
        return "-"
    return f"{x},{y},{width},{height}"


def _cell(value: Any) -> str:
    text = _scalar(value)
    if text == "":
        return "-"
    return text.replace("|", "/").replace("\n", " ")


def _scalar(value: Any) -> str:
    if value is True:
        return "true"
    if value is False:
        return "false"
    if value is None:
        return "-"
    return str(value)
