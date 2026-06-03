"""JSONL runner for the macOS app shell."""

from __future__ import annotations

import argparse
import json
import os
import sys
from dataclasses import asdict
from pathlib import Path
from typing import Any, TextIO
from uuid import uuid4

from dotenv import load_dotenv

from odin import Agent, AgentConfig, create_client
from odin.action.safety import SafetyConfig
from odin.agent.tracing import JsonlTracer, TraceEvent, _json_safe, _utc_now


class StdoutJsonlTracer:
    """Trace sink that streams agent events to stdout and optionally to disk."""

    def __init__(
        self,
        stream: TextIO,
        *,
        trace_path: str | Path | None = None,
        save_screenshots: bool = False,
    ):
        self._stream = stream
        self._file_tracer = (
            JsonlTracer(trace_path, save_screenshots=save_screenshots)
            if trace_path
            else None
        )
        self.path = self._file_tracer.path if self._file_tracer else None
        self.run_id: str | None = None

    def start_run(self, task: str, metadata: dict[str, Any]) -> str:
        """Start a run and emit run_started."""
        self.run_id = uuid4().hex
        if self._file_tracer:
            self._file_tracer.run_id = self.run_id
        self.event(
            "run_started",
            data={
                "task": task,
                **metadata,
            },
        )
        return self.run_id

    def event(
        self,
        event: str,
        *,
        step: int | None = None,
        data: dict[str, Any] | None = None,
    ) -> None:
        """Stream one trace event."""
        if self.run_id is None:
            self.run_id = uuid4().hex
            if self._file_tracer:
                self._file_tracer.run_id = self.run_id

        trace_event = TraceEvent(
            timestamp=_utc_now(),
            run_id=self.run_id,
            event=event,
            step=step,
            data=_json_safe(data or {}),
        )
        payload = json.dumps(asdict(trace_event), ensure_ascii=False)
        self._stream.write(payload + "\n")
        self._stream.flush()

        if self._file_tracer:
            self._file_tracer.event(event, step=step, data=data)

    def save_image(self, image: Any, *, step: int, label: str) -> str | None:
        """Persist screenshots through the file tracer when enabled."""
        if not self._file_tracer:
            return None
        if self.run_id is not None:
            self._file_tracer.run_id = self.run_id
        return self._file_tracer.save_image(image, step=step, label=label)


class StdinActionApprover:
    """Wait for app-provided approval responses on stdin."""

    def __init__(self, stream: TextIO):
        self._stream = stream

    def __call__(self, request: dict[str, Any]) -> bool:
        request_id = request.get("request_id")
        while True:
            line = self._stream.readline()
            if line == "":
                return False

            try:
                payload = json.loads(line)
            except json.JSONDecodeError:
                continue

            if payload.get("event") != "action_approval_response":
                continue
            if payload.get("request_id") != request_id:
                continue
            return bool(payload.get("approved"))


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Run Odin for the macOS app and stream JSONL events.",
    )
    parser.add_argument("--task", required=True, help="Natural-language task.")
    parser.add_argument(
        "--provider",
        choices=["openrouter", "bedrock"],
        default=os.environ.get("ODIN_LLM_PROVIDER", "openrouter"),
        help="LLM provider to use.",
    )
    parser.add_argument("--model", default=None, help="Provider model identifier.")
    parser.add_argument(
        "--max-steps",
        type=int,
        default=AgentConfig().loop.max_steps,
        help="Maximum agent steps.",
    )
    parser.add_argument(
        "--max-batch-actions",
        type=int,
        default=AgentConfig().loop.max_batch_actions,
        help="Maximum actions accepted per LLM response.",
    )
    parser.add_argument(
        "--trace-path",
        default=None,
        help="Optional JSONL trace path to mirror streamed events.",
    )
    parser.add_argument(
        "--trace-screenshots",
        action="store_true",
        help="Save screenshot artifacts when trace-path is set.",
    )
    parser.add_argument(
        "--require-action-approval",
        action="store_true",
        help="Wait for app approval before executing every non-done action.",
    )
    return parser


def _emit(stream: TextIO, event: str, data: dict[str, Any]) -> None:
    stream.write(
        json.dumps(
            {
                "timestamp": _utc_now(),
                "run_id": None,
                "event": event,
                "step": None,
                "data": _json_safe(data),
            },
            ensure_ascii=False,
        )
        + "\n"
    )
    stream.flush()


def main(argv: list[str] | None = None) -> int:
    """Run the app-facing JSONL agent process."""
    load_dotenv()
    args = _build_parser().parse_args(argv)

    try:
        sys.stdout.reconfigure(line_buffering=True)  # type: ignore[union-attr]
        sys.stderr.reconfigure(line_buffering=True)  # type: ignore[union-attr]
    except (AttributeError, ValueError):
        pass

    if args.provider == "openrouter" and not os.environ.get("OPENROUTER_API_KEY"):
        _emit(
            sys.stdout,
            "app_runner_error",
            {
                "message": (
                    "OPENROUTER_API_KEY is not set. Add it in Settings or your "
                    "environment."
                )
            },
        )
        return 1

    tracer = StdoutJsonlTracer(
        sys.stdout,
        trace_path=args.trace_path,
        save_screenshots=args.trace_screenshots,
    )

    llm = None
    try:
        llm = create_client(provider=args.provider, model=args.model)
        agent = Agent(
            llm,
            config=AgentConfig(
                loop=AgentConfig().loop.model_copy(update={
                    "max_steps": args.max_steps,
                    "max_batch_actions": max(1, args.max_batch_actions),
                }),
                trace=AgentConfig().trace.model_copy(update={
                    "path": args.trace_path,
                    "save_screenshots": args.trace_screenshots,
                }),
                safety=SafetyConfig(
                    require_confirmation=args.require_action_approval,
                ),
            ),
            tracer=tracer,
            action_approval_callback=StdinActionApprover(sys.stdin)
            if args.require_action_approval
            else None,
        )
        result = agent.run(args.task)
        tracer.event(
            "app_runner_finished",
            data={
                "success": result.success,
                "message": result.message,
                "total_steps": result.total_steps,
                "actions_executed": result.actions_executed,
                "duration_seconds": result.duration_seconds,
                "trace_id": result.trace_id,
                "trace_path": result.trace_path,
                "llm_usage": result.llm_usage,
            },
        )
        return 0 if result.success else 1
    except KeyboardInterrupt:
        tracer.event("app_runner_interrupted", data={"message": "Interrupted by user."})
        return 130
    except Exception as exc:
        tracer.event(
            "app_runner_error",
            data={
                "type": exc.__class__.__name__,
                "message": str(exc),
            },
        )
        return 1
    finally:
        if llm is not None:
            llm.close()


if __name__ == "__main__":
    sys.exit(main())
