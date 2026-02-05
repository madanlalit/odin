"""LLM Client for OpenRouter API with vision support."""

import base64
import os
from dataclasses import dataclass
from io import BytesIO
from typing import Any

import httpx
from PIL import Image


@dataclass
class LLMResponse:
    """Response from the LLM."""

    content: str
    reasoning: str | None = None
    usage: dict[str, int] | None = None


class LLMClient:
    """
    OpenRouter-based LLM client with vision capabilities.

    Uses OpenRouter to access various vision-capable models like
    GPT-4 Vision, Claude 3, Gemini Pro Vision, etc.
    """

    OPENROUTER_API_URL = "https://openrouter.ai/api/v1/chat/completions"

    def __init__(
        self,
        api_key: str | None = None,
        model: str = "",
    ):
        """
        Initialize the LLM client.

        Args:
            api_key: OpenRouter API key. If not provided, reads from
                     OPENROUTER_API_KEY environment variable.
            model: Model identifier (e.g., "openai/gpt-4-vision-preview",
                   "anthropic/claude-3-opus", "google/gemini-pro-vision")

        """
        self.api_key = api_key or os.environ.get("OPENROUTER_API_KEY")
        if not self.api_key:
            raise ValueError(
                "OpenRouter API key required. Set OPENROUTER_API_KEY environment "
                "variable or pass api_key parameter."
            )

        self.model = model

        self._client = httpx.Client(timeout=120.0)

    def _encode_image(self, image: Image.Image) -> str:
        """Encode a PIL Image to base64 string."""
        buffer = BytesIO()
        # Convert to RGB if necessary (e.g., RGBA screenshots)
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
    ) -> LLMResponse:
        """
        Analyze a screenshot and determine the next action.

        Args:
            image: PIL Image of the current screen state.
            task: The user's task/goal to accomplish.
            system_prompt: System prompt with instructions.
            history: Previous conversation history (optional).

        Returns:
            LLMResponse with the model's analysis and suggested action.
        """
        image_base64 = self._encode_image(image)

        messages: list[dict[str, Any]] = [{"role": "system", "content": system_prompt}]

        # Add conversation history if provided
        if history:
            messages.extend(history)

        # Add current message with screenshot
        messages.append(
            {
                "role": "user",
                "content": [
                    {
                        "type": "text",
                        "text": f"Current task: {task}\n\nAnalyze the screenshot and determine the next action.",
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

    def close(self):
        """Close the HTTP client."""
        self._client.close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()


def create_client(
    api_key: str | None = None,
    model: str = "google/gemini-2.0-flash-001",
) -> LLMClient:
    """
    Factory function to create an LLM client.

    Args:
        api_key: OpenRouter API key (or set OPENROUTER_API_KEY env var).
        model: Model to use for inference.

    Returns:
        Configured LLMClient instance.
    """
    return LLMClient(api_key=api_key, model=model)
