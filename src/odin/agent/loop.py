"""ReAct loop implementation.

Keeps the :func:`Agent.run` body out of :mod:`odin.agent.core` so the
public façade stays small. The loop walks the agent through:

1. capture screen + accessibility + mouse context
2. call the LLM
3. parse the action batch
4. validate, map, and approve each action
5. execute the batch

Every failure mode is converted into a structured trace event and either
returns a final result or continues to the next step.
"""

from __future__ import annotations

import time
from dataclasses import dataclass
from datetime import datetime
from typing import TYPE_CHECKING, Any

from PIL import Image

from odin.agent.actions import ActionKind
from odin.agent.coordinates import map_action_coordinates
from odin.agent.events import TraceEventKind
from odin.agent.parser import ParseError, parse_llm_actions, validate_action_params
from odin.agent.tracing import exception_trace, image_metadata
from odin.agent.types import AgentResult, AgentStatus
from odin.llm.prompts import build_system_prompt
from odin.log import logger
from odin.perception.accessibility import AccessibilitySnapshot

if TYPE_CHECKING:
    from odin.agent.core import Agent


@dataclass
class GuardResult:
    """Outcome of a guarded operation."""

    ok: bool
    value: Any = None
    error: BaseException | None = None


class ReActLoop:
    """The ReAct loop driven by an :class:`Agent`."""

    def __init__(self, agent: Agent) -> None:
        self._agent = agent

    def run(self, task: str) -> AgentResult:
        """Execute the ReAct loop to accomplish a task."""
        agent = self._agent
        agent.status = AgentStatus.RUNNING
        agent._stop_requested = False
        agent.memory.clear()
        agent._llm_usage = agent._empty_llm_usage()

        start_time = datetime.now()
        start_perf = time.perf_counter()
        step = 0
        final_screenshot: Image.Image | None = None

        agent.tracer.start_run(
            task,
            metadata={
                "agent_config": agent._trace_config(),
                "llm": agent._trace_llm_metadata(),
            },
        )

        try:
            return self._drive(
                task=task,
                start_time=start_time,
                start_perf=start_perf,
                final_screenshot=final_screenshot,
            )
        except Exception as exc:
            logger.exception("agent run crashed unexpectedly")
            agent.status = AgentStatus.FAILED
            agent.tracer.event(
                TraceEventKind.UNEXPECTED_ERROR,
                step=step,
                data={"error": exception_trace(exc)},
            )
            return self._finish(
                success=False,
                message=f"Unexpected error: {exc}",
                total_steps=step,
                start_time=start_time,
                start_perf=start_perf,
                final_screenshot=final_screenshot,
            )

    def _drive(
        self,
        *,
        task: str,
        start_time: datetime,
        start_perf: float,
        final_screenshot: Image.Image | None,
    ) -> AgentResult:
        agent = self._agent
        step = 0
        while step < agent.config.loop.max_steps and not agent._stop_requested:
            step += 1
            agent.tracer.event(TraceEventKind.STEP_STARTED, step=step)

            screenshot = self._capture_screen(step)
            final_screenshot = screenshot
            accessibility_snapshot = self._capture_accessibility(step)
            mouse_context = self._mouse_context(screenshot)
            agent.tracer.event(
                TraceEventKind.MOUSE_POSITION_CAPTURED,
                step=step,
                data=mouse_context,
            )
            screen_context = self._screen_context(
                screenshot,
                accessibility_snapshot,
                mouse_context,
            )

            llm_result = self._guard_llm(
                step=step,
                task=task,
                screenshot=screenshot,
                history=agent.memory.get_conversation_for_llm(),
                screen_context=screen_context,
                accessibility_snapshot=accessibility_snapshot,
                mouse_context=mouse_context,
            )
            if not llm_result.ok:
                return self._finish(
                    success=False,
                    message=f"LLM error: {llm_result.error}",
                    total_steps=step,
                    start_time=start_time,
                    start_perf=start_perf,
                    final_screenshot=final_screenshot,
                )

            try:
                actions = parse_llm_actions(
                    llm_result.value,
                    max_actions=max(1, agent.config.loop.max_batch_actions),
                )
            except ParseError as exc:
                agent.tracer.event(
                    TraceEventKind.PARSE_ERROR,
                    step=step,
                    data={"error": str(exc), "content": llm_result.value},
                )
                agent.memory.add_message(
                    "assistant",
                    f"Parse error: {exc}. Please respond with valid JSON.",
                )
                self._delay_between_steps(step)
                continue

            self._trace_actions_parsed(step, actions)
            prepared, done_after = self._prepare_batch(step, actions)
            if done_after is not None and not prepared:
                return self._complete_with_done(
                    step=step,
                    action=done_after,
                    start_time=start_time,
                    start_perf=start_perf,
                    final_screenshot=final_screenshot,
                )

            batch_executed = self._execute_batch(
                step=step,
                prepared=prepared,
                batch_size=len(actions),
            )

            if batch_executed and done_after is not None:
                return self._complete_with_done(
                    step=step,
                    action=done_after,
                    start_time=start_time,
                    start_perf=start_perf,
                    final_screenshot=final_screenshot,
                )

            self._delay_between_steps(step)

        agent.status = (
            AgentStatus.STOPPED if agent._stop_requested else AgentStatus.FAILED
        )
        return self._finish(
            success=False,
            message="Max steps reached"
            if not agent._stop_requested
            else "Stopped by user",
            total_steps=step,
            start_time=start_time,
            start_perf=start_perf,
            final_screenshot=final_screenshot,
        )

    def _call_llm(
        self,
        *,
        task: str,
        screenshot: Image.Image,
        history: list[dict[str, Any]],
        screen_context: dict[str, Any],
        accessibility_snapshot: AccessibilitySnapshot,
        mouse_context: dict[str, object],
    ) -> str:
        agent = self._agent
        agent.tracer.event(
            TraceEventKind.LLM_REQUEST_STARTED,
            data={
                "model": getattr(agent.llm, "model", None),
                "history_messages": len(history),
                "image": image_metadata(screenshot),
                "accessibility_available": accessibility_snapshot.available,
                "accessibility_elements": len(accessibility_snapshot.elements),
                "mouse": mouse_context,
            },
        )
        started = time.perf_counter()
        response = agent.llm.analyze_screen(
            image=screenshot,
            task=task,
            system_prompt=build_system_prompt(
                max_batch_actions=max(1, agent.config.loop.max_batch_actions),
            ),
            history=history,
            screen_context=screen_context,
        )
        llm_usage = agent._record_llm_metrics(response)
        agent.tracer.event(
            TraceEventKind.LLM_RESPONSE_RECEIVED,
            data={
                "duration_seconds": time.perf_counter() - started,
                "content": response.content,
                "reasoning": response.reasoning,
                "usage": response.usage,
                "usage_totals": llm_usage,
            },
        )
        return response.content

    def _guard_llm(
        self,
        *,
        step: int,
        task: str,
        screenshot: Image.Image,
        history: list[dict[str, Any]],
        screen_context: dict[str, Any],
        accessibility_snapshot: AccessibilitySnapshot,
        mouse_context: dict[str, object],
    ) -> GuardResult:
        try:
            return GuardResult(
                ok=True,
                value=self._call_llm(
                    task=task,
                    screenshot=screenshot,
                    history=history,
                    screen_context=screen_context,
                    accessibility_snapshot=accessibility_snapshot,
                    mouse_context=mouse_context,
                ),
            )
        except Exception as exc:
            logger.exception("LLM call failed at step %d", step)
            self._agent.tracer.event(
                TraceEventKind.LLM_ERROR,
                step=step,
                data={"error": exception_trace(exc)},
            )
            return GuardResult(ok=False, error=exc)

    def _trace_actions_parsed(self, step: int, actions: list) -> None:
        agent = self._agent
        agent.tracer.event(
            TraceEventKind.ACTIONS_PARSED,
            step=step,
            data={
                "count": len(actions),
                "actions": [
                    {
                        "thought": action.thought,
                        "action": str(action.action),
                        "params": action.params,
                    }
                    for action in actions
                ],
            },
        )
        for batch_index, action in enumerate(actions, start=1):
            agent.tracer.event(
                TraceEventKind.ACTION_PARSED,
                step=step,
                data={
                    "batch_index": batch_index,
                    "batch_count": len(actions),
                    "thought": action.thought,
                    "action": str(action.action),
                    "params": action.params,
                },
            )

    def _prepare_batch(
        self,
        step: int,
        actions: list,
    ) -> tuple[list[tuple[int, Any]], Any | None]:
        """Validate, map, and run safety on each action.

        Returns ``(prepared, done_after)`` where ``prepared`` is a list of
        ``(batch_index, action)`` tuples ready to execute, and
        ``done_after`` is a pending done action to fire after the batch.
        ``None`` for ``done_after`` means no done is pending.
        """
        agent = self._agent
        prepared: list[tuple[int, Any]] = []
        done_after: Any | None = None

        for batch_index, action in enumerate(actions, start=1):
            valid, error = validate_action_params(action)
            if not valid:
                agent.tracer.event(
                    TraceEventKind.ACTION_VALIDATION_FAILED,
                    step=step,
                    data={
                        "batch_index": batch_index,
                        "batch_count": len(actions),
                        "action": str(action.action),
                        "params": action.params,
                        "error": error,
                    },
                )
                agent.memory.add_message(
                    "assistant",
                    f"Invalid action: {error}. Please fix parameters.",
                )
                return [], None

            action = self._map_action_coordinates(step, action)

            if action.action is ActionKind.DONE:
                if prepared:
                    done_after = action
                    break
                return [], action

            safe, safety_error = agent.safety.validate_action(
                str(action.action), action.params
            )
            agent.tracer.event(
                TraceEventKind.SAFETY_CHECKED,
                step=step,
                data={
                    "batch_index": batch_index,
                    "batch_count": len(actions),
                    "action": str(action.action),
                    "params": action.params,
                    "allowed": safe,
                    "error": safety_error,
                },
            )
            if not safe:
                agent.tracer.event(
                    TraceEventKind.ACTION_BLOCKED,
                    step=step,
                    data={
                        "batch_index": batch_index,
                        "batch_count": len(actions),
                        "action": str(action.action),
                        "params": action.params,
                        "error": safety_error,
                    },
                )
                agent.memory.add_message(
                    "assistant",
                    f"Action blocked by safety: {safety_error}",
                )
                return [], None

            prepared.append((batch_index, action))

        return prepared, done_after

    def _map_action_coordinates(self, step: int, action) -> Any:
        agent = self._agent
        mapped, mappings = map_action_coordinates(
            action,
            screenshot_size=agent._last_screenshot_size,
            screen_width=agent.action_controller.screen_width,
            screen_height=agent.action_controller.screen_height,
        )
        if mappings and agent._last_screenshot_size is not None:
            screenshot_size = agent._last_screenshot_size
            agent.tracer.event(
                TraceEventKind.ACTION_COORDINATES_MAPPED,
                step=step,
                data={
                    "action": str(mapped.action),
                    "screenshot_size": {
                        "width": screenshot_size[0],
                        "height": screenshot_size[1],
                    },
                    "screen_size": {
                        "width": agent.action_controller.screen_width,
                        "height": agent.action_controller.screen_height,
                    },
                    "mappings": [
                        {
                            "x_key": m.x_key,
                            "y_key": m.y_key,
                            "input_x": m.input_x,
                            "input_y": m.input_y,
                            "mapped_x": m.mapped_x,
                            "mapped_y": m.mapped_y,
                        }
                        for m in mappings
                    ],
                },
            )
        return mapped

    def _execute_batch(
        self,
        *,
        step: int,
        prepared: list[tuple[int, Any]],
        batch_size: int,
    ) -> bool:
        agent = self._agent

        approved_batch: list[tuple[int, Any]] = []
        for batch_index, action in prepared:
            if not agent.request_action_approval(
                action=action,
                step=step,
                batch_index=batch_index,
                batch_count=batch_size,
            ):
                agent.memory.add_message(
                    "assistant",
                    (
                        "Action was not approved by the user. "
                        "Choose a safer alternative or finish if blocked."
                    ),
                )
                agent.tracer.event(
                    TraceEventKind.ACTION_BATCH_STOPPED,
                    step=step,
                    data={
                        "batch_index": batch_index,
                        "batch_count": batch_size,
                        "reason": "action_not_approved",
                        "action": str(action.action),
                    },
                )
                return False
            approved_batch.append((batch_index, action))

        for batch_index, action in approved_batch:
            agent.tracer.event(
                TraceEventKind.ACTION_EXECUTION_STARTED,
                step=step,
                data={
                    "batch_index": batch_index,
                    "batch_count": batch_size,
                    "thought": action.thought,
                    "action": str(action.action),
                    "params": action.params,
                    "target": agent.executor.visual_target(action),
                },
            )
            started = time.perf_counter()
            result = agent.executor.execute(action)
            agent.safety.record_action()
            agent.tracer.event(
                TraceEventKind.ACTION_EXECUTED,
                step=step,
                data={
                    "batch_index": batch_index,
                    "batch_count": batch_size,
                    "duration_seconds": time.perf_counter() - started,
                    "action": str(result.action),
                    "success": result.success,
                    "message": result.message,
                    "error": result.error,
                },
            )
            agent.memory.add_action(action, success=result.success)
            agent.memory.add_message(
                "assistant",
                f"Executed: {action.action} - {'Success' if result.success else 'Failed'}: {result.message or result.error}",
            )
            if agent._on_step is not None:
                agent._on_step(step, action)

            if not result.success:
                agent.tracer.event(
                    TraceEventKind.ACTION_BATCH_STOPPED,
                    step=step,
                    data={
                        "batch_index": batch_index,
                        "batch_count": batch_size,
                        "reason": "action_failed",
                        "action": str(result.action),
                        "error": result.error,
                    },
                )
                return False

            if agent._stop_requested:
                return False

            self._delay_between_batch_actions(batch_index, batch_size)

        return True

    def _complete_with_done(
        self,
        *,
        step: int,
        action,
        start_time: datetime,
        start_perf: float,
        final_screenshot: Image.Image | None,
    ) -> AgentResult:
        agent = self._agent
        success = action.params.get("success", True)
        message = action.params.get("result", "Task completed")
        agent.status = AgentStatus.COMPLETED
        agent.tracer.event(
            TraceEventKind.TASK_DONE,
            step=step,
            data={
                "thought": action.thought,
                "success": success,
                "message": message,
                "params": action.params,
            },
        )
        return self._finish(
            success=success,
            message=message,
            total_steps=step,
            start_time=start_time,
            start_perf=start_perf,
            final_screenshot=final_screenshot,
        )

    def _capture_screen(self, step: int) -> Image.Image:
        agent = self._agent
        agent.tracer.event(TraceEventKind.SCREENSHOT_CAPTURE_STARTED, step=step)
        started = time.perf_counter()

        try:
            screenshot = agent.screen.get_screenshot()
            raw_metadata = image_metadata(screenshot)

            if agent.config.capture.compress_screenshots:
                screenshot = agent.processing.compress_image(
                    screenshot,
                    max_size=agent.config.capture.max_screenshot_size,
                )

            agent._last_screenshot_size = (screenshot.width, screenshot.height)

            screenshot_path = agent.tracer.save_image(
                screenshot, step=step, label="screen",
            )
            agent.tracer.event(
                TraceEventKind.SCREENSHOT_CAPTURED,
                step=step,
                data={
                    "duration_seconds": time.perf_counter() - started,
                    "raw_image": raw_metadata,
                    "processed_image": image_metadata(screenshot),
                    "compressed": agent.config.capture.compress_screenshots,
                    "screenshot_path": screenshot_path,
                },
            )
        except Exception as exc:
            logger.exception("screenshot capture failed at step %d", step)
            agent.tracer.event(
                TraceEventKind.SCREENSHOT_ERROR,
                step=step,
                data={"error": exception_trace(exc)},
            )
            raise

        return screenshot

    def _capture_accessibility(self, step: int) -> AccessibilitySnapshot:
        agent = self._agent
        if not agent.config.capture.use_accessibility:
            return AccessibilitySnapshot(
                available=False,
                error="Accessibility capture is disabled.",
            )

        agent.tracer.event(TraceEventKind.ACCESSIBILITY_CAPTURE_STARTED, step=step)
        started = time.perf_counter()
        snapshot = agent.accessibility.capture(
            max_depth=agent.config.capture.accessibility_max_depth,
            max_nodes=agent.config.capture.accessibility_max_nodes,
        )
        agent.tracer.event(
            TraceEventKind.ACCESSIBILITY_CAPTURED,
            step=step,
            data={
                "duration_seconds": time.perf_counter() - started,
                "available": snapshot.available,
                "trusted": snapshot.trusted,
                "app": snapshot.app,
                "window": snapshot.window,
                "elements": len(snapshot.elements),
                "error": snapshot.error,
            },
        )
        return snapshot

    def _mouse_context(self, screenshot: Image.Image) -> dict[str, object]:
        agent = self._agent
        try:
            raw_x, raw_y = agent.action_controller.get_mouse_position()
            x = int(raw_x)
            y = int(raw_y)
        except Exception as exc:
            logger.debug("mouse position unavailable: %s", exc)
            return {"available": False, "error": str(exc)}

        screen_width = agent.action_controller.screen_width
        screen_height = agent.action_controller.screen_height
        context: dict[str, object] = {
            "available": True,
            "screen_position": {"x": x, "y": y},
        }
        if screen_width > 0 and screen_height > 0:
            context["screenshot_position"] = {
                "x": round(x * screenshot.width / screen_width),
                "y": round(y * screenshot.height / screen_height),
            }
        return context

    def _screen_context(
        self,
        screenshot: Image.Image,
        accessibility_snapshot: AccessibilitySnapshot,
        mouse_context: dict[str, object],
    ) -> dict:
        agent = self._agent
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
                    "width": agent.action_controller.screen_width,
                    "height": agent.action_controller.screen_height,
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
            context["app"] = agent.screen.get_app_context()
        except Exception:
            logger.debug("app context unavailable", exc_info=True)
            context["app"] = {"frontmost_app": None, "windows": []}
        return context

    def _finish(
        self,
        *,
        success: bool,
        message: str,
        total_steps: int,
        start_time: datetime,
        start_perf: float,
        final_screenshot: Image.Image | None,
    ) -> AgentResult:
        agent = self._agent
        duration_seconds = time.perf_counter() - start_perf
        trace_path = str(agent.tracer.path) if agent.tracer.path else None
        llm_usage = agent._llm_usage.copy()
        agent.tracer.event(
            TraceEventKind.RUN_FINISHED,
            data={
                "success": success,
                "message": message,
                "status": agent.status.value,
                "total_steps": total_steps,
                "actions_executed": agent.memory.total_actions,
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
            actions_executed=agent.memory.total_actions,
            duration_seconds=duration_seconds,
            final_screenshot=final_screenshot,
            trace_id=agent.tracer.run_id,
            trace_path=trace_path,
            llm_usage=llm_usage,
        )

    def _delay_between_steps(self, step: int) -> None:
        agent = self._agent
        delay = agent.config.loop.step_delay
        if delay <= 0:
            return
        if agent._stop_requested or step >= agent.config.loop.max_steps:
            return
        time.sleep(delay)

    def _delay_between_batch_actions(self, batch_index: int, batch_count: int) -> None:
        agent = self._agent
        if batch_index >= batch_count:
            return
        delay = agent.config.safety.min_action_delay
        if delay <= 0:
            return
        time.sleep(delay)


__all__ = ["ReActLoop"]
