"""Tests for ActionController bounds and key handling."""

from unittest.mock import patch

from odin.action.controller import ActionController


class TestActionControllerBounds:
    """Coordinate validation tests for ActionController."""

    @patch("odin.platform.macos.MacOSBackend.screen_size", return_value=(1920, 1080))
    def test_validate_coordinates_upper_bound_is_exclusive(self, mock_size):
        """Coordinates at width/height should be rejected."""
        controller = ActionController()

        assert controller._validate_coordinates(1919, 1079) is True
        assert controller._validate_coordinates(1920, 1079) is False
        assert controller._validate_coordinates(1919, 1080) is False

    @patch("odin.platform.macos.MacOSBackend.hotkey")
    @patch("odin.platform.macos.MacOSBackend.screen_size", return_value=(1920, 1080))
    def test_hotkey_normalizes_key_aliases(self, mock_size, mock_hotkey):
        """Common key aliases are normalized before calling the backend."""
        controller = ActionController()

        result = controller.hotkey("cmd", "space")

        assert result.success is True
        assert result.message == "Pressed: command+space"
        mock_hotkey.assert_called_once_with("command", "space")
