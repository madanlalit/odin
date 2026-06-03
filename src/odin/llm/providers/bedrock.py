"""AWS Bedrock LLM client with vision support."""

import os
from importlib import import_module
from io import BytesIO
from typing import Any

from PIL import Image

from odin.llm.base import LLMResponse
from odin.llm.context import format_screen_context


class BedrockLLMClient:
    """
    AWS Bedrock Converse API client with vision capabilities.

    The boto3 dependency is optional. Install it with the Bedrock extra before
    constructing this client without an injected SDK client.
    """

    def __init__(
        self,
        model: str = "",
        region_name: str | None = None,
        profile_name: str | None = None,
        inference_config: dict[str, Any] | None = None,
        client: Any | None = None,
    ):
        """
        Initialize the Bedrock client.

        Args:
            model: Bedrock model ID or inference profile ID.
            region_name: AWS region. Uses the AWS SDK default chain if omitted.
            profile_name: AWS profile. Uses the AWS SDK default chain if omitted.
            inference_config: Optional Bedrock Converse inferenceConfig.
            client: Optional injected bedrock-runtime client, primarily for tests.
        """
        self.model = model
        self.inference_config = inference_config

        if client is not None:
            self._client = client
            self._session = None
            return

        boto3 = self._load_boto3()
        session_kwargs = {}
        resolved_region_name = (
            region_name
            or os.environ.get("AWS_REGION")
            or os.environ.get("AWS_REGION_NAME")
        )
        if resolved_region_name:
            session_kwargs["region_name"] = resolved_region_name
        if profile_name:
            session_kwargs["profile_name"] = profile_name

        self._session = boto3.Session(**session_kwargs)
        try:
            self._client = self._session.client("bedrock-runtime")
        except Exception as exc:
            if exc.__class__.__name__ == "NoRegionError":
                raise ValueError(
                    "AWS region required for Bedrock. Set AWS_REGION, "
                    "AWS_DEFAULT_REGION, AWS_REGION_NAME, configure an AWS "
                    "profile, or pass region_name."
                ) from exc
            raise

    @staticmethod
    def _load_boto3() -> Any:
        """Load boto3 only when Bedrock support is used."""
        try:
            return import_module("boto3")
        except ImportError as exc:
            raise ImportError(
                "AWS Bedrock support requires the optional Bedrock dependency. "
                "Install it with `pip install 'odin[bedrock]'` or "
                "`uv sync --extra bedrock`."
            ) from exc

    def _image_bytes(self, image: Image.Image) -> bytes:
        """Encode a PIL Image to JPEG bytes for the AWS SDK."""
        buffer = BytesIO()
        if image.mode in ("RGBA", "P"):
            image = image.convert("RGB")
        image.save(buffer, format="JPEG", quality=85)
        buffer.seek(0)
        return buffer.read()

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
        messages = self._bedrock_history(history)
        user_text = (
            f"Current task: {task}\n\n"
            "Analyze the screenshot and determine the next action batch."
        )
        if screen_context:
            user_text += (
                "\n\nScreen context:\n"
                f"{format_screen_context(screen_context)}"
            )

        user_content: list[dict[str, Any]] = [
            {"text": user_text},
            {
                "image": {
                    "format": "jpeg",
                    "source": {"bytes": self._image_bytes(image)},
                }
            },
        ]
        if messages and messages[-1]["role"] == "user":
            messages[-1]["content"].extend(user_content)
        else:
            messages.append({"role": "user", "content": user_content})

        request: dict[str, Any] = {
            "modelId": self.model,
            "messages": messages,
        }
        if system_prompt:
            request["system"] = [{"text": system_prompt}]
        if self.inference_config:
            request["inferenceConfig"] = self.inference_config

        data = self._client.converse(**request)
        content_blocks = data.get("output", {}).get("message", {}).get("content", [])

        return LLMResponse(
            content=self._extract_text(content_blocks),
            reasoning=self._extract_reasoning(content_blocks),
            usage=data.get("usage"),
        )

    def _bedrock_history(
        self, history: list[dict[str, Any]] | None
    ) -> list[dict[str, Any]]:
        """Convert OpenAI-style chat history to Bedrock Converse messages.

        Bedrock requires the conversation to start with a user message and to
        alternate user/assistant roles. Skip leading assistant messages and
        merge consecutive same-role messages.
        """
        messages: list[dict[str, Any]] = []
        if not history:
            return messages

        for message in history:
            role = message.get("role")
            if role not in {"user", "assistant"}:
                continue

            content = self._content_blocks(message.get("content", ""))
            if not content:
                continue

            if not messages and role != "user":
                continue

            if messages and messages[-1]["role"] == role:
                messages[-1]["content"].extend(content)
                continue

            messages.append({"role": role, "content": content})

        return messages

    def _content_blocks(self, content: Any) -> list[dict[str, Any]]:
        """Convert common chat content formats to Bedrock text blocks."""
        if isinstance(content, str):
            return [{"text": content}] if content else []

        if not isinstance(content, list):
            text = str(content)
            return [{"text": text}] if text else []

        blocks: list[dict[str, Any]] = []
        for item in content:
            if isinstance(item, str):
                if item:
                    blocks.append({"text": item})
                continue

            if not isinstance(item, dict):
                blocks.append({"text": str(item)})
                continue

            if isinstance(item.get("text"), str) or (item.get("type") == "text" and isinstance(item.get("text"), str)):
                blocks.append({"text": item["text"]})

        return blocks

    @staticmethod
    def _extract_text(content_blocks: list[dict[str, Any]]) -> str:
        """Extract all text blocks from a Bedrock Converse response."""
        return "\n".join(
            block["text"]
            for block in content_blocks
            if isinstance(block, dict) and isinstance(block.get("text"), str)
        )

    @staticmethod
    def _extract_reasoning(content_blocks: list[dict[str, Any]]) -> str | None:
        """Extract reasoning text when a Bedrock model returns it."""
        reasoning: list[str] = []
        for block in content_blocks:
            if not isinstance(block, dict):
                continue
            reasoning_content = block.get("reasoningContent")
            if not isinstance(reasoning_content, dict):
                continue
            reasoning_text = reasoning_content.get("reasoningText")
            if isinstance(reasoning_text, dict) and isinstance(
                reasoning_text.get("text"), str
            ):
                reasoning.append(reasoning_text["text"])

        return "\n".join(reasoning) if reasoning else None

    def close(self) -> None:
        """Close the underlying SDK client if supported."""
        close = getattr(self._client, "close", None)
        if callable(close):
            close()

    def __enter__(self):
        return self

    def __exit__(self, *args):
        self.close()
