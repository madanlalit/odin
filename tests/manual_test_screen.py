import sys
import os

# Add src to python path so we can import odin
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../src')))

from odin.perception.screen import Screen

try:
    s = Screen()
    print(f"Screen initialized. Size: {s.width}x{s.height}")

    img = s.get_screenshot()
    print(f"Screenshot captured. Image size: {img.size}")
    print("Test PASSED")
except Exception as e:
    print(f"Test FAILED: {e}")
