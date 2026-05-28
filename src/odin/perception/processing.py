"""Image processing helpers for screen captures."""

from PIL import Image


class Processing:
    """Image processing utilities."""

    def compress_image(self, image_source, max_size=(1920, 1080)):
        """
        Open an image or use a provided PIL Image, convert it to RGB, and resize it.

        Args:
            image_source: File path or PIL Image object.
            max_size: Max dimensions as (width, height).
        """
        if isinstance(image_source, str):
            image = Image.open(image_source)
        else:
            image = image_source

        if image.mode != "RGB":
            image = image.convert("RGB")

        image.thumbnail(max_size, Image.Resampling.LANCZOS)
        return image
