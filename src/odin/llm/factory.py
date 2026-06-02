"""Factory for constructing configured LLM providers."""

import os
from typing import Any

from odin.llm.base import LLMProvider


def create_client(
    api_key: str | None = None,
    model: str | None = None,
    provider: str | None = None,
    region_name: str | None = None,
    profile_name: str | None = None,
    inference_config: dict[str, Any] | None = None,
) -> LLMProvider:
    """
    Create an LLM provider client.

    Args:
        api_key: OpenRouter API key (or set OPENROUTER_API_KEY env var).
        model: Provider-specific model to use for inference. Required.
        provider: LLM provider ("openrouter" or "bedrock"). Defaults to
                  ODIN_LLM_PROVIDER or infers the provider from model prefixes.
        region_name: AWS region for Bedrock. Uses the AWS SDK default chain if omitted.
        profile_name: AWS profile for Bedrock. Uses the AWS SDK default chain if omitted.
        inference_config: Optional Bedrock Converse inferenceConfig.

    Returns:
        Configured LLM provider instance.
    """
    if not model or not model.strip():
        raise ValueError("A model identifier is required.")

    provider_name = _resolve_provider(provider, model)

    if provider_name == "openrouter":
        from odin.llm.providers.openrouter import OpenRouterLLMClient

        return OpenRouterLLMClient(
            api_key=api_key,
            model=_strip_model_prefix(model, "openrouter"),
        )

    if provider_name == "bedrock":
        from odin.llm.providers.bedrock import BedrockLLMClient

        return BedrockLLMClient(
            model=_strip_model_prefix(model, "bedrock"),
            region_name=region_name,
            profile_name=profile_name,
            inference_config=inference_config,
        )

    raise ValueError(
        f"Unsupported LLM provider '{provider_name}'. "
        "Expected 'openrouter' or 'bedrock'."
    )


def _resolve_provider(provider: str | None, model: str | None) -> str:
    """Resolve provider from explicit argument, env, or model prefix."""
    if provider:
        return _normalize_provider(provider)

    env_provider = os.environ.get("ODIN_LLM_PROVIDER")
    if env_provider:
        return _normalize_provider(env_provider)

    if model and model.startswith("bedrock/"):
        return "bedrock"
    if model and model.startswith("openrouter/"):
        return "openrouter"

    return "openrouter"


def _normalize_provider(provider: str) -> str:
    """Normalize supported provider aliases."""
    provider = provider.lower().replace("_", "-")
    if provider in {"openrouter", "open-router"}:
        return "openrouter"
    if provider in {"bedrock", "aws-bedrock"}:
        return "bedrock"
    return provider


def _strip_model_prefix(model: str, provider: str) -> str:
    """Strip optional provider prefix from a model identifier."""
    prefix = f"{provider}/"
    if model.startswith(prefix):
        return model[len(prefix) :]
    return model
