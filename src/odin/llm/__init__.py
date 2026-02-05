"""LLM module for OpenRouter-based vision models."""

from odin.llm.client import LLMClient, LLMResponse, create_client
from odin.llm.prompts import SIMPLE_PROMPT, SYSTEM_PROMPT

__all__ = [
    "LLMClient",
    "LLMResponse",
    "create_client",
    "SYSTEM_PROMPT",
    "SIMPLE_PROMPT",
]
