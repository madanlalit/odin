"""Tests for the app-facing JSONL runner."""

import json
from io import StringIO

from odin.app_runner import StdinActionApprover, StdoutJsonlTracer


def test_stdout_jsonl_tracer_streams_events():
    """The macOS app runner tracer writes structured JSONL events."""
    stream = StringIO()
    tracer = StdoutJsonlTracer(stream)

    run_id = tracer.start_run("Open Finder", metadata={"llm": {"model": "test"}})
    tracer.event("action_executed", step=1, data={"message": "Pressed command+space"})

    lines = [json.loads(line) for line in stream.getvalue().splitlines()]

    assert lines[0]["event"] == "run_started"
    assert lines[0]["run_id"] == run_id
    assert lines[0]["data"]["task"] == "Open Finder"
    assert lines[1]["event"] == "action_executed"
    assert lines[1]["step"] == 1
    assert lines[1]["data"]["message"] == "Pressed command+space"


def test_stdin_action_approver_waits_for_matching_response():
    """The app runner accepts only the approval response for the request id."""
    stream = StringIO(
        '{"event":"action_approval_response","request_id":"other","approved":true}\n'
        '{"event":"action_approval_response","request_id":"abc","approved":true}\n'
    )
    approver = StdinActionApprover(stream)

    assert approver({"request_id": "abc"}) is True


def test_stdin_action_approver_denies_on_eof():
    """EOF means the app went away, so the action should not execute."""
    approver = StdinActionApprover(StringIO(""))

    assert approver({"request_id": "abc"}) is False
