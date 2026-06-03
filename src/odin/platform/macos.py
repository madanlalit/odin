"""macOS-native backend using Quartz / CoreGraphics.

Replaces pyautogui with direct CGEvent calls for mouse, keyboard, and scroll
input, and CGWindowListCreateImage for screenshot capture.  This avoids the
overhead of shelling out to ``screencapture`` and provides proper Unicode
text entry via the system clipboard.
"""

from __future__ import annotations

import time
from typing import Literal

from PIL import Image

_quartz = None
_appkit = None


def _load_quartz():
    global _quartz
    if _quartz is None:
        import Quartz  # type: ignore[import-untyped]

        _quartz = Quartz
    return _quartz


def _load_appkit():
    global _appkit
    if _appkit is None:
        import AppKit  # type: ignore[import-untyped]

        _appkit = AppKit
    return _appkit


_KEY_CODES: dict[str, int] = {
    "a": 0x00, "s": 0x01, "d": 0x02, "f": 0x03, "h": 0x04,
    "g": 0x05, "z": 0x06, "x": 0x07, "c": 0x08, "v": 0x09,
    "b": 0x0B, "q": 0x0C, "w": 0x0D, "e": 0x0E, "r": 0x0F,
    "y": 0x10, "t": 0x11, "1": 0x12, "2": 0x13, "3": 0x14,
    "4": 0x15, "6": 0x16, "5": 0x17, "7": 0x1A, "8": 0x1C,
    "9": 0x19, "0": 0x1D, "=": 0x18, "-": 0x1B, "]": 0x1E,
    "o": 0x1F, "u": 0x20, "[": 0x21, "i": 0x22, "p": 0x23,
    "l": 0x25, "j": 0x26, "'": 0x27, "k": 0x28, ";": 0x29,
    "\\": 0x2A, ",": 0x2B, "/": 0x2C, "n": 0x2D, "m": 0x2E,
    ".": 0x2F, "`": 0x32, " ": 0x31,
    "return": 0x24, "enter": 0x24, "tab": 0x30, "space": 0x31,
    "delete": 0x33, "backspace": 0x33, "escape": 0x35, "esc": 0x35,
    "command": 0x37, "shift": 0x38, "capslock": 0x39,
    "option": 0x3A, "alt": 0x3A,
    "ctrl": 0x3B, "control": 0x3B,
    "fn": 0x3F,
    "f1": 0x7A, "f2": 0x78, "f3": 0x63, "f4": 0x76,
    "f5": 0x60, "f6": 0x61, "f7": 0x62, "f8": 0x64,
    "f9": 0x65, "f10": 0x6D, "f11": 0x67, "f12": 0x6F,
    "left": 0x7B, "right": 0x7C, "down": 0x7D, "up": 0x7E,
    "home": 0x73, "end": 0x77, "pageup": 0x74, "pagedown": 0x79,
    "forwarddelete": 0x75,
}

_MODIFIER_FLAGS: dict[str, int] = {
    "command": 0x00100000,
    "shift":   0x00020000,
    "option":  0x00080000,
    "alt":     0x00080000,
    "ctrl":    0x00040000,
    "control": 0x00040000,
    "fn":      0x00800000,
}

_MODIFIER_NAMES = frozenset(_MODIFIER_FLAGS.keys())


