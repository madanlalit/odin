"""Core agent: the public façade for the ReAct loop.

The :class:`Agent` owns its dependencies and the run state, but the
step-by-step ReAct execution lives in :class:`odin.agent.loop.ReActLoop`
so this module can stay small and focused.
"""

from __future__ import annotations

from collections.abc import Callable
from pathlib import Path
from typing import TYPE_CHECKING, Any
from uuid import uuid4

from pydantic import BaseModel, Field

from odin.action.controller import ActionController
from odin.action.elements import ElementActionHandler
from odin.action.safety import SafetyConfig, SafetyController
from odin.agent.events import TraceEventKind
from odin.agent.executor import ActionExecutor
from odin.agent.memory import AgentMemory
from odin.agent.parser import ParsedAction
from odin.agent.tracing import (
    AgentTracer,
    JsonlTracer,
    NoopTracer,
    exception_trace,
)
from odin.agent.types import AgentResult, AgentStatus
from odin.llm.base import LLMProvider, LLMResponse
from odin.perception.accessibility import Accessibility
from odin.perception.processing import Processing
from odin.perception.screen import Screen

if TYPE_CHECKING:
    from odin.agent.loop import ReActLoop

ActionApprovalCallback = Callable[[dict[str, Any]], bool]


class LoopConfig(BaseModel):
    """Loop-level execution parameters."""

    max_steps: int = 100
    step_delay: float = 0.5
    max_batch_actions: int = 5


class CaptureConfig(BaseModel):
    """Screen and accessibility capture parameters."""

    compress_screenshots: bool = True
    max_screenshot_size: tuple[int, int] = (1920, 1080)
    use_accessibility: bool = True
    accessibility_max_depth: int = 8
    accessibility_max_nodes: int = 120


class TraceConfig(BaseModel):
    """Structured trace recording parameters."""

    path: str | Path | None = None
    save_screenshots: bool = False


class AgentConfig(BaseModel):
    """Configuration for the agent."""

    loop: LoopConfig = Field(default_factory=LoopConfig)
    capture: CaptureConfig = Field(default_factory=CaptureConfig)
    trace: TraceConfig = Field(default_factory=TraceConfig)
    safety: SafetyConfig = Field(default_factory=SafetyConfig)


