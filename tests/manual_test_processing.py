import sys
import os
from PIL import Image

# Add src to python path so we can import odin
sys.path.insert(0, os.path.abspath(os.path.join(os.path.dirname(__file__), '../src')))

from odin.perception.screen import Screen
from odin.perception.processing import Processing

def main():
    try:
        # 1. Take Screenshot
        print("Initializing Screen...")
        screen = Screen()
        screenshot = screen.get_screenshot()

        # Save original for compress_image which expects a file path
        screenshot_path = "test_original.png"
        screenshot.save(screenshot_path)
        print(f"Screenshot saved to {screenshot_path} ({screenshot.width}x{screenshot.height})")

        # 2. Initialize Processing
        processor = Processing()

        # 3. Create Grid
        print("Generating grid...")
        grid = processor.draw_grids(screenshot.width, screenshot.height)

        # Save grid alone
        grid_path = "test_grid.png"
        grid.save(grid_path)
        print(f"Grid layer saved to {grid_path}")

        # Create a combined image (Screenshot + Grid) to verify alignment
        # We need to convert screenshot to RGBA to alpha_composite with the transparent grid
        print("Creating combined preview...")
        combined = Image.alpha_composite(screenshot.convert("RGBA"), grid)
        combined.save("test_combined.png")
        print("Combined image saved to test_combined.png")

        # 4. Compress Image
        # processing.compress_image now accepts a PIL Image object
        print("Compressing combined image...")
        compressed = processor.compress_image(combined)
        compressed_path = "test_compressed.png"
        compressed.save(compressed_path)
        print(f"Compressed image (with grid) saved to {compressed_path} ({compressed.width}x{compressed.height})")

        print("Test PASSED")
    except Exception as e:
        print(f"Test FAILED: {e}")
        import traceback
        traceback.print_exc()

if __name__ == "__main__":
    main()
