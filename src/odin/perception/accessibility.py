"""macOS accessibility tree capture and element interaction."""

from __future__ import annotations

from collections.abc import Iterable
from importlib import import_module
from typing import Any, cast

from pydantic import BaseModel, Field

AX_OK = 0


class AXFrame(BaseModel):
    """Screen-space frame for an accessibility element."""

    x: int
    y: int
    width: int
    height: int

    @property
    def center(self) -> tuple[int, int]:
        """Return the center point of the frame."""
        return (self.x + self.width // 2, self.y + self.height // 2)

    def to_dict(self) -> dict[str, int]:
        """Convert frame to prompt-safe JSON."""
        return {
            "x": self.x,
            "y": self.y,
            "width": self.width,
            "height": self.height,
        }


class AXElementInfo(BaseModel):
    """Prompt-safe accessibility element information."""

    id: str
    role: str | None = None
    title: str | None = None
    value: str | None = None
    description: str | None = None
    placeholder: str | None = None
    frame: AXFrame | None = None
    enabled: bool | None = None
    focused: bool | None = None
    actions: list[str] = Field(default_factory=list)
    depth: int = 0

    def to_dict(self) -> dict[str, Any]:
        """Convert element info to compact prompt-safe JSON."""
        data: dict[str, Any] = {
            "id": self.id,
            "role": self.role,
            "title": self.title,
            "value": self.value,
            "description": self.description,
            "placeholder": self.placeholder,
            "frame": self.frame.to_dict() if self.frame else None,
            "enabled": self.enabled,
            "focused": self.focused,
            "actions": self.actions,
            "depth": self.depth,
        }
        return {key: value for key, value in data.items() if value not in (None, "", [])}


class AccessibilitySnapshot(BaseModel):
    """Captured accessibility context for one agent step."""

    available: bool
    trusted: bool | None = None
    app: str | None = None
    window: str | None = None
    elements: list[AXElementInfo] = Field(default_factory=list)
    error: str | None = None

    def to_context(self) -> dict[str, Any]:
        """Convert snapshot to prompt-safe JSON."""
        data: dict[str, Any] = {
            "available": self.available,
            "trusted": self.trusted,
            "app": self.app,
            "window": self.window,
            "elements": [element.to_dict() for element in self.elements],
            "error": self.error,
        }
        return {key: value for key, value in data.items() if value not in (None, "", [])}


class Accessibility:
    """Capture and interact with the focused macOS accessibility tree."""

    def __init__(self):
        """Initialize the accessibility bridge lazily."""
        self._ax: Any | None = None
        self._elements_by_id: dict[str, Any] = {}
        self._info_by_id: dict[str, AXElementInfo] = {}
        self._last_error: str | None = None

    def capture(
        self,
        *,
        max_depth: int = 8,
        max_nodes: int = 120,
    ) -> AccessibilitySnapshot:
        """Capture a compact accessibility tree for the focused window."""
        self._elements_by_id.clear()
        self._info_by_id.clear()

        ax = self._load_ax()
        if ax is None:
            return AccessibilitySnapshot(
                available=False,
                trusted=None,
                error=self._last_error,
            )

        trusted = self._is_trusted(ax)
        if trusted is False:
            return AccessibilitySnapshot(
                available=False,
                trusted=False,
                error="Accessibility permission is not granted.",
            )

        try:
            system = ax.AXUIElementCreateSystemWide()
            app = self._copy_attr(system, ax.kAXFocusedApplicationAttribute)
            if app is None:
                app = self._frontmost_application(ax)
            if app is None:
                return AccessibilitySnapshot(
                    available=False,
                    trusted=trusted,
                    error="No focused application is available.",
                )

            window = self._copy_attr(app, ax.kAXFocusedWindowAttribute)
            root = window or app
            elements = self._walk(root, max_depth=max_depth, max_nodes=max_nodes)

            return AccessibilitySnapshot(
                available=True,
                trusted=trusted,
                app=_stringify(self._copy_attr(app, ax.kAXTitleAttribute)),
                window=_stringify(self._copy_attr(root, ax.kAXTitleAttribute)),
                elements=elements,
            )
        except Exception as exc:
            return AccessibilitySnapshot(
                available=False,
                trusted=trusted,
                error=f"{exc.__class__.__name__}: {exc}",
            )

    def perform_action(self, element_id: str, action_name: str) -> tuple[bool, str]:
        """Perform a native AX action on an element."""
        element = self._elements_by_id.get(element_id)
        if element is None:
            return False, f"Unknown accessibility element: {element_id}"

        ax = self._load_ax()
        if ax is None:
            return False, self._last_error or "Accessibility APIs are unavailable."

        action = self._action_constant(ax, action_name)
        if not action:
            return False, f"Unsupported AX action: {action_name}"

        try:
            error = ax.AXUIElementPerformAction(element, action)
        except Exception as exc:
            return False, f"{exc.__class__.__name__}: {exc}"

        if error != AX_OK:
            return False, f"AX action {action} failed with error {error}"

        return True, f"Performed {action} on {element_id}"

    def focus(self, element_id: str) -> tuple[bool, str]:
        """Focus an accessibility element."""
        element = self._elements_by_id.get(element_id)
        if element is None:
            return False, f"Unknown accessibility element: {element_id}"

        ax = self._load_ax()
        if ax is None:
            return False, self._last_error or "Accessibility APIs are unavailable."

        try:
            error = ax.AXUIElementSetAttributeValue(
                element,
                ax.kAXFocusedAttribute,
                True,
            )
        except Exception as exc:
            return False, f"{exc.__class__.__name__}: {exc}"

        if error != AX_OK:
            return False, f"AX focus failed with error {error}"

        return True, f"Focused {element_id}"

    def set_value(self, element_id: str, value: str) -> tuple[bool, str]:
        """Set the value of an accessibility element."""
        element = self._elements_by_id.get(element_id)
        if element is None:
            return False, f"Unknown accessibility element: {element_id}"

        ax = self._load_ax()
        if ax is None:
            return False, self._last_error or "Accessibility APIs are unavailable."

        try:
            error = ax.AXUIElementSetAttributeValue(
                element,
                ax.kAXValueAttribute,
                value,
            )
        except Exception as exc:
            return False, f"{exc.__class__.__name__}: {exc}"

        if error != AX_OK:
            return False, f"AX set value failed with error {error}"

        return True, f"Set value for {element_id}"

    def frame(self, element_id: str) -> AXFrame | None:
        """Return the last captured frame for an element."""
        info = self._info_by_id.get(element_id)
        if info:
            return info.frame
        return None

    def describe(self, element_id: str) -> dict[str, Any] | None:
        """Return prompt-safe details for an element."""
        info = self._info_by_id.get(element_id)
        return info.to_dict() if info else None

    def _load_ax(self) -> Any | None:
        """Load PyObjC ApplicationServices only when accessibility is used."""
        if self._ax is not None:
            return self._ax

        try:
            self._ax = import_module("ApplicationServices")
        except ImportError as exc:
            self._last_error = (
                "macOS accessibility support requires pyobjc-framework-"
                f"ApplicationServices: {exc}"
            )
            return None

        required = (
            "AXUIElementCreateSystemWide",
            "AXUIElementCopyAttributeValue",
            "AXUIElementSetAttributeValue",
            "AXUIElementPerformAction",
        )
        missing = [name for name in required if not hasattr(self._ax, name)]
        if missing:
            self._last_error = f"Accessibility APIs unavailable: {', '.join(missing)}"
            self._ax = None
            return None

        return self._ax

    def _is_trusted(self, ax: Any) -> bool | None:
        """Return whether the process is trusted for accessibility."""
        checker = getattr(ax, "AXIsProcessTrusted", None)
        if checker is None:
            return None
        try:
            return bool(checker())
        except Exception:
            return None

    def _frontmost_application(self, ax: Any) -> Any | None:
        """Return the frontmost app AX element when system focus lookup is empty."""
        creator = getattr(ax, "AXUIElementCreateApplication", None)
        if creator is None:
            return None

        try:
            from odin.platform.macos import MacOSBackend

            pid = MacOSBackend.frontmost_app().get("pid")
            if pid is None:
                return None
            return creator(int(pid))
        except Exception:
            return None

    def _walk(self, root: Any, *, max_depth: int, max_nodes: int) -> list[AXElementInfo]:
        """Flatten the accessibility tree into a compact element list."""
        elements: list[AXElementInfo] = []
        stack: list[tuple[Any, int]] = [(root, 0)]
        seen: set[int] = set()

        while stack and len(elements) < max_nodes:
            element, depth = stack.pop()
            element_key = id(element)
            if element_key in seen:
                continue
            seen.add(element_key)

            element_id = f"ax_{len(elements) + 1}"
            info = self._element_info(element_id, element, depth)
            if self._is_interesting(info):
                self._elements_by_id[element_id] = element
                self._info_by_id[element_id] = info
                elements.append(info)

            if depth >= max_depth:
                continue

            children = self._children(element)
            for child in reversed(children):
                stack.append((child, depth + 1))

        return elements

    def _element_info(self, element_id: str, element: Any, depth: int) -> AXElementInfo:
        """Extract prompt-safe info from an AXUIElement."""
        ax = self._load_ax()
        if ax is None:
            return AXElementInfo(id=element_id, depth=depth)

        role = _stringify(self._copy_attr(element, ax.kAXRoleAttribute))
        title = _truncate(_stringify(self._copy_attr(element, ax.kAXTitleAttribute)))
        value = _truncate(_stringify(self._copy_attr(element, ax.kAXValueAttribute)))
        description = _truncate(
            _stringify(self._copy_attr(element, ax.kAXDescriptionAttribute))
        )
        placeholder = _truncate(
            _stringify(self._copy_attr(element, getattr(ax, "kAXPlaceholderValueAttribute", "")))
        )

        return AXElementInfo(
            id=element_id,
            role=role,
            title=title,
            value=value,
            description=description,
            placeholder=placeholder,
            frame=self._frame(element),
            enabled=_bool_or_none(self._copy_attr(element, ax.kAXEnabledAttribute)),
            focused=_bool_or_none(self._copy_attr(element, ax.kAXFocusedAttribute)),
            actions=self._actions(element),
            depth=depth,
        )

    def _copy_attr(self, element: Any, attribute: str) -> Any | None:
        """Read an AX attribute and return None on missing/failed attributes."""
        if not attribute:
            return None

        ax = self._load_ax()
        if ax is None:
            return None

        try:
            result = ax.AXUIElementCopyAttributeValue(element, attribute, None)
        except Exception:
            return None

        error, value = _split_ax_result(result)
        if error != AX_OK:
            return None

        return value

    def _children(self, element: Any) -> list[Any]:
        """Return AX children for an element."""
        ax = self._load_ax()
        if ax is None:
            return []

        children = self._copy_attr(element, ax.kAXChildrenAttribute)
        return _ax_iterable_list(children)

    def _frame(self, element: Any) -> AXFrame | None:
        """Read element position and size."""
        ax = self._load_ax()
        if ax is None:
            return None

        position = self._copy_attr(element, ax.kAXPositionAttribute)
        size = self._copy_attr(element, ax.kAXSizeAttribute)
        point = _ax_value_pair(ax, position, "kAXValueCGPointType")
        dimensions = _ax_value_pair(ax, size, "kAXValueCGSizeType")
        if point is None or dimensions is None:
            return None

        return AXFrame(
            x=round(point[0]),
            y=round(point[1]),
            width=round(dimensions[0]),
            height=round(dimensions[1]),
        )

    def _actions(self, element: Any) -> list[str]:
        """Return available AX action names for an element."""
        ax = self._load_ax()
        if ax is None or not hasattr(ax, "AXUIElementCopyActionNames"):
            return []

        try:
            result = ax.AXUIElementCopyActionNames(element, None)
        except Exception:
            return []

        error, actions = _split_ax_result(result)
        if error != AX_OK:
            return []
        return [str(action) for action in _ax_iterable_list(actions)]

    def _action_constant(self, ax: Any, action_name: str) -> str | None:
        """Map friendly action names to AX action constants."""
        normalized = action_name.lower()
        mapping = {
            "press": "kAXPressAction",
            "increment": "kAXIncrementAction",
            "decrement": "kAXDecrementAction",
            "show_menu": "kAXShowMenuAction",
            "scroll_up": "kAXScrollUpAction",
            "scroll_down": "kAXScrollDownAction",
            "scroll_left": "kAXScrollLeftAction",
            "scroll_right": "kAXScrollRightAction",
        }
        attr = mapping.get(normalized)
        if attr:
            return getattr(ax, attr, None)
        if action_name.startswith("AX"):
            return action_name
        return None

    def _is_interesting(self, info: AXElementInfo) -> bool:
        """Keep elements useful enough for model context."""
        if info.frame is None:
            return False
        if info.role in {"AXGroup", "AXLayoutArea", "AXLayoutItem"} and not (
            info.title or info.value or info.description or info.actions
        ):
            return False
        return bool(
            info.role
            or info.title
            or info.value
            or info.description
            or info.placeholder
            or info.actions
        )


def _split_ax_result(result: Any) -> tuple[int, Any | None]:
    """Normalize PyObjC AX return conventions."""
    if isinstance(result, tuple):
        if len(result) >= 2:
            return int(result[0]), result[1]
        if len(result) == 1:
            return int(result[0]), None
    if isinstance(result, int):
        return result, None
    return AX_OK, result


def _ax_iterable_list(value: Any) -> list[Any]:
    """Convert Python and PyObjC collection values to a plain list."""
    if value is None or isinstance(value, str | bytes | dict):
        return []
    if isinstance(value, Iterable):
        try:
            return list(value)
        except Exception:
            return []
    return []


def _ax_value_pair(ax: Any, value: Any, type_name: str) -> tuple[float, float] | None:
    """Convert an AXValue CGPoint/CGSize to a numeric pair."""
    if value is None or not hasattr(ax, "AXValueGetValue"):
        return None

    value_type = getattr(ax, type_name, None)
    if value_type is None:
        return None

    try:
        result = ax.AXValueGetValue(value, value_type, None)
    except Exception:
        return _pair_from_attrs(value)

    if isinstance(result, tuple):
        if len(result) >= 2 and result[0]:
            return _pair_from_attrs(result[1])
        return None

    return _pair_from_attrs(result)


def _pair_from_attrs(value: Any) -> tuple[float, float] | None:
    """Extract a pair from CGPoint-like or CGSize-like objects."""
    if value is None:
        return None

    if isinstance(value, tuple | list) and len(value) >= 2:
        return float(value[0]), float(value[1])

    obj = cast(Any, value)

    if hasattr(obj, "x") and hasattr(obj, "y"):
        return float(obj.x), float(obj.y)

    if hasattr(obj, "width") and hasattr(obj, "height"):
        return float(obj.width), float(obj.height)

    return None


def _stringify(value: Any) -> str | None:
    """Convert AX values to a usable string."""
    if value is None:
        return None
    if isinstance(value, str):
        return value
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, int | float):
        return str(value)
    return str(value)


def _truncate(value: str | None, limit: int = 160) -> str | None:
    """Limit long AX strings before sending to the model."""
    if value is None or len(value) <= limit:
        return value
    return value[: limit - 1] + "…"


def _bool_or_none(value: Any) -> bool | None:
    """Convert AX boolean-ish values to bool or None."""
    if value is None:
        return None
    return bool(value)
