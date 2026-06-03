"""Platform-specific backends for input simulation and screen capture."""

from odin.platform.base import PlatformBackend, default_backend
from odin.platform.macos import MacOSBackend

__all__ = ["MacOSBackend", "PlatformBackend", "default_backend"]
