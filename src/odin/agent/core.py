"""Core agent implementing the ReAct loop for screen automation."""

from datetime import datetime
from enum import Enum
from pathlib import Path
import time
from typing import Any, Callable
from uuid import uuid4

from PIL import Image
from pydantic import BaseModel, Field

from odin.action.controller import ActionController
from odin.action.elements import ElementActionHandler
from odin.action.safety import SafetyConfig, SafetyController
from odin.agent.executor import ActionExecutor
from odin.agent.memory import AgentMemory
from odin.agent.parser import (
    ParsedAction,
    ParseError,
    parse_llm_actions,
    validate_action_params,
)
from odin.agent.tracing import (
    AgentTracer,
    JsonlTracer,
    NoopTracer,
    exception_trace,
    image_metadata,
)
from odin.llm.base import LLMProvider, LLMResponse
from odin.llm.prompts import build_system_prompt
from odin.perception.accessibility import Accessibility, AccessibilitySnapshot
from odin.perception.processing import Processing
from odin.perception.screen import Screen


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


ActionApprovalCallback = Callable[[dict[str, Any]], bool]


class AgentConfig(BaseModel):
    """Configuration for the agent."""

    max_steps: int = 100

    step_delay: float = 0.5

    compress_screenshots: bool = True

    max_screenshot_size: tuple[int, int] = (1920, 1080)

    use_accessibility: bool = True

    accessibility_max_depth: int = 8

    accessibility_max_nodes: int = 120

    safety: SafetyConfig = Field(default_factory=SafetyConfig)

    trace_path: str | Path | None = None

    trace_screenshots: bool = False

    max_batch_actions: int = 5


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
        self.safety = SafetyController(self.config.safety)
        self.element_handler = ElementActionHandler(
            self.accessibility, self.action_controller, self.safety,
        )
        self.executor = ActionExecutor(
            self.action_controller, self.element_handler, self.accessibility,
        )
        self.memory = AgentMemory()
        self._accessibility_snapshot: AccessibilitySnapshot | None = None

        self.status = AgentStatus.IDLE
        self._stop_requested = False
        self._on_step = on_step
        self._action_approval_callback = action_approval_callback
        self.tracer = tracer or self._create_tracer()
        self._last_screenshot_size: tuple[int, int] | None = None
        self._llm_usage = self._empty_llm_usage()

    def run(self, task: str) -> AgentResult:
        """
        Execute the ReAct loop to accomplish a task.

        Args:
            task: Natural language description of the task

        Returns:
            AgentResult with execution details
        """
        self.status = AgentStatus.RUNNING
        self._stop_requested = False
        self.memory.clear()
        self._llm_usage = self._empty_llm_usage()

        start_time = datetime.now()
        start_perf = time.perf_counter()
        step = 0
        final_screenshot = None
        self.tracer.start_run(
            task,
            metadata={
                "agent_config": self._trace_config(),
                "llm": self._trace_llm_metadata(),
            },
        )

        try:
            while step < self.config.max_steps and not self._stop_requested:
                step += 1
                self.tracer.event("step_started", step=step)

                screenshot = self._capture_screen(step)
                final_screenshot = screenshot
                accessibility_snapshot = self._capture_accessibility(step)
                self._accessibility_snapshot = accessibility_snapshot
                mouse_context = self._mouse_context(screenshot)
                self.tracer.event(
                    "mouse_position_captured",
                    step=step,
                    data=mouse_context,
                )
                screen_context = self._screen_context(
                    screenshot,
                    accessibility_snapshot,
                    mouse_context,
                )

                try:
                    history = self.memory.get_conversation_for_llm()
                    self.tracer.event(
                        "llm_request_started",
                        step=step,
                        data={
                            "model": getattr(self.llm, "model", None),
                            "history_messages": len(history),
                            "image": image_metadata(screenshot),
                            "accessibility_available": accessibility_snapshot.available,
                            "accessibility_elements": len(
                                accessibility_snapshot.elements
                            ),
                            "mouse": mouse_context,
                        },
                    )
                    llm_started_at = time.perf_counter()
                    response = self.llm.analyze_screen(
                        image=screenshot,
                        task=task,
                        system_prompt=self._system_prompt(),
                        history=history,
                        screen_context=screen_context,
                    )
                    llm_usage = self._record_llm_metrics(response)
                    self.tracer.event(
                        "llm_response_received",
                        step=step,
                        data={
                            "duration_seconds": time.perf_counter() - llm_started_at,
                            "content": response.content,
                            "reasoning": response.reasoning,
                            "usage": response.usage,
                            "cost": response.cost,
                            "usage_totals": llm_usage,
                        },
                    )
                except Exception as e:
                    self.status = AgentStatus.FAILED
                    self.tracer.event(
                        "llm_error",
                        step=step,
                        data={"error": exception_trace(e)},
                    )
                    return self._finish_result(
                        success=False,
                        message=f"LLM error: {e}",
                        total_steps=step,
                        start_time=start_time,
                        start_perf=start_perf,
                        final_screenshot=final_screenshot,
                    )

                try:
                    actions = parse_llm_actions(
                        response.content,
                        max_actions=max(1, self.config.max_batch_actions),
                    )
                    self.tracer.event(
                        "actions_parsed",
                        step=step,
                        data={
                            "count": len(actions),
                            "actions": [
                                {
                                    "thought": action.thought,
                                    "action": action.action,
                                    "params": action.params,
                                }
                                for action in actions
                            ],
                        },
                    )
                    for batch_index, action in enumerate(actions, start=1):
                        self.tracer.event(
                            "action_parsed",
                            step=step,
                            data={
                                "batch_index": batch_index,
                                "batch_count": len(actions),
                                "thought": action.thought,
                                "action": action.action,
                                "params": action.params,
                            },
                        )
                except ParseError as e:
                    self.tracer.event(
                        "parse_error",
                        step=step,
                        data={
                            "error": str(e),
                            "content": response.content,
                        },
                    )
                    self.memory.add_message(
                        "assistant",
                        f"Parse error: {e}. Please respond with valid JSON.",
                    )
                    self._delay_between_steps(step)
                    continue

                prepared_actions: list[tuple[int, ParsedAction]] = []
                done_after_actions: tuple[int, ParsedAction] | None = None
                batch_stopped = False

                for batch_index, action in enumerate(actions, start=1):
                    valid, error = validate_action_params(action)
                    if not valid:
                        self.tracer.event(
                            "action_validation_failed",
                            step=step,
                            data={
                                "batch_index": batch_index,
                                "batch_count": len(actions),
                                "action": action.action,
                                "params": action.params,
                                "error": error,
                            },
                        )
                        self.memory.add_message(
                            "assistant",
                            f"Invalid action: {error}. Please fix parameters.",
                        )
                        batch_stopped = True
                        break

                    action = self._map_action_coordinates(action, step)

                    if action.action == "done":
                        if prepared_actions:
                            done_after_actions = (batch_index, action)
                            break

                        self.status = AgentStatus.COMPLETED
                        success = action.params.get("success", True)
                        result_msg = action.params.get("result", "Task completed")

                        self.tracer.event(
                            "task_done",
                            step=step,
                            data={
                                "batch_index": batch_index,
                                "batch_count": len(actions),
                                "success": success,
                                "message": result_msg,
                                "params": action.params,
                            },
                        )

                        return self._finish_result(
                            success=success,
                            message=result_msg,
                            total_steps=step,
                            start_time=start_time,
                            start_perf=start_perf,
                            final_screenshot=final_screenshot,
                        )

                    safe, safety_error = self.safety.validate_action(
                        action.action, action.params
                    )
                    self.tracer.event(
                        "safety_checked",
                        step=step,
                        data={
                            "batch_index": batch_index,
                            "batch_count": len(actions),
                            "action": action.action,
                            "params": action.params,
                            "allowed": safe,
                            "error": safety_error,
                        },
                    )
                    if not safe:
                        self.tracer.event(
                            "action_blocked",
                            step=step,
                            data={
                                "batch_index": batch_index,
                                "batch_count": len(actions),
                                "action": action.action,
                                "params": action.params,
                                "error": safety_error,
                            },
                        )
                        self.memory.add_message(
                            "assistant",
                            f"Action blocked by safety: {safety_error}",
                        )
                        batch_stopped = True
                        break

                    prepared_actions.append((batch_index, action))

                if not batch_stopped:
                    for batch_index, action in prepared_actions:
                        approved = self._request_action_approval(
                            action=action,
                            step=step,
                            batch_index=batch_index,
                            batch_count=len(actions),
                        )
                        if not approved:
                            self.memory.add_message(
                                "assistant",
                                (
                                    "Action was not approved by the user. "
                                    "Choose a safer alternative or finish if blocked."
                                ),
                            )
                            self.tracer.event(
                                "action_batch_stopped",
                                step=step,
                                data={
                                    "batch_index": batch_index,
                                    "batch_count": len(actions),
                                    "reason": "action_not_approved",
                                    "action": action.action,
                                },
                            )
                            batch_stopped = True
                            break

                batch_executed_successfully = False
                if not batch_stopped:
                    batch_executed_successfully = True
                    for batch_index, action in prepared_actions:
                        self.tracer.event(
                            "action_execution_started",
                            step=step,
                            data={
                                "batch_index": batch_index,
                                "batch_count": len(actions),
                                "thought": action.thought,
                                "action": action.action,
                                "params": action.params,
                                "target": self.executor.visual_target(action),
                            },
                        )
                        action_started_at = time.perf_counter()
                        result = self.executor.execute(action)
                        self.safety.record_action()
                        self.tracer.event(
                            "action_executed",
                            step=step,
                            data={
                                "batch_index": batch_index,
                                "batch_count": len(actions),
                                "duration_seconds": time.perf_counter()
                                - action_started_at,
                                "action": result.action,
                                "success": result.success,
                                "message": result.message,
                                "error": result.error,
                            },
                        )

                        self.memory.add_action(
                            action,
                            success=result.success,
                            message=result.message or result.error,
                        )

                        self.memory.add_message(
                            "assistant",
                            f"Executed: {action.action} - {'Success' if result.success else 'Failed'}: {result.message or result.error}",
                        )

                        if self._on_step:
                            self._on_step(step, action)

                        if not result.success:
                            self.tracer.event(
                                "action_batch_stopped",
                                step=step,
                                data={
                                    "batch_index": batch_index,
                                    "batch_count": len(actions),
                                    "reason": "action_failed",
                                    "action": result.action,
                                    "error": result.error,
                                },
                            )
                            batch_executed_successfully = False
                            break

                        if self._stop_requested:
                            batch_executed_successfully = False
                            break

                        self._delay_between_batch_actions(batch_index, len(actions))

                if batch_executed_successfully and done_after_actions is not None:
                    batch_index, action = done_after_actions
                    self.status = AgentStatus.COMPLETED
                    success = action.params.get("success", True)
                    result_msg = action.params.get("result", "Task completed")

                    self.tracer.event(
                        "task_done",
                        step=step,
                        data={
                            "batch_index": batch_index,
                            "batch_count": len(actions),
                            "success": success,
                            "message": result_msg,
                            "params": action.params,
                        },
                    )

                    return self._finish_result(
                        success=success,
                        message=result_msg,
                        total_steps=step,
                        start_time=start_time,
                        start_perf=start_perf,
                        final_screenshot=final_screenshot,
                    )

                self._delay_between_steps(step)

            self.status = (
                AgentStatus.STOPPED if self._stop_requested else AgentStatus.FAILED
            )
            return self._finish_result(
                success=False,
                message="Max steps reached"
                if not self._stop_requested
                else "Stopped by user",
                total_steps=step,
                start_time=start_time,
                start_perf=start_perf,
                final_screenshot=final_screenshot,
            )

        except Exception as e:
            self.status = AgentStatus.FAILED
            self.tracer.event(
                "unexpected_error",
                step=step,
                data={"error": exception_trace(e)},
            )
            return self._finish_result(
                success=False,
                message=f"Unexpected error: {e}",
                total_steps=step,
                start_time=start_time,
                start_perf=start_perf,
                final_screenshot=final_screenshot,
            )

    def stop(self):
        """Request the agent to stop after the current step."""
        self._stop_requested = True

    def _create_tracer(self) -> AgentTracer:
        """Create the configured tracer."""
        if self.config.trace_path:
            return JsonlTracer(
                self.config.trace_path,
                save_screenshots=self.config.trace_screenshots,
            )
        return NoopTracer()

    def _trace_config(self) -> dict:
        """Return trace-safe agent configuration."""
        return {
            "max_steps": self.config.max_steps,
            "step_delay": self.config.step_delay,
            "compress_screenshots": self.config.compress_screenshots,
            "max_screenshot_size": self.config.max_screenshot_size,
            "use_accessibility": self.config.use_accessibility,
            "accessibility_max_depth": self.config.accessibility_max_depth,
            "accessibility_max_nodes": self.config.accessibility_max_nodes,
            "trace_screenshots": self.config.trace_screenshots,
            "max_batch_actions": self.config.max_batch_actions,
            "safety": {
                "max_actions_per_minute": self.config.safety.max_actions_per_minute,
                "min_action_delay": self.config.safety.min_action_delay,
                "require_confirmation": self.config.safety.require_confirmation,
                "bounds_margin": self.config.safety.bounds_margin,
            },
        }

    def _request_action_approval(
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
            "action": action.action,
            "params": action.params,
            "target": self.executor.visual_target(action),
        }
        self.tracer.event("action_approval_requested", step=step, data=request)

        if self._action_approval_callback is None:
            self.tracer.event(
                "action_approval_received",
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
                "action_approval_received",
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
            "action_approval_received",
            step=step,
            data={**request, "approved": approved},
        )
        return approved

    def _trace_llm_metadata(self) -> dict:
        """Return trace-safe LLM metadata."""
        return {
            "class": self.llm.__class__.__name__,
            "model": getattr(self.llm, "model", None),
        }

    def _empty_llm_usage(self) -> dict[str, Any]:
        """Return a mutable run-level LLM usage accumulator."""
        return {
            "requests": 0,
            "input_tokens": 0,
            "output_tokens": 0,
            "total_tokens": 0,
            "cache_read_input_tokens": 0,
            "cache_write_input_tokens": 0,
            "estimated_input_cost_usd": 0.0,
            "estimated_output_cost_usd": 0.0,
            "estimated_cost_usd": 0.0,
            "cost_estimated": False,
            "currency": "USD",
        }

    def _record_llm_metrics(self, response: LLMResponse) -> dict[str, Any]:
        """Accumulate per-call token usage and estimated cost."""
        self._llm_usage["requests"] += 1

        usage = response.usage if isinstance(response.usage, dict) else {}
        self._llm_usage["input_tokens"] += self._metric_int(usage, "inputTokens")
        self._llm_usage["output_tokens"] += self._metric_int(usage, "outputTokens")
        self._llm_usage["total_tokens"] += self._metric_int(usage, "totalTokens")
        self._llm_usage["cache_read_input_tokens"] += self._metric_int(
            usage, "cacheReadInputTokens"
        )
        self._llm_usage["cache_write_input_tokens"] += self._metric_int(
            usage, "cacheWriteInputTokens"
        )

        cost = response.cost if isinstance(response.cost, dict) else {}
        if cost.get("estimated"):
            self._llm_usage["cost_estimated"] = True
            self._llm_usage["currency"] = cost.get("currency", "USD")
            self._llm_usage["estimated_input_cost_usd"] += self._metric_float(
                cost, "input_cost_usd"
            )
            self._llm_usage["estimated_output_cost_usd"] += self._metric_float(
                cost, "output_cost_usd"
            )
            self._llm_usage["estimated_cost_usd"] += self._metric_float(
                cost, "total_cost_usd"
            )

        return self._llm_usage_summary()

    @staticmethod
    def _metric_int(metrics: dict[str, Any], key: str) -> int:
        """Read an integer metric with a zero default."""
        value = metrics.get(key)
        if isinstance(value, bool) or value is None:
            return 0
        try:
            return int(value)
        except (TypeError, ValueError):
            return 0

    @staticmethod
    def _metric_float(metrics: dict[str, Any], key: str) -> float:
        """Read a float metric with a zero default."""
        value = metrics.get(key)
        if isinstance(value, bool) or value is None:
            return 0.0
        try:
            return float(value)
        except (TypeError, ValueError):
            return 0.0

    def _llm_usage_summary(self) -> dict[str, Any]:
        """Return trace/result-safe LLM usage totals."""
        summary = self._llm_usage.copy()
        if not summary["cost_estimated"]:
            summary["estimated_input_cost_usd"] = None
            summary["estimated_output_cost_usd"] = None
            summary["estimated_cost_usd"] = None
        return summary

    def _system_prompt(self) -> str:
        """Build the system prompt for the current agent configuration."""
        return build_system_prompt(
            max_batch_actions=max(1, self.config.max_batch_actions),
        )

    def _screen_context(
        self,
        screenshot: Image.Image,
        accessibility_snapshot: AccessibilitySnapshot,
        mouse_context: dict[str, object],
    ) -> dict:
        """Build prompt context that complements the screenshot."""
        context: dict = {
            "coordinate_system": {
                "type": "screenshot_coordinates_for_raw_xy_actions",
                "origin": "top_left",
                "x_axis": "right",
                "y_axis": "down",
                "screenshot_size": {
                    "width": screenshot.width,
                    "height": screenshot.height,
                },
                "screen_size": {
                    "width": self.action_controller.screen_width,
                    "height": self.action_controller.screen_height,
                },
                "notes": (
                    "For raw coordinate actions like click, double_click, and move, "
                    "return x/y in screenshot coordinates. Odin maps them to screen "
                    "coordinates before executing. Accessibility element frames are "
                    "already screen coordinates; use element actions for those."
                ),
            },
            "mouse": mouse_context,
            "accessibility": accessibility_snapshot.to_context(),
            "interaction_guidance": (
                "Prefer element actions with element_id when accessibility elements "
                "match the target. Use raw x/y only as a fallback."
            ),
        }
        try:
            context["app"] = self.screen.get_app_context()
        except Exception:
            context["app"] = {"frontmost_app": None, "windows": []}
        return context

    def _mouse_context(self, screenshot: Image.Image) -> dict[str, object]:
        """Capture the current pointer location in screen and screenshot coordinates."""
        try:
            raw_x, raw_y = self.action_controller.get_mouse_position()
            x = int(raw_x)
            y = int(raw_y)
        except Exception as exc:
            return {
                "available": False,
                "error": str(exc),
            }

        screen_width = self.action_controller.screen_width
        screen_height = self.action_controller.screen_height
        context: dict[str, object] = {
            "available": True,
            "screen_position": {
                "x": x,
                "y": y,
            },
        }

        if screen_width > 0 and screen_height > 0:
            context["screenshot_position"] = {
                "x": round(x * screenshot.width / screen_width),
                "y": round(y * screenshot.height / screen_height),
            }

        return context

    def _finish_result(
        self,
        *,
        success: bool,
        message: str,
        total_steps: int,
        start_time: datetime,
        start_perf: float,
        final_screenshot: Image.Image | None,
    ) -> AgentResult:
        """Emit run_finished and build the agent result."""
        duration_seconds = time.perf_counter() - start_perf
        trace_path = str(self.tracer.path) if self.tracer.path else None
        llm_usage = self._llm_usage_summary()
        self.tracer.event(
            "run_finished",
            data={
                "success": success,
                "message": message,
                "status": self.status.value,
                "total_steps": total_steps,
                "actions_executed": self.memory.total_actions,
                "duration_seconds": duration_seconds,
                "started_at": start_time.isoformat(),
                "final_screenshot": image_metadata(final_screenshot)
                if final_screenshot is not None
                else None,
                "llm_usage": llm_usage,
            },
        )
        return AgentResult(
            success=success,
            message=message,
            total_steps=total_steps,
            actions_executed=self.memory.total_actions,
            duration_seconds=duration_seconds,
            final_screenshot=final_screenshot,
            trace_id=self.tracer.run_id,
            trace_path=trace_path,
            llm_usage=llm_usage,
        )

    def _delay_between_steps(self, step: int) -> None:
        """Apply configured delay before the next step, if any."""
        if self.config.step_delay <= 0:
            return
        if self._stop_requested or step >= self.config.max_steps:
            return
        time.sleep(self.config.step_delay)

    def _delay_between_batch_actions(
        self,
        batch_index: int,
        batch_count: int,
    ) -> None:
        """Respect safety delay between actions inside a batch."""
        if batch_index >= batch_count:
            return

        delay = self.config.safety.min_action_delay
        if delay <= 0:
            return
        time.sleep(delay)

    def _capture_screen(self, step: int) -> Image.Image:
        """Capture and process the current screen."""
        self.tracer.event("screenshot_capture_started", step=step)
        started_at = time.perf_counter()

        try:
            screenshot = self.screen.get_screenshot()
            raw_metadata = image_metadata(screenshot)

            if self.config.compress_screenshots:
                screenshot = self.processing.compress_image(
                    screenshot,
                    max_size=self.config.max_screenshot_size,
                )

            self._last_screenshot_size = (screenshot.width, screenshot.height)

            self.memory.add_screenshot(screenshot)
            screenshot_path = self.tracer.save_image(
                screenshot,
                step=step,
                label="screen",
            )
            self.tracer.event(
                "screenshot_captured",
                step=step,
                data={
                    "duration_seconds": time.perf_counter() - started_at,
                    "raw_image": raw_metadata,
                    "processed_image": image_metadata(screenshot),
                    "compressed": self.config.compress_screenshots,
                    "screenshot_path": screenshot_path,
                },
            )
        except Exception as e:
            self.tracer.event(
                "screenshot_error",
                step=step,
                data={"error": exception_trace(e)},
            )
            raise

        return screenshot

    def _map_action_coordinates(
        self,
        action: ParsedAction,
        step: int,
    ) -> ParsedAction:
        """Map screenshot coordinates from the model to screen coordinates."""
        coordinate_keys: tuple[tuple[str, str], ...]
        if action.action in {"click", "double_click", "move"}:
            coordinate_keys = (("x", "y"),)
        elif action.action == "scroll" and {"x", "y"}.issubset(action.params):
            coordinate_keys = (("x", "y"),)
        else:
            return action

        screenshot_size = self._last_screenshot_size
        if not screenshot_size:
            return action

        screenshot_width, screenshot_height = screenshot_size
        screen_width = self.action_controller.screen_width
        screen_height = self.action_controller.screen_height
        if (
            screenshot_width <= 0
            or screenshot_height <= 0
            or screen_width <= 0
            or screen_height <= 0
        ):
            return action

        mapped_params = action.params.copy()
        mappings: list[dict[str, int | str]] = []
        for x_key, y_key in coordinate_keys:
            x = mapped_params.get(x_key)
            y = mapped_params.get(y_key)
            if not isinstance(x, int) or not isinstance(y, int):
                continue

            mapped_x = round(x * screen_width / screenshot_width)
            mapped_y = round(y * screen_height / screenshot_height)
            mapped_params[x_key] = mapped_x
            mapped_params[y_key] = mapped_y
            mappings.append(
                {
                    "x_key": x_key,
                    "y_key": y_key,
                    "input_x": x,
                    "input_y": y,
                    "mapped_x": mapped_x,
                    "mapped_y": mapped_y,
                }
            )

        if mappings:
            self.tracer.event(
                "action_coordinates_mapped",
                step=step,
                data={
                    "action": action.action,
                    "screenshot_size": {
                        "width": screenshot_width,
                        "height": screenshot_height,
                    },
                    "screen_size": {
                        "width": screen_width,
                        "height": screen_height,
                    },
                    "mappings": mappings,
                },
            )

        return ParsedAction(
            thought=action.thought,
            action=action.action,
            params=mapped_params,
            raw_response=action.raw_response,
        )

    def _capture_accessibility(self, step: int) -> AccessibilitySnapshot:
        """Capture the focused macOS accessibility tree."""
        if not self.config.use_accessibility:
            return AccessibilitySnapshot(
                available=False,
                error="Accessibility capture is disabled.",
            )

        self.tracer.event("accessibility_capture_started", step=step)
        started_at = time.perf_counter()
        snapshot = self.accessibility.capture(
            max_depth=self.config.accessibility_max_depth,
            max_nodes=self.config.accessibility_max_nodes,
        )
        self.tracer.event(
            "accessibility_captured",
            step=step,
            data={
                "duration_seconds": time.perf_counter() - started_at,
                "available": snapshot.available,
                "trusted": snapshot.trusted,
                "app": snapshot.app,
                "window": snapshot.window,
                "elements": len(snapshot.elements),
                "error": snapshot.error,
            },
        )
        return snapshot
