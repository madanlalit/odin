"""Module-level logger for Odin.

A library should not configure logging handlers by default, so we attach a
:class:`logging.NullHandler` and let application code (the CLI, the macOS
app runner) install a real handler when desired. This avoids the
``No handlers could be found for logger "odin"`` warning without forcing
a particular output format on every consumer.
"""

from __future__ import annotations

import logging

_LOGGER_NAME = "odin"

logger = logging.getLogger(_LOGGER_NAME)
logger.addHandler(logging.NullHandler())
logger.propagate = False


__all__ = ["logger"]
