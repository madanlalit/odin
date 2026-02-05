"""Tests for action controller and safety bounds handling."""

from unittest.mock import patch

from odin.action.controller import ActionController
from odin.action.safety import SafetyConfig, SafetyController


class TestActionControllerBounds:
    """Coordinate validation tests for ActionController."""

    @patch("odin.action.controller.pyautogui.size", return_value=(1920, 1080))
    def test_validate_coordinates_upper_bound_is_exclusive(self, mock_size):
        """Coordinates at width/height should be rejected."""
        controller = ActionController()

        assert controller._validate_coordinates(1919, 1079) is True
        assert controller._validate_coordinates(1920, 1079) is False
        assert controller._validate_coordinates(1919, 1080) is False


class TestSafetyControllerBounds:
    """Coordinate validation tests for SafetyController."""

    @patch("odin.action.safety.pyautogui.size", return_value=(1000, 800))
    def test_validate_coordinates_margin_upper_bound_is_exclusive(self, mock_size):
        """Upper margin boundary should be considered too close to edge."""
        safety = SafetyController(config=SafetyConfig(bounds_margin=10))

        assert safety.validate_coordinates(989, 789)[0] is True
        assert safety.validate_coordinates(990, 789)[0] is False
        assert safety.validate_coordinates(989, 790)[0] is False
