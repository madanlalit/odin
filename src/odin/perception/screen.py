import pyautogui  # type: ignore[import-untyped]

class Screen:
    def __init__(self):
        # Store screen dimensions
        self.width, self.height = pyautogui.size()

    def get_screenshot(self):
        """
        Captures and returns a screenshot of the primary monitor.
        """
        try:
            return pyautogui.screenshot()
        except (OSError, IOError) as e:
            # On macOS, lack of Screen Recording permissions often results in a file error
            # because the OS writes an invalid/empty file.
            if "cannot identify image file" in str(e) or "could not create image" in str(e):
                 raise PermissionError(
                    "Failed to capture screenshot. This is likely a permission issue on macOS.\n"
                    "Please ensure your terminal/IDE has 'Screen Recording' permission in:\n"
                    "System Settings -> Privacy & Security -> Screen Recording"
                ) from e
            raise RuntimeError(f"Failed to capture screenshot: {e}")
        except Exception as e:
            # You might want to log this error in a real app
            raise RuntimeError(f"Failed to capture screenshot: {e}")
