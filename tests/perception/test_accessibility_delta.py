"""Tests for accessibility snapshot diffing and stable element IDs."""

from __future__ import annotations

from odin.perception.accessibility import (
    AccessibilitySnapshot,
    AXElementInfo,
    AXFrame,
    _element_payload,
    _stable_element_id,
)


def _make_element(
    element_id: str,
    *,
    role: str | None = "AXButton",
    title: str | None = "OK",
    value: str | None = None,
    description: str | None = None,
    placeholder: str | None = None,
    enabled: bool | None = True,
    focused: bool | None = False,
    actions: list[str] | None = None,
    depth: int = 0,
    frame: AXFrame | None = None,
) -> AXElementInfo:
    """Build an ``AXElementInfo`` for tests with sensible defaults."""
    return AXElementInfo(
        id=element_id,
        role=role,
        title=title,
        value=value,
        description=description,
        placeholder=placeholder,
        frame=frame,
        enabled=enabled,
        focused=focused,
        actions=actions or [],
        depth=depth,
    )


def test_stable_element_id_is_path_scoped() -> None:
    """Same role+title at different positions must not collide."""
    root_path = ()
    child_a_path = (("AXGroup", "root", "0"), ("AXButton", "OK", "0"))
    child_b_path = (
        ("AXGroup", "root", "0"),
        ("AXGroup", "middle", "0"),
        ("AXButton", "OK", "0"),
    )

    id_a = _stable_element_id(child_a_path)
    id_b = _stable_element_id(child_b_path)
    root_id = _stable_element_id(root_path)

    assert id_a != id_b
    assert id_a != root_id
    assert id_b != root_id
    assert id_a.startswith("ax_")
    assert len(id_a) == len("ax_") + 10


def test_stable_element_id_is_deterministic() -> None:
    """Same path always produces the same ID."""
    path = (("AXWindow", "Settings", "0"), ("AXButton", "Save", "0"))
    assert _stable_element_id(path) == _stable_element_id(path)


def test_stable_element_id_disambiguates_identical_siblings() -> None:
    """Identical siblings at the same depth level get distinct stable IDs."""
    sibling_a_path = (("AXGroup", "root", "0"), ("AXButton", "OK", "0"))
    sibling_b_path = (("AXGroup", "root", "0"), ("AXButton", "OK", "1"))

    id_a = _stable_element_id(sibling_a_path)
    id_b = _stable_element_id(sibling_b_path)

    assert id_a != id_b
    assert id_a.startswith("ax_")
    assert id_b.startswith("ax_")


def test_diff_first_step_returns_everything_as_added() -> None:
    """A diff against ``None`` lists every current element as added."""
    snapshot = AccessibilitySnapshot(
        available=True,
        trusted=True,
        app="Test",
        window="Win",
        elements=[
            _make_element("ax_aaa", title="A"),
            _make_element("ax_bbb", title="B"),
        ],
    )

    delta = snapshot.diff(None)

    assert delta.unchanged == []
    assert delta.removed == []
    assert [e.id for e in delta.added] == ["ax_aaa", "ax_bbb"]
    assert delta.changed == []


def test_diff_unchanged_skips_equal_elements() -> None:
    """An element with the same payload is listed by ID, not as changed."""
    first = _make_element("ax_aaa", role="AXButton", title="OK", value="v1", depth=0)
    second = _make_element("ax_aaa", role="AXButton", title="OK", value="v1", depth=99)
    prev = AccessibilitySnapshot(
        available=True, trusted=True, app="X", window="W", elements=[first],
    )
    curr = AccessibilitySnapshot(
        available=True, trusted=True, app="X", window="W", elements=[second],
    )

    delta = curr.diff(prev)

    assert delta.unchanged == ["ax_aaa"]
    assert delta.added == []
    assert delta.changed == []
    assert delta.removed == []


def test_diff_changed_carries_new_payload() -> None:
    """An element whose payload differs is reported in ``changed``."""
    prev_element = _make_element("ax_aaa", role="AXButton", title="OK", value="v1")
    curr_element = _make_element("ax_aaa", role="AXButton", title="OK", value="v2")
    prev = AccessibilitySnapshot(available=True, app="X", window="W", elements=[prev_element])
    curr = AccessibilitySnapshot(available=True, app="X", window="W", elements=[curr_element])

    delta = curr.diff(prev)

    assert delta.unchanged == []
    assert delta.removed == []
    assert [e.id for e in delta.changed] == ["ax_aaa"]


def test_diff_removed_lists_missing_ids() -> None:
    """An element only in ``previous`` is reported in ``removed``."""
    prev = AccessibilitySnapshot(
        available=True, app="X", window="W",
        elements=[_make_element("ax_old", title="Old")],
    )
    curr = AccessibilitySnapshot(available=True, app="X", window="W", elements=[])

    delta = curr.diff(prev)

    assert delta.removed == ["ax_old"]
    assert delta.unchanged == []
    assert delta.added == []
    assert delta.changed == []


def test_delta_context_contains_every_current_id() -> None:
    """The prompt payload references every current element ID."""
    prev_element = _make_element("ax_keep", role="AXButton", title="Keep")
    prev = AccessibilitySnapshot(
        available=True, app="X", window="W", elements=[prev_element],
    )
    curr = AccessibilitySnapshot(
        available=True, app="X", window="W",
        elements=[prev_element, _make_element("ax_new", role="AXButton", title="New")],
    )

    delta = curr.diff(prev)
    context = curr.delta_context(delta)

    assert "delta" in context
    unchanged_ids = {item["id"] for item in context["delta"]["unchanged"]}
    added_ids = {element["id"] for element in context["delta"]["added"]}
    assert "ax_keep" in unchanged_ids
    assert "ax_new" in added_ids


def test_element_payload_excludes_depth() -> None:
    """``depth`` is implicit in the path and must not affect equality."""
    payload_a = _element_payload(_make_element("ax", depth=0))
    payload_b = _element_payload(_make_element("ax", depth=5))

    assert payload_a == payload_b
