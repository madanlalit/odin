"""Typed trace event names emitted by the agent loop.

Centralised as a :class:`StrEnum` so the tracer protocol can stay string-typed
for backward compatibility while every call site in the loop is checked.
"""

from __future__ import annotations

from enum import StrEnum


class TraceEventKind(StrEnum):
    """All structured trace events the agent loop emits."""

    RUN_STARTED = "run_started"
    RUN_FINISHED = "run_finished"

    STEP_STARTED = "step_started"

    SCREENSHOT_CAPTURE_STARTED = "screenshot_capture_started"
    SCREENSHOT_CAPTURED = "screenshot_captured"
    SCREENSHOT_ERROR = "screenshot_error"

    ACCESSIBILITY_CAPTURE_STARTED = "accessibility_capture_started"
    ACCESSIBILITY_CAPTURED = "accessibility_captured"

    MOUSE_POSITION_CAPTURED = "mouse_position_captured"

    LLM_REQUEST_STARTED = "llm_request_started"
    LLM_RESPONSE_RECEIVED = "llm_response_received"
    LLM_ERROR = "llm_error"

    ACTIONS_PARSED = "actions_parsed"
    ACTION_PARSED = "action_parsed"
    PARSE_ERROR = "parse_error"

    ACTION_VALIDATION_FAILED = "action_validation_failed"
    SAFETY_CHECKED = "safety_checked"
    ACTION_BLOCKED = "action_blocked"
    ACTION_COORDINATES_MAPPED = "action_coordinates_mapped"

    ACTION_APPROVAL_REQUESTED = "action_approval_requested"
    ACTION_APPROVAL_RECEIVED = "action_approval_received"

    ACTION_EXECUTION_STARTED = "action_execution_started"
    ACTION_EXECUTED = "action_executed"
    ACTION_BATCH_STOPPED = "action_batch_stopped"

    TASK_DONE = "task_done"
    UNEXPECTED_ERROR = "unexpected_error"


__all__ = ["TraceEventKind"]
