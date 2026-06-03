"""Tests for agent memory management."""

from odin.agent.memory import AgentMemory
from odin.agent.parser import ParsedAction


class TestAgentMemory:
    """Tests for agent memory management."""

    def test_add_message(self):
        """Test adding messages to memory."""
        memory = AgentMemory()
        memory.add_message("user", "Hello")
        memory.add_message("assistant", "Hi there")

        assert len(memory.messages) == 2
        assert memory.messages[0]["role"] == "user"
        assert memory.messages[1]["content"] == "Hi there"

    def test_message_trimming(self):
        """Test that old messages are trimmed when limit exceeded."""
        memory = AgentMemory(max_messages=3)

        for i in range(5):
            memory.add_message("user", f"Message {i}")

        assert len(memory.messages) == 3
        assert memory.messages[-1]["content"] == "Message 4"

    def test_add_action(self):
        """Test adding action records."""
        memory = AgentMemory()
        action = ParsedAction(
            thought="test",
            action="click",
            params={"x": 100, "y": 200},
            raw_response="",
        )

        memory.add_action(action, success=True)

        assert len(memory.actions) == 1
        assert memory.actions[0].success is True
        assert memory.total_actions == 1

    def test_clear(self):
        """Test clearing memory."""
        memory = AgentMemory()
        memory.add_message("user", "test")
        memory.add_action(
            ParsedAction("", "click", {"x": 0, "y": 0}, ""),
            success=True,
        )

        memory.clear()

        assert len(memory.messages) == 0
        assert len(memory.actions) == 0

    def test_get_conversation_for_llm(self):
        """Test getting conversation formatted for LLM."""
        memory = AgentMemory()
        memory.add_message("user", "test1")
        memory.add_message("assistant", "test2")

        conversation = memory.get_conversation_for_llm()

        assert len(conversation) == 2
        conversation.append({"role": "test"})
        assert len(memory.messages) == 2
