"""
Odin - AI Computer Automation Agent

A ReAct loop agent that uses vision LLMs to automate computer tasks.
"""

from odin.agent import Agent, AgentConfig, AgentResult
from odin.llm import LLMClient, create_client

__version__ = "0.1.0"

__all__ = [
    "Agent",
    "AgentConfig",
    "AgentResult",
    "LLMClient",
    "create_client",
    "__version__",
]
