"""Action module for GUI automation."""

from odin.action.controller import ActionController, ActionResult
from odin.action.safety import SafetyConfig, SafetyController

__all__ = [
    "ActionController",
    "ActionResult",
    "SafetyController",
    "SafetyConfig",
]
