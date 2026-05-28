import os
import sys

sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), "../src")))

from odin.perception.screen import Screen


def main():
    try:
        screen = Screen()
        print(f"Screen initialized. Size: {screen.width}x{screen.height}")

        image = screen.get_screenshot()
        print(f"Screenshot captured. Image size: {image.size}")
        print("Check passed")
    except Exception as e:
        print(f"Check failed: {e}")


if __name__ == "__main__":
    main()
