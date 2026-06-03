"""Memory management for agent conversation and action history."""

from dataclasses import dataclass, field
from typing import Any

from odin.agent.parser import ParsedAction


@dataclass
class ActionRecord:
    """Record of an executed action."""

    action: ParsedAction
    success: bool


@dataclass
class AgentMemory:
    """Memory storage for the agent.

    Tracks conversation history and executed actions.
    """

    messages: list[dict[str, Any]] = field(default_factory=list)

    actions: list[ActionRecord] = field(default_factory=list)

    max_messages: int = 20

    def add_message(self, role: str, content: str | list):
        """Append a message to conversation history.

        Trims oldest messages when the configured limit is exceeded so the
        prompt sent to the LLM stays bounded.
        """
        self.messages.append({"role": role, "content": content})

        if len(self.messages) > self.max_messages:
            if self.messages and self.messages[0].get("role") == "system":
                self.messages = [
                    self.messages[0],
                    *self.messages[-(self.max_messages - 1) :],
                ]
            else:
                self.messages = self.messages[-self.max_messages :]

    def add_action(self, action: ParsedAction, success: bool) -> None:
        """Record an executed action."""
        self.actions.append(ActionRecord(action=action, success=success))

    def get_conversation_for_llm(self) -> list[dict[str, Any]]:
        """Return a copy of the conversation history formatted for the LLM."""
        return self.messages.copy()

    def clear(self) -> None:
        """Clear all memory."""
        self.messages.clear()
        self.actions.clear()

    @property
    def total_actions(self) -> int:
        """Total number of actions executed."""
        return len(self.actions)
