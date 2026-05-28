"""Tests for SafetyController bounds handling."""

from unittest.mock import patch

from odin.action.safety import SafetyConfig, SafetyController


class TestSafetyControllerBounds:
    """Coordinate validation tests for SafetyController."""

    @patch("odin.platform.macos.MacOSBackend.screen_size", return_value=(1000, 800))
    def test_validate_coordinates_margin_upper_bound_is_exclusive(self, mock_size):
        """Upper margin boundary should be considered too close to edge."""
        safety = SafetyController(config=SafetyConfig(bounds_margin=10))

        assert safety.validate_coordinates(989, 789)[0] is True
        assert safety.validate_coordinates(990, 789)[0] is False
        assert safety.validate_coordinates(989, 790)[0] is False