class Agent:
    """
    Main agent implementing the ReAct (Reason + Act) loop.

    The agent:
    1. Captures a screenshot of the current screen
    2. Sends it to the LLM with the task and history
    3. Parses the action batch from the LLM response
    4. Executes the actions (with safety checks)
    5. Repeats until task is complete or max steps reached
    """

    def __init__(
        self,
        llm_client: LLMProvider,
        config: AgentConfig | None = None,
        on_step: Callable[[int, ParsedAction], None] | None = None,
        tracer: AgentTracer | None = None,
        action_approval_callback: ActionApprovalCallback | None = None,
    ):
        """
        Initialize the agent.

        Args:
            llm_client: LLM client for vision analysis
            config: Agent configuration
            on_step: Optional callback called after each step
            tracer: Optional custom tracer. If omitted, trace_path controls JSONL tracing.
            action_approval_callback: Optional callback for human approval before actions.
        """
        self.llm = llm_client
        self.config = config or AgentConfig()

        self.screen = Screen()
        self.processing = Processing()
        self.accessibility = Accessibility()
        self.action_controller = ActionController()
        self.safety = SafetyController.from_backend(
            self.action_controller._backend,
            self.config.safety,
        )
        self.element_handler = ElementActionHandler(
            self.accessibility, self.action_controller, self.safety,
        )
        self.executor = ActionExecutor(
            self.action_controller, self.element_handler, self.accessibility,
        )
        self.memory = AgentMemory()

        self.status = AgentStatus.IDLE
        self._stop_requested = False
        self._on_step = on_step
        self._action_approval_callback = action_approval_callback
        self.tracer = tracer or self._create_tracer()
        self._last_screenshot_size: tuple[int, int] | None = None
        self._llm_usage = self._empty_llm_usage()
        self._loop: ReActLoop | None = None

    def _loop_instance(self) -> ReActLoop:
        """Lazily build the ReAct loop to avoid a circular import."""
        if self._loop is None:
            from odin.agent.loop import ReActLoop

            self._loop = ReActLoop(self)
        return self._loop

    def run(self, task: str) -> AgentResult:
        """Execute the ReAct loop to accomplish a task.

        Args:
            task: Natural language description of the task

        Returns:
            AgentResult with execution details
        """
        return self._loop_instance().run(task)

    def stop(self):
        """Request the agent to stop after the current step."""
        self._stop_requested = True

    def _create_tracer(self) -> AgentTracer:
        """Create the configured tracer."""
        trace_path = self.config.trace.path
        if trace_path:
            return JsonlTracer(
                trace_path,
                save_screenshots=self.config.trace.save_screenshots,
            )
        return NoopTracer()

    def _trace_config(self) -> dict:
        """Return trace-safe agent configuration."""
        return {
            "loop": {
                "max_steps": self.config.loop.max_steps,
                "step_delay": self.config.loop.step_delay,
                "max_batch_actions": self.config.loop.max_batch_actions,
            },
            "capture": {
                "compress_screenshots": self.config.capture.compress_screenshots,
                "max_screenshot_size": self.config.capture.max_screenshot_size,
                "use_accessibility": self.config.capture.use_accessibility,
                "accessibility_max_depth": self.config.capture.accessibility_max_depth,
                "accessibility_max_nodes": self.config.capture.accessibility_max_nodes,
            },
            "trace": {
                "save_screenshots": self.config.trace.save_screenshots,
            },
            "safety": {
                "max_actions_per_minute": self.config.safety.max_actions_per_minute,
                "min_action_delay": self.config.safety.min_action_delay,
                "require_confirmation": self.config.safety.require_confirmation,
                "bounds_margin": self.config.safety.bounds_margin,
            },
        }

    def _trace_llm_metadata(self) -> dict:
        """Return trace-safe LLM metadata."""
        return {
            "class": self.llm.__class__.__name__,
            "model": getattr(self.llm, "model", None),
        }

    def request_action_approval(
        self,
        *,
        action: ParsedAction,
        step: int,
        batch_index: int,
        batch_count: int,
    ) -> bool:
        """Request human approval when configured before executing an action."""
        if not self.config.safety.require_confirmation:
            return True

        request = {
            "request_id": uuid4().hex,
            "batch_index": batch_index,
            "batch_count": batch_count,
            "thought": action.thought,
            "action": str(action.action),
            "params": action.params,
            "target": self.executor.visual_target(action),
        }
        self.tracer.event(TraceEventKind.ACTION_APPROVAL_REQUESTED, step=step, data=request)

        if self._action_approval_callback is None:
            self.tracer.event(
                TraceEventKind.ACTION_APPROVAL_RECEIVED,
                step=step,
                data={
                    **request,
                    "approved": False,
                    "reason": "no_approval_callback",
                },
            )
            return False

        try:
            approved = bool(self._action_approval_callback(request))
        except Exception as exc:
            self.tracer.event(
                TraceEventKind.ACTION_APPROVAL_RECEIVED,
                step=step,
                data={
                    **request,
                    "approved": False,
                    "reason": "approval_callback_error",
                    "error": exception_trace(exc),
                },
            )
            return False

        self.tracer.event(
            TraceEventKind.ACTION_APPROVAL_RECEIVED,
            step=step,
            data={**request, "approved": approved},
        )
        return approved

    _TOKEN_USAGE_KEYS: tuple[tuple[str, str], ...] = (
        ("input_tokens", "inputTokens"),
        ("output_tokens", "outputTokens"),
        ("total_tokens", "totalTokens"),
        ("cache_read_input_tokens", "cacheReadInputTokens"),
        ("cache_write_input_tokens", "cacheWriteInputTokens"),
    )

    def _empty_llm_usage(self) -> dict[str, Any]:
        """Return a mutable run-level LLM usage accumulator."""
        summary: dict[str, Any] = {"requests": 0}
        for summary_key, _ in self._TOKEN_USAGE_KEYS:
            summary[summary_key] = 0
        return summary

    def _record_llm_metrics(self, response: LLMResponse) -> dict[str, Any]:
        """Accumulate per-call token usage."""
        self._llm_usage["requests"] += 1

        usage = response.usage if isinstance(response.usage, dict) else {}
        for summary_key, usage_key in self._TOKEN_USAGE_KEYS:
            value = usage.get(usage_key)
            if isinstance(value, bool) or value is None:
                continue
            try:
                self._llm_usage[summary_key] += int(value)
            except (TypeError, ValueError):
                continue

        return self._llm_usage.copy()


__all__ = [
    "ActionApprovalCallback",
    "Agent",
    "AgentConfig",
    "AgentResult",
    "AgentStatus",
    "CaptureConfig",
    "LoopConfig",
    "TraceConfig",
]
