"""Memory management for agent conversation and action history."""

from dataclasses import dataclass, field
from datetime import datetime
from typing import Any

from PIL import Image

from odin.agent.parser import ParsedAction


@dataclass
class ActionRecord:
    """Record of an executed action."""

    action: ParsedAction
    success: bool
    result_message: str | None
    timestamp: datetime = field(default_factory=datetime.now)


@dataclass
class AgentMemory:
    """
    Memory storage for the agent.

    Tracks conversation history, executed actions, and recent screenshots.
    """

    # LLM conversation messages
    messages: list[dict[str, Any]] = field(default_factory=list)

    # History of executed actions
    actions: list[ActionRecord] = field(default_factory=list)

    # Recent screenshots (limited to save memory)
    screenshots: list[Image.Image] = field(default_factory=list)

    # Maximum number of screenshots to keep
    max_screenshots: int = 5

    # Maximum number of messages to keep (for context window)
    max_messages: int = 20

    def add_message(self, role: str, content: str | list):
        """
        Add a message to conversation history.

        Args:
            role: Message role ("user" or "assistant")
            content: Message content (text or multimodal content)
        """
        self.messages.append({"role": role, "content": content})

        # Trim old messages if needed
        if len(self.messages) > self.max_messages:
            # Keep system message if present, trim oldest user/assistant messages
            if self.messages and self.messages[0].get("role") == "system":
                self.messages = [self.messages[0]] + self.messages[
                    -(self.max_messages - 1) :
                ]
            else:
                self.messages = self.messages[-self.max_messages :]

    def add_action(
        self, action: ParsedAction, success: bool, message: str | None = None
    ):
        """
        Record an executed action.

        Args:
            action: The action that was executed
            success: Whether the action succeeded
            message: Result or error message
        """
        self.actions.append(
            ActionRecord(
                action=action,
                success=success,
                result_message=message,
            )
        )

    def add_screenshot(self, image: Image.Image):
        """
        Add a screenshot to memory.

        Args:
            image: PIL Image of the screenshot
        """
        self.screenshots.append(image)

        # Trim old screenshots
        if len(self.screenshots) > self.max_screenshots:
            self.screenshots = self.screenshots[-self.max_screenshots :]

    def get_action_summary(self, last_n: int = 5) -> str:
        """
        Get a summary of recent actions for context.

        Args:
            last_n: Number of recent actions to include

        Returns:
            Formatted string summary
        """
        if not self.actions:
            return "No actions executed yet."

        recent = self.actions[-last_n:]
        lines = ["Recent actions:"]

        for record in recent:
            status = "✓" if record.success else "✗"
            line = f"  {status} {record.action.action}({record.action.params})"
            if record.result_message:
                line += f" → {record.result_message}"
            lines.append(line)

        return "\n".join(lines)

    def get_conversation_for_llm(self) -> list[dict[str, Any]]:
        """
        Get conversation history formatted for LLM.

        Returns:
            List of message dictionaries
        """
        return self.messages.copy()

    def clear(self):
        """Clear all memory."""
        self.messages.clear()
        self.actions.clear()
        self.screenshots.clear()

    @property
    def total_actions(self) -> int:
        """Total number of actions executed."""
        return len(self.actions)

    @property
    def successful_actions(self) -> int:
        """Number of successful actions."""
        return sum(1 for a in self.actions if a.success)
