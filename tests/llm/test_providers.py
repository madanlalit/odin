"""Tests for LLM provider clients."""

import os
from unittest.mock import MagicMock, patch

import pytest
from PIL import Image

from odin.llm.base import DEFAULT_BEDROCK_MODEL, DEFAULT_OPENROUTER_MODEL
from odin.llm.factory import create_client
from odin.llm.providers.bedrock import BedrockLLMClient
from odin.llm.providers.openrouter import OpenRouterLLMClient


def _sample_screen_context() -> dict:
    """Small context fixture for provider serialization tests."""
    return {
        "coordinate_system": {
            "type": "screenshot_coordinates_for_raw_xy_actions",
            "origin": "top_left",
            "x_axis": "right",
            "y_axis": "down",
            "screenshot_size": {"width": 1800, "height": 1130},
            "screen_size": {"width": 1800, "height": 1169},
        },
        "accessibility": {
            "available": True,
            "trusted": True,
            "app": "Firefox",
            "window": "Dynamic Array Code Implementation",
            "elements": [
                {
                    "id": "ax_1",
                    "role": "AXWindow",
                    "title": "Dynamic Array Code Implementation",
                    "frame": {"x": 0, "y": 39, "width": 1800, "height": 1130},
                    "enabled": True,
                    "focused": True,
                    "actions": ["AXRaise"],
                    "depth": 0,
                }
            ],
        },
    }


def test_create_client_defaults_to_openrouter():
    """Default factory path remains OpenRouter."""
    httpx_module = MagicMock()
    with patch.dict(os.environ, {"OPENROUTER_API_KEY": "test-key"}, clear=True):
        with patch.object(
            OpenRouterLLMClient, "_load_httpx", return_value=httpx_module
        ):
            client = create_client()

    assert isinstance(client, OpenRouterLLMClient)
    assert client.model == DEFAULT_OPENROUTER_MODEL
    httpx_module.Client.assert_called_once_with(timeout=120.0)
    client.close()


def test_create_client_infers_bedrock_from_model_prefix():
    """A bedrock/ model prefix selects Bedrock and strips the prefix."""
    with patch("odin.llm.providers.bedrock.BedrockLLMClient") as mock_client:
        create_client(model="bedrock/amazon.nova-lite-v1:0")

    mock_client.assert_called_once_with(
        model="amazon.nova-lite-v1:0",
        region_name=None,
        profile_name=None,
        inference_config=None,
    )


def test_create_client_defaults_to_bedrock_opus():
    """Explicit Bedrock provider defaults to the Opus model used by the app."""
    with patch("odin.llm.providers.bedrock.BedrockLLMClient") as mock_client:
        create_client(provider="bedrock")

    mock_client.assert_called_once_with(
        model=DEFAULT_BEDROCK_MODEL,
        region_name=None,
        profile_name=None,
        inference_config=None,
    )


def test_openrouter_client_requires_optional_dependency():
    """Using OpenRouter without the optional extra raises a clear error."""
    with patch("odin.llm.providers.openrouter.import_module", side_effect=ImportError):
        with pytest.raises(ImportError, match=r"odin\[openrouter\]"):
            OpenRouterLLMClient(api_key="test-key")


def test_bedrock_client_requires_optional_dependency():
    """Using Bedrock without the optional extra raises a clear error."""
    with patch("odin.llm.providers.bedrock.import_module", side_effect=ImportError):
        with pytest.raises(ImportError, match=r"odin\[bedrock\]"):
            BedrockLLMClient(model="amazon.nova-lite-v1:0")


def test_bedrock_client_uses_aws_region_env_var():
    """AWS_REGION is accepted even though boto3 defaults to AWS_DEFAULT_REGION."""
    boto3_module = MagicMock()
    session = boto3_module.Session.return_value
    with patch.dict(os.environ, {"AWS_REGION": "us-east-1"}, clear=True):
        with patch("odin.llm.providers.bedrock.import_module", return_value=boto3_module):
            BedrockLLMClient(model="amazon.nova-lite-v1:0")

    boto3_module.Session.assert_called_once_with(region_name="us-east-1")
    session.client.assert_called_once_with("bedrock-runtime")


def test_bedrock_client_uses_aws_region_name_env_var():
    """AWS_REGION_NAME is accepted for compatibility with common app settings."""
    boto3_module = MagicMock()
    session = boto3_module.Session.return_value
    with patch.dict(os.environ, {"AWS_REGION_NAME": "us-east-1"}, clear=True):
        with patch("odin.llm.providers.bedrock.import_module", return_value=boto3_module):
            BedrockLLMClient(model="amazon.nova-lite-v1:0")

    boto3_module.Session.assert_called_once_with(region_name="us-east-1")
    session.client.assert_called_once_with("bedrock-runtime")


