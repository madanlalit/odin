from PIL import Image, ImageDraw, ImageFont

class Processing:

    def __init__(self):
        pass

    def draw_grids(self, width, height, step=100):
        """
        Creates a transparent image with a grid overlay and unique numbers.
        """
        # Create a transparent image
        grid_layer = Image.new("RGBA", (width, height), (255, 255, 255, 0))
        draw = ImageDraw.Draw(grid_layer)

        try:
            # Available in Pillow 10.0.0+
            font = ImageFont.load_default(size=24)
        except TypeError:
            # Fallback for older Pillow versions
            font = ImageFont.load_default()

        # Semi-transparent red color for both lines and text
        grid_color = (255, 0, 0, 128)

        # Draw vertical lines
        for x in range(0, width, step):
            draw.line([(x, 0), (x, height)], fill=grid_color, width=1)

        # Draw horizontal lines
        for y in range(0, height, step):
            draw.line([(0, y), (width, y)], fill=grid_color, width=1)

        # Draw Grid Numbers
        counter = 1
        for y in range(0, height, step):
            for x in range(0, width, step):
                text = str(counter)

                # Get text size to center it
                bbox = draw.textbbox((0, 0), text, font=font)
                text_w = bbox[2] - bbox[0]
                text_h = bbox[3] - bbox[1]

                # Center coordinates
                cx = x + step / 2
                cy = y + step / 2

                # Center text
                text_pos = (cx - text_w / 2, cy - text_h / 2)

                # Draw text with the same color
                draw.text(text_pos, text, fill=grid_color, font=font)

                counter += 1

        return grid_layer
    def compress_image(self, image_source, max_size=(1920, 1080)):
        """
        Opens an image (or uses provided PIL Image), converts to RGB, and resizes it.
        Args:
            image_source: File path (str) or PIL Image object.
            max_size: Tuple (width, height) for max dimensions.
        """
        if isinstance(image_source, str):
            image = Image.open(image_source)
        else:
            image = image_source

        if image.mode != 'RGB':
            image = image.convert('RGB')

        image.thumbnail(max_size, Image.Resampling.LANCZOS)
        return image
