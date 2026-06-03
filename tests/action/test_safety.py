"""Tests for SafetyController bounds handling."""

from unittest.mock import patch

from odin.action.safety import SafetyConfig, SafetyController
from odin.platform.macos import MacOSBackend


class TestSafetyControllerBounds:
    """Coordinate validation tests for SafetyController."""

    @patch("odin.platform.macos.MacOSBackend.screen_size", return_value=(1000, 800))
    def test_validate_coordinates_margin_upper_bound_is_exclusive(self, _mock_size):
        """Upper margin boundary should be considered too close to edge."""
        safety = SafetyController.from_backend(
            MacOSBackend(),
            config=SafetyConfig(bounds_margin=10),
        )

        assert safety.validate_coordinates(989, 789)[0] is True
        assert safety.validate_coordinates(990, 789)[0] is False
        assert safety.validate_coordinates(989, 790)[0] is False

    def test_refresh_screen_size_reads_from_backend(self):
        """``refresh_screen_size`` updates cached dimensions from the backend."""
        safety = SafetyController(
            config=SafetyConfig(),
            screen_size=(800, 600),
        )

        class FakeBackend:
            def screen_size(self):
                return (1920, 1080)

        safety.refresh_screen_size(backend=FakeBackend())

        assert safety.screen_width == 1920
        assert safety.screen_height == 1080