def test_bedrock_client_reads_cost_rate_env_vars():
    """Bedrock cost rates can be configured from env vars."""
    sdk_client = MagicMock()
    with patch.dict(
        os.environ,
        {
            "ODIN_BEDROCK_INPUT_COST_PER_1K_TOKENS": "0.01",
            "ODIN_BEDROCK_OUTPUT_COST_PER_1K_TOKENS": "0.02",
        },
        clear=True,
    ):
        client = BedrockLLMClient(
            model="amazon.nova-lite-v1:0",
            client=sdk_client,
        )

    assert client.input_cost_per_1k_tokens == 0.01
    assert client.output_cost_per_1k_tokens == 0.02


@pytest.mark.parametrize(
    "model",
    [
        "anthropic.claude-opus-4-7",
        "us.anthropic.claude-opus-4-7",
        "global.anthropic.claude-opus-4-7",
        "bedrock/global.anthropic.claude-opus-4-7",
    ],
)
def test_bedrock_client_uses_builtin_opus_47_cost_rates(model):
    """Claude Opus 4.7 uses built-in standard Bedrock token rates."""
    with patch.dict(os.environ, {}, clear=True):
        client = BedrockLLMClient(model=model, client=MagicMock())

    assert client.input_cost_per_1k_tokens == 0.005
    assert client.output_cost_per_1k_tokens == 0.025


def test_openrouter_analyze_screen_sends_compact_context_text():
    """OpenRouter input context is compact text; output contract remains JSON."""
    response = MagicMock()
    response.json.return_value = {
        "choices": [
            {
                "message": {
                    "content": '{"thought":"Done","actions":[{"action":"done","params":{"success":true}}]}'
                }
            }
        ],
    }
    http_client = MagicMock()
    http_client.post.return_value = response
    client = OpenRouterLLMClient(api_key="test-key", client=http_client)

    client.analyze_screen(
        image=Image.new("RGB", (8, 8), color="white"),
        task="Test task",
        system_prompt="System prompt",
        screen_context=_sample_screen_context(),
    )

    request_json = http_client.post.call_args.kwargs["json"]
    text_block = request_json["messages"][-1]["content"][0]["text"]
    assert "Screen context:\nSCREEN_CONTEXT" in text_block
    assert "Screen context JSON" not in text_block
    assert "ACCESSIBILITY:" in text_block
    assert "ax_1 | AXWindow | Dynamic Array Code Implementation" in text_block
    assert '{"coordinate_system"' not in text_block


def test_bedrock_analyze_screen_uses_converse_image_bytes():
    """Bedrock client sends SDK image bytes and extracts text responses."""
    sdk_client = MagicMock()
    sdk_client.converse.return_value = {
        "output": {
            "message": {
                "content": [
                    {
                        "text": '{"thought": "Done", "actions": [{"action": "done", "params": {"result": "ok"}}]}'
                    }
                ]
            }
        },
        "usage": {"inputTokens": 10, "outputTokens": 5, "totalTokens": 15},
    }
    client = BedrockLLMClient(
        model="amazon.nova-lite-v1:0",
        input_cost_per_1k_tokens=0.01,
        output_cost_per_1k_tokens=0.02,
        client=sdk_client,
    )

    response = client.analyze_screen(
        image=Image.new("RGBA", (8, 8), color="white"),
        task="Test task",
        system_prompt="System prompt",
        history=[{"role": "assistant", "content": "Previous action succeeded."}],
        screen_context=_sample_screen_context(),
    )

    assert response.content.startswith('{"thought": "Done"')
    assert response.usage == {"inputTokens": 10, "outputTokens": 5, "totalTokens": 15}
    assert response.cost == {
        "provider": "bedrock",
        "model": "amazon.nova-lite-v1:0",
        "currency": "USD",
        "input_tokens": 10,
        "output_tokens": 5,
        "total_tokens": 15,
        "cache_read_input_tokens": 0,
        "cache_write_input_tokens": 0,
        "estimated": True,
        "input_cost_usd": 0.0001,
        "output_cost_usd": 0.0001,
        "total_cost_usd": 0.0002,
        "input_cost_per_1k_tokens": 0.01,
        "output_cost_per_1k_tokens": 0.02,
    }

    request = sdk_client.converse.call_args.kwargs
    assert request["modelId"] == "amazon.nova-lite-v1:0"
    assert request["system"] == [{"text": "System prompt"}]
    assert len(request["messages"]) == 1
    assert request["messages"][0]["role"] == "user"

    current_message = request["messages"][-1]
    text_block = next(block["text"] for block in current_message["content"] if "text" in block)
    assert "Screen context:\nSCREEN_CONTEXT" in text_block
    assert "Screen context JSON" not in text_block
    assert "ACCESSIBILITY:" in text_block
    assert "ax_1 | AXWindow | Dynamic Array Code Implementation" in text_block
    assert '{"coordinate_system"' not in text_block
    image_block = next(
        block for block in current_message["content"] if "image" in block
    )
    assert image_block["image"]["format"] == "jpeg"
    assert isinstance(image_block["image"]["source"]["bytes"], bytes)
