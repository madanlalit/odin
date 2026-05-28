"""OpenRouter LLM client with vision support."""

import base64
import os
from importlib import import_module
from io import BytesIO
from typing import Any

from PIL import Image

from odin.llm.base import DEFAULT_OPENROUTER_MODEL, LLMResponse
from odin.llm.context import format_screen_context


class OpenRouterLLMClient:
    """
    OpenRouter-based LLM client with vision capabilities.

    The httpx dependency is optional. Install it with the OpenRouter extra
    before constructing this client without an injected HTTP client.
    """

    OPENROUTER_API_URL = "https://openrouter.ai/api/v1/chat/completions"

    def __init__(
        self,
        api_key: str | None = None,
        model: str = DEFAULT_OPENROUTER_MODEL,
        client: Any | None = None,
    ):
        """
        Initialize the OpenRouter client.

        Args:
            api_key: OpenRouter API key. If not provided, reads from
                     OPENROUTER_API_KEY environment variable.
            model: OpenRouter model identifier.
            client: Optional injected HTTP client, primarily for tests.
        """
        self.api_key = api_key or os.environ.get("OPENROUTER_API_KEY")
        if not self.api_key:
            raise ValueError(
                "OpenRouter API key required. Set OPENROUTER_API_KEY environment "
                "variable or pass api_key parameter."
            )

        self.model = model
        self._client = client or self._load_httpx().Client(timeout=120.0)

    @staticmethod
    def _load_httpx() -> Any:
        """Load httpx only when OpenRouter support is used."""
        try:
            return import_module("httpx")
        except ImportError as exc:
            raise ImportError(
                "OpenRouter support requires the optional OpenRouter dependency. "
                "Install it with `pip install 'odin[openrouter]'` or "
                "`uv sync --extra openrouter`."
            ) from exc

    def _encode_image(self, image: Image.Image) -> str:
        """Encode a PIL Image to base64 string."""
        buffer = BytesIO()
        if image.mode in ("RGBA", "P"):
            image = image.convert("RGB")
        image.save(buffer, format="JPEG", quality=85)
        buffer.seek(0)
        return base64.b64encode(buffer.read()).decode("utf-8")

    def analyze_screen(
        self,
        image: Image.Image,
        task: str,
        system_prompt: str,
        history: list[dict[str, Any]] | None = None,
        screen_context: dict[str, Any] | None = None,
    ) -> LLMResponse:
        """
        Analyze a screenshot and determine the next action batch.

        Args:
            image: PIL Image of the current screen state.
            task: The user's task/goal to accomplish.
            system_prompt: System prompt with instructions.
            history: Previous conversation history (optional).

        Returns:
            LLMResponse with the model's analysis and suggested action batch.
        """
        image_base64 = self._encode_image(image)

        messages: list[dict[str, Any]] = [{"role": "system", "content": system_prompt}]

        if history:
            messages.extend(history)

        user_text = (
            f"Current task: {task}\n\n"
            "Analyze the screenshot and determine the next action batch."
        )
        if screen_context:
            user_text += (
                "\n\nScreen context:\n"
                f"{format_screen_context(screen_context)}"
            )

        messages.append(
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": user_text,
                    },
                    {
                        "type": "image_url",
                        "image_url": {
                            "url": f"data:image/jpeg;base64,{image_base64}",
                        },
                    },
                ],
            }
        )

        response = self._client.post(
            self.OPENROUTER_API_URL,
            headers={
                "Authorization": f"Bearer {self.api_key}",
                "Content-Type": "application/json",
            },
            json={
                "model": self.model,
                "messages": messages,
            },
        )

        response.raise_for_status()
        data = response.json()

        choice = data["choices"][0]
        message = choice["message"]

        return LLMResponse(
            content=message.get("content", ""),
            reasoning=message.get("reasoning"),
            usage=data.get("usage"),
        )

    def close(self) -> None:
        """Close the HTTP client."""
        self._client.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
