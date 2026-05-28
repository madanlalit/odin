"""Keyboard key normalization helpers."""

from collections.abc import Iterable


KEY_ALIASES: dict[str, str] = {
    "cmd": "command",
    "command": "command",
    "meta": "command",
    "super": "command",
    "control": "ctrl",
    "ctl": "ctrl",
    "ctrl": "ctrl",
    "option": "option",
    "opt": "option",
}


def normalize_key(key: str) -> str:
    """Normalize common model/user key aliases to standard key names."""
    normalized = key.strip().lower().replace(" ", "")
    return KEY_ALIASES.get(normalized, normalized)


def normalize_keys(keys: Iterable[str]) -> list[str]:
    """Normalize a sequence of keyboard shortcut keys."""
    return [normalize_key(key) for key in keys]
