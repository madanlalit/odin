"""Tests for macOS accessibility normalization helpers."""

from odin.perception.accessibility import Accessibility


class FakeNSArray:
    """Small iterable stand-in for PyObjC NSArray values."""

    def __init__(self, *items):
        self._items = items

    def __iter__(self):
        return iter(self._items)


class FakeAX:
    """Minimal ApplicationServices stand-in for accessibility unit tests."""

    kAXChildrenAttribute = "AXChildren"

    def AXUIElementCopyActionNames(self, _element, _error):
        return 0, FakeNSArray("AXPress", "AXShowMenu")


def test_children_accepts_pyobjc_iterable_collections():
    """PyObjC NSArray children should not be dropped from the prompt tree."""
    accessibility = Accessibility()
    accessibility._ax = FakeAX()
    child_1 = object()
    child_2 = object()

    def fake_copy_attr(_element, _attr):
        return FakeNSArray(child_1, child_2)

    accessibility._copy_attr = fake_copy_attr  # type: ignore[method-assign]

    assert accessibility._children(object()) == [child_1, child_2]


def test_actions_accepts_pyobjc_iterable_collections():
    """PyObjC NSArray action names should become prompt-safe string actions."""
    accessibility = Accessibility()
    accessibility._ax = FakeAX()

    assert accessibility._actions(object()) == ["AXPress", "AXShowMenu"]


def test_frontmost_application_falls_back_to_window_server_pid(monkeypatch):
    """AX capture can recover when system focused-app lookup is empty."""
    from odin.platform.macos import MacOSBackend

    expected_app = object()

    class FakeAXWithApplication(FakeAX):
        def AXUIElementCreateApplication(self, pid):
            assert pid == 1234
            return expected_app

    monkeypatch.setattr(
        MacOSBackend,
        "frontmost_app",
        staticmethod(lambda: {"name": "Test", "bundle_id": "test.app", "pid": 1234}),
    )

    accessibility = Accessibility()

    assert accessibility._frontmost_application(FakeAXWithApplication()) is expected_app
