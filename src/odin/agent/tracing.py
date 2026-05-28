"""Structured tracing for agent runs."""

from __future__ import annotations

from dataclasses import asdict, dataclass, is_dataclass
from datetime import UTC, datetime
from enum import Enum
import json
from pathlib import Path
import traceback
from typing import Any, Protocol
from uuid import uuid4

from PIL import Image


@dataclass
class TraceEvent:
    """A single structured trace event."""

    timestamp: str
    run_id: str
    event: str
    step: int | None
    data: dict[str, Any]


class AgentTracer(Protocol):
    """Tracing interface used by the agent loop."""

    @property
    def run_id(self) -> str | None:
        """Current trace run ID."""
        ...

    @property
    def path(self) -> Path | None:
        """Trace output path, if any."""
        ...

    def start_run(self, task: str, metadata: dict[str, Any]) -> str:
        """Start a traced run and return its run ID."""
        ...

    def event(
        self,
        event: str,
        *,
        step: int | None = None,
        data: dict[str, Any] | None = None,
    ) -> None:
        """Record a trace event."""
        ...

    def save_image(
        self,
        image: Image.Image,
        *,
        step: int,
        label: str,
    ) -> str | None:
        """Persist an image artifact and return the saved path."""
        ...


class NoopTracer:
    """Tracer implementation that intentionally records nothing."""

    run_id: str | None = None
    path: Path | None = None

    def start_run(self, task: str, metadata: dict[str, Any]) -> str:
        """Return an empty run ID without recording anything."""
        return ""

    def event(
        self,
        event: str,
        *,
        step: int | None = None,
        data: dict[str, Any] | None = None,
    ) -> None:
        """Ignore a trace event."""

    def save_image(
        self,
        image: Image.Image,
        *,
        step: int,
        label: str,
    ) -> str | None:
        """Do not persist image artifacts."""
        return None


class JsonlTracer:
    """Append-only JSONL tracer with optional screenshot artifacts."""

    def __init__(
        self,
        path: str | Path,
        *,
        save_screenshots: bool = False,
        screenshots_dir: str | Path | None = None,
    ):
        """
        Initialize a JSONL tracer.

        Args:
            path: Trace file path.
            save_screenshots: Whether to save screenshot PNG artifacts.
            screenshots_dir: Optional screenshot artifact directory. Defaults to
                a sibling directory named after the trace file.
        """
        self.path = Path(path)
        self.path.parent.mkdir(parents=True, exist_ok=True)
        self.run_id: str | None = None
        self.save_screenshots = save_screenshots
        self.screenshots_dir = (
            Path(screenshots_dir)
            if screenshots_dir is not None
            else self.path.with_suffix("").parent / f"{self.path.stem}_screenshots"
        )

    def start_run(self, task: str, metadata: dict[str, Any]) -> str:
        """Start a traced run and emit a run_started event."""
        self.run_id = uuid4().hex
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
        """Append a structured trace event."""
        if self.run_id is None:
            self.run_id = uuid4().hex

        trace_event = TraceEvent(
            timestamp=_utc_now(),
            run_id=self.run_id,
            event=event,
            step=step,
            data=_json_safe(data or {}),
        )

        with self.path.open("a", encoding="utf-8") as file:
            file.write(json.dumps(asdict(trace_event), ensure_ascii=False) + "\n")

    def save_image(
        self,
        image: Image.Image,
        *,
        step: int,
        label: str,
    ) -> str | None:
        """Persist a screenshot artifact if enabled."""
        if not self.save_screenshots:
            return None

        if self.run_id is None:
            self.run_id = uuid4().hex

        self.screenshots_dir.mkdir(parents=True, exist_ok=True)
        safe_label = "".join(
            char if char.isalnum() or char in ("-", "_") else "_" for char in label
        )
        path = self.screenshots_dir / f"{self.run_id}_step_{step:03d}_{safe_label}.png"
        image.save(path)
        return str(path)


def exception_trace(exc: BaseException) -> dict[str, Any]:
    """Convert an exception to JSON-safe trace data."""
    return {
        "type": exc.__class__.__name__,
        "message": str(exc),
        "traceback": traceback.format_exception(type(exc), exc, exc.__traceback__),
    }


def image_metadata(image: Image.Image) -> dict[str, Any]:
    """Return trace-safe image metadata."""
    return {
        "width": image.width,
        "height": image.height,
        "mode": image.mode,
    }


def _utc_now() -> str:
    """Return an ISO-8601 UTC timestamp."""
    return datetime.now(UTC).isoformat().replace("+00:00", "Z")


def _json_safe(value: Any) -> Any:
    """Convert common Python objects to JSON-safe values."""
    if value is None or isinstance(value, str | int | float | bool):
        return value

    if isinstance(value, Path):
        return str(value)

    if isinstance(value, Enum):
        return value.value

    if isinstance(value, BaseException):
        return exception_trace(value)

    if isinstance(value, Image.Image):
        return image_metadata(value)

    if is_dataclass(value) and not isinstance(value, type):
        return _json_safe(asdict(value))

    if isinstance(value, dict):
        return {str(key): _json_safe(item) for key, item in value.items()}

    if isinstance(value, list | tuple | set):
        return [_json_safe(item) for item in value]

    return str(value)
