"""Shared agent data types.

Lives in its own module so :mod:`odin.agent.core` and
:mod:`odin.agent.loop` can import from it without a circular dependency.
"""

from __future__ import annotations

from enum import Enum
from typing import Any

from PIL import Image
from pydantic import BaseModel, Field


class AgentStatus(Enum):
    """Status of the agent."""

    IDLE = "idle"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    STOPPED = "stopped"


class AgentResult(BaseModel):
    """Result of an agent run."""

    model_config = {"arbitrary_types_allowed": True}

    success: bool
    message: str
    total_steps: int
    actions_executed: int
    duration_seconds: float
    final_screenshot: Image.Image | None = None
    trace_id: str | None = None
    trace_path: str | None = None
    llm_usage: dict[str, Any] = Field(default_factory=dict)


__all__ = ["AgentResult", "AgentStatus"]
