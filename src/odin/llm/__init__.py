"""LLM module for vision-capable model providers."""

from odin.llm.base import LLMProvider, LLMResponse
from odin.llm.factory import create_client
from odin.llm.prompts import SIMPLE_PROMPT, SYSTEM_PROMPT, build_system_prompt

__all__ = [
    "LLMProvider",
    "LLMResponse",
    "create_client",
    "SYSTEM_PROMPT",
    "SIMPLE_PROMPT",
    "build_system_prompt",
]
