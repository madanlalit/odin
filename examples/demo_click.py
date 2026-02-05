#!/usr/bin/env python
"""
Simple demo - click at coordinates to verify pyautogui is working.

Run with:
    uv run python examples/demo_click.py
"""

import time

from odin.action.controller import ActionController
from odin.perception.screen import Screen


def main():
    print("🔱 Odin Click Demo")
    print("-" * 40)

    # Initialize
    screen = Screen()
    controller = ActionController()

    print(f"Screen size: {screen.width}x{screen.height}")
    print(f"Current mouse position: {controller.get_mouse_position()}")

    # Move to center
    center_x = screen.width // 2
    center_y = screen.height // 2

    print(f"\nMoving mouse to center ({center_x}, {center_y}) in 2 seconds...")
    time.sleep(2)

    result = controller.move(center_x, center_y)
    print(f"Move result: {result.message}")

    print("\nDemo complete! If the mouse moved, everything is working.")


if __name__ == "__main__":
    main()
