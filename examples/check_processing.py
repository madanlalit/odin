import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../src")))

from odin.perception.processing import Processing
from odin.perception.screen import Screen


def main():
    try:
        print("Initializing Screen...")
        screen = Screen()
        screenshot = screen.get_screenshot()

        screenshot_path = "test_original.png"
        screenshot.save(screenshot_path)
        print(
            f"Screenshot saved to {screenshot_path} "
            f"({screenshot.width}x{screenshot.height})"
        )

        processor = Processing()

        print("Compressing screenshot...")
        compressed = processor.compress_image(screenshot)
        compressed_path = "test_compressed.png"
        compressed.save(compressed_path)
        print(
            f"Compressed image saved to {compressed_path} "
            f"({compressed.width}x{compressed.height})"
        )

        print("Check passed")
    except Exception as e:
        print(f"Check failed: {e}")
        import traceback

        traceback.print_exc()


if __name__ == "__main__":
    main()
