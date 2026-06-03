"""Shared LLM provider contracts and data types."""

from typing import Any, Protocol

from PIL import Image
from pydantic import BaseModel


class LLMResponse(BaseModel):
    """Response from the LLM."""

    content: str
    reasoning: str | None = None
    usage: dict[str, Any] | None = None


class LLMProvider(Protocol):
    """Provider interface used by the agent."""

    model: str

    def analyze_screen(
        self,
        image: Image.Image,
        task: str,
        system_prompt: str,
        history: list[dict[str, Any]] | None = None,
        screen_context: dict[str, Any] | None = None,
    ) -> LLMResponse:
        """Analyze a screenshot and return the model response."""
        ...

    def close(self) -> None:
        """Release provider resources."""
        ...