class MacOSBackend:
    """macOS-native input simulation and screen capture via Quartz."""


    @staticmethod
    def screen_size() -> tuple[int, int]:
        """Return (width, height) of the main display in points."""
        Quartz = _load_quartz()
        bounds = Quartz.CGDisplayBounds(Quartz.CGMainDisplayID())
        return int(bounds.size.width), int(bounds.size.height)


    @staticmethod
    def mouse_position() -> tuple[int, int]:
        """Return current mouse (x, y) in screen coordinates."""
        AppKit = _load_appkit()
        Quartz = _load_quartz()
        loc = AppKit.NSEvent.mouseLocation()
        main_height = Quartz.CGDisplayBounds(Quartz.CGMainDisplayID()).size.height
        return int(loc.x), int(main_height - loc.y)

    @staticmethod
    def click(
        x: int,
        y: int,
        button: Literal["left", "right", "middle"] = "left",
    ) -> None:
        """Click at (x, y)."""
        Quartz = _load_quartz()
        point = Quartz.CGPointMake(float(x), float(y))

        if button == "right":
            down_type = Quartz.kCGEventRightMouseDown
            up_type = Quartz.kCGEventRightMouseUp
            mouse_button = Quartz.kCGMouseButtonRight
        elif button == "middle":
            down_type = Quartz.kCGEventOtherMouseDown
            up_type = Quartz.kCGEventOtherMouseUp
            mouse_button = Quartz.kCGMouseButtonCenter
        else:
            down_type = Quartz.kCGEventLeftMouseDown
            up_type = Quartz.kCGEventLeftMouseUp
            mouse_button = Quartz.kCGMouseButtonLeft

        down = Quartz.CGEventCreateMouseEvent(None, down_type, point, mouse_button)
        up = Quartz.CGEventCreateMouseEvent(None, up_type, point, mouse_button)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, down)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, up)

    @staticmethod
    def double_click(x: int, y: int) -> None:
        """Double-click at (x, y)."""
        Quartz = _load_quartz()
        point = Quartz.CGPointMake(float(x), float(y))

        down = Quartz.CGEventCreateMouseEvent(
            None, Quartz.kCGEventLeftMouseDown, point, Quartz.kCGMouseButtonLeft,
        )
        up = Quartz.CGEventCreateMouseEvent(
            None, Quartz.kCGEventLeftMouseUp, point, Quartz.kCGMouseButtonLeft,
        )
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, down)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, up)
        Quartz.CGEventSetIntegerValueField(
            down, Quartz.kCGMouseEventClickState, 2,
        )
        Quartz.CGEventSetIntegerValueField(
            up, Quartz.kCGMouseEventClickState, 2,
        )
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, down)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, up)

    @staticmethod
    def move(x: int, y: int) -> None:
        """Move the mouse to (x, y) instantly."""
        Quartz = _load_quartz()
        point = Quartz.CGPointMake(float(x), float(y))
        event = Quartz.CGEventCreateMouseEvent(
            None, Quartz.kCGEventMouseMoved, point, Quartz.kCGMouseButtonLeft,
        )
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)

    @staticmethod
    def drag(
        start_x: int,
        start_y: int,
        end_x: int,
        end_y: int,
        duration: float = 0.5,
    ) -> None:
        """Drag from (start_x, start_y) to (end_x, end_y)."""
        Quartz = _load_quartz()
        steps = max(int(duration * 60), 2)
        dt = duration / steps

        start = Quartz.CGPointMake(float(start_x), float(start_y))
        down = Quartz.CGEventCreateMouseEvent(
            None, Quartz.kCGEventLeftMouseDown, start, Quartz.kCGMouseButtonLeft,
        )
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, down)

        for i in range(1, steps + 1):
            t = i / steps
            cx = start_x + (end_x - start_x) * t
            cy = start_y + (end_y - start_y) * t
            point = Quartz.CGPointMake(cx, cy)
            drag_event = Quartz.CGEventCreateMouseEvent(
                None, Quartz.kCGEventLeftMouseDragged, point, Quartz.kCGMouseButtonLeft,
            )
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, drag_event)
            time.sleep(dt)

        end = Quartz.CGPointMake(float(end_x), float(end_y))
        up = Quartz.CGEventCreateMouseEvent(
            None, Quartz.kCGEventLeftMouseUp, end, Quartz.kCGMouseButtonLeft,
        )
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, up)


    @staticmethod
    def _key_event(keycode: int, down: bool, flags: int = 0) -> None:
        """Post a single key-down or key-up event."""
        Quartz = _load_quartz()
        event = Quartz.CGEventCreateKeyboardEvent(None, keycode, down)
        if flags:
            Quartz.CGEventSetFlags(event, flags)
        Quartz.CGEventPost(Quartz.kCGHIDEventTap, event)

    @classmethod
    def hotkey(cls, *keys: str) -> None:
        """Press a key combination (e.g. ``hotkey("command", "c")``)."""
        flags = 0
        regular_keys: list[str] = []
        for key in keys:
            low = key.lower()
            if low in _MODIFIER_NAMES:
                flags |= _MODIFIER_FLAGS[low]
            else:
                regular_keys.append(low)

        for key in keys:
            low = key.lower()
            if low in _MODIFIER_NAMES:
                kc = _KEY_CODES.get(low)
                if kc is not None:
                    cls._key_event(kc, down=True, flags=flags)

        for key in regular_keys:
            kc = _KEY_CODES.get(key)
            if kc is not None:
                cls._key_event(kc, down=True, flags=flags)
                cls._key_event(kc, down=False, flags=flags)

        for key in reversed(keys):
            low = key.lower()
            if low in _MODIFIER_NAMES:
                kc = _KEY_CODES.get(low)
                if kc is not None:
                    cls._key_event(kc, down=False, flags=0)

    @classmethod
    def type_text(cls, text: str) -> None:
        """Type *text* via the system clipboard (supports full Unicode)."""
        AppKit = _load_appkit()

        pasteboard = AppKit.NSPasteboard.generalPasteboard()
        old_types = pasteboard.types()
        old_items: list[tuple] = []
        if old_types:
            for t in old_types:
                data = pasteboard.dataForType_(t)
                if data is not None:
                    old_items.append((t, data))

        pasteboard.clearContents()
        pasteboard.setString_forType_(text, AppKit.NSPasteboardTypeString)

        cls.hotkey("command", "v")
        time.sleep(0.05)

        pasteboard.clearContents()
        for ptype, pdata in old_items:
            pasteboard.setData_forType_(pdata, ptype)


    @staticmethod
    def scroll(
        direction: Literal["up", "down", "left", "right"],
        clicks: int = 3,
        x: int | None = None,
        y: int | None = None,
    ) -> None:
        """Scroll *clicks* units in *direction*, optionally at (x, y)."""
        Quartz = _load_quartz()

        if x is not None and y is not None:
            point = Quartz.CGPointMake(float(x), float(y))
            move_event = Quartz.CGEventCreateMouseEvent(
                None, Quartz.kCGEventMouseMoved, point, Quartz.kCGMouseButtonLeft,
            )
            Quartz.CGEventPost(Quartz.kCGHIDEventTap, move_event)
            time.sleep(0.01)

        if direction in ("up", "down"):
            dy = clicks if direction == "up" else -clicks
            scroll_event = Quartz.CGEventCreateScrollWheelEvent(
                None,
                Quartz.kCGScrollEventUnitLine,
                1,
                dy,
            )
        else:
            dx = clicks if direction == "right" else -clicks
            scroll_event = Quartz.CGEventCreateScrollWheelEvent(
                None,
                Quartz.kCGScrollEventUnitLine,
                2,
                0,
                dx,
            )

        Quartz.CGEventPost(Quartz.kCGHIDEventTap, scroll_event)


    @staticmethod
    def _cgimage_to_pil(image_ref) -> Image.Image:
        """Convert a CGImageRef to a PIL Image."""
        Quartz = _load_quartz()
        width = Quartz.CGImageGetWidth(image_ref)
        height = Quartz.CGImageGetHeight(image_ref)
        bytes_per_row = Quartz.CGImageGetBytesPerRow(image_ref)
        data_provider = Quartz.CGImageGetDataProvider(image_ref)
        raw_data = Quartz.CGDataProviderCopyData(data_provider)
        img = Image.frombytes(
            "RGBA", (width, height), raw_data, "raw", "BGRA", bytes_per_row, 1,
        )
        return img.convert("RGB")

    @staticmethod
    def screenshot() -> Image.Image:
        """Capture the entire main display and return a PIL Image.

        Uses ``CGWindowListCreateImage`` which is significantly faster than
        shelling out to ``screencapture``.
        """
        Quartz = _load_quartz()

        image_ref = Quartz.CGWindowListCreateImage(
            Quartz.CGRectInfinite,
            Quartz.kCGWindowListOptionOnScreenOnly,
            Quartz.kCGNullWindowID,
            Quartz.kCGWindowImageDefault,
        )

        if image_ref is None:
            raise PermissionError(
                "Failed to capture screenshot. This is likely a permission issue on macOS.\n"
                "Please ensure your terminal/IDE has 'Screen Recording' permission in:\n"
                "System Settings -> Privacy & Security -> Screen Recording"
            )

        return MacOSBackend._cgimage_to_pil(image_ref)

    @staticmethod
    def frontmost_app() -> dict[str, str | int | None]:
        """Return info about the frontmost application.

        Keys: ``name``, ``bundle_id``, ``pid``.
        """
        AppKit = _load_appkit()
        app = AppKit.NSWorkspace.sharedWorkspace().frontmostApplication()
        if app is None:
            return {"name": None, "bundle_id": None, "pid": None}
        return {
            "name": app.localizedName(),
            "bundle_id": app.bundleIdentifier(),
            "pid": app.processIdentifier(),
        }

    @staticmethod
    def running_apps() -> list[dict[str, str | int | bool | None]]:
        """Return running macOS applications, including apps on other Spaces."""
        AppKit = _load_appkit()
        workspace = AppKit.NSWorkspace.sharedWorkspace()
        frontmost = workspace.frontmostApplication()
        frontmost_pid = frontmost.processIdentifier() if frontmost is not None else None
        regular_policy = getattr(AppKit, "NSApplicationActivationPolicyRegular", 0)

        apps: list[dict[str, str | int | bool | None]] = []
        for app in workspace.runningApplications() or []:
            try:
                activation_policy = int(app.activationPolicy())
            except Exception:
                activation_policy = None

            pid = app.processIdentifier()
            apps.append({
                "name": app.localizedName(),
                "bundle_id": app.bundleIdentifier(),
                "pid": pid,
                "is_active": bool(pid == frontmost_pid),
                "is_hidden": bool(app.isHidden()),
                "activation_policy": activation_policy,
                "user_facing": (
                    activation_policy == regular_policy
                    if activation_policy is not None
                    else None
                ),
            })
        return apps

    @staticmethod
    def window_list(
        *,
        on_screen_only: bool = True,
        for_pid: int | None = None,
    ) -> list[dict[str, object]]:
        """Return a list of visible windows with name, bounds, owner, and id.

        When *for_pid* is given, only windows owned by that process are
        returned.
        """
        Quartz = _load_quartz()
        option = (
            Quartz.kCGWindowListOptionOnScreenOnly
            if on_screen_only
            else Quartz.kCGWindowListOptionAll
        )
        option |= Quartz.kCGWindowListExcludeDesktopElements

        raw = Quartz.CGWindowListCopyWindowInfo(option, Quartz.kCGNullWindowID)
        if raw is None:
            return []

        windows: list[dict[str, object]] = []
        for info in raw:
            pid = int(info.get("kCGWindowOwnerPID", 0))
            if for_pid is not None and pid != for_pid:
                continue
            name = info.get("kCGWindowName") or info.get("kCGWindowOwnerName")
            layer = int(info.get("kCGWindowLayer", 0))
            if layer != 0:
                continue
            bounds = info.get("kCGWindowBounds", {})
            windows.append({
                "window_id": int(info.get("kCGWindowNumber", 0)),
                "owner_name": str(info.get("kCGWindowOwnerName", "")),
                "owner_pid": pid,
                "title": str(name) if name else None,
                "x": int(bounds.get("X", 0)),
                "y": int(bounds.get("Y", 0)),
                "width": int(bounds.get("Width", 0)),
                "height": int(bounds.get("Height", 0)),
            })
        return windows
