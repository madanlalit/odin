"""Core agent implementing the ReAct loop for screen automation."""

from dataclasses import dataclass, field
from datetime import datetime
from enum import Enum
import time
from typing import Callable

from PIL import Image

from odin.action.controller import ActionController
from odin.action.safety import SafetyConfig, SafetyController
from odin.agent.memory import AgentMemory
from odin.agent.parser import (
    ParsedAction,
    ParseError,
    parse_llm_response,
    validate_action_params,
)
from odin.llm.client import LLMClient
from odin.llm.prompts import SYSTEM_PROMPT
from odin.perception.processing import Processing
from odin.perception.screen import Screen


class AgentStatus(Enum):
    """Status of the agent."""

    IDLE = "idle"
    RUNNING = "running"
    COMPLETED = "completed"
    FAILED = "failed"
    STOPPED = "stopped"


@dataclass
class AgentResult:
    """Result of an agent run."""

    success: bool
    message: str
    total_steps: int
    actions_executed: int
    duration_seconds: float
    final_screenshot: Image.Image | None = None


@dataclass
class AgentConfig:
    """Configuration for the agent."""

    # Maximum steps before stopping
    max_steps: int = 50

    # Delay between steps (seconds)
    step_delay: float = 0.5

    # Whether to use grid overlay on screenshots
    use_grid: bool = True

    # Grid step size in pixels
    grid_step: int = 100

    # Whether to compress screenshots
    compress_screenshots: bool = True

    # Max screenshot size
    max_screenshot_size: tuple[int, int] = (1920, 1080)

    # Safety configuration
    safety: SafetyConfig = field(default_factory=SafetyConfig)


class Agent:
    """
    Main agent implementing the ReAct (Reason + Act) loop.

    The agent:
    1. Captures a screenshot of the current screen
    2. Sends it to the LLM with the task and history
    3. Parses the action from the LLM response
    4. Executes the action (with safety checks)
    5. Repeats until task is complete or max steps reached
    """

    def __init__(
        self,
        llm_client: LLMClient,
        config: AgentConfig | None = None,
        on_step: Callable[[int, ParsedAction], None] | None = None,
    ):
        """
        Initialize the agent.

        Args:
            llm_client: LLM client for vision analysis
            config: Agent configuration
            on_step: Optional callback called after each step
        """
        self.llm = llm_client
        self.config = config or AgentConfig()

        # Components
        self.screen = Screen()
        self.processing = Processing()
        self.action_controller = ActionController()
        self.safety = SafetyController(self.config.safety)
        self.memory = AgentMemory()

        # State
        self.status = AgentStatus.IDLE
        self._stop_requested = False
        self._on_step = on_step

    def run(self, task: str) -> AgentResult:
        """
        Execute the ReAct loop to accomplish a task.

        Args:
            task: Natural language description of the task

        Returns:
            AgentResult with execution details
        """
        self.status = AgentStatus.RUNNING
        self._stop_requested = False
        self.memory.clear()

        start_time = datetime.now()
        step = 0
        final_screenshot = None

        try:
            while step < self.config.max_steps and not self._stop_requested:
                step += 1

                # Step 1: Capture screenshot
                screenshot = self._capture_screen()
                final_screenshot = screenshot

                # Step 2: Analyze with LLM
                try:
                    response = self.llm.analyze_screen(
                        image=screenshot,
                        task=task,
                        system_prompt=SYSTEM_PROMPT,
                        history=self.memory.get_conversation_for_llm(),
                    )
                except Exception as e:
                    self.status = AgentStatus.FAILED
                    return AgentResult(
                        success=False,
                        message=f"LLM error: {e}",
                        total_steps=step,
                        actions_executed=self.memory.total_actions,
                        duration_seconds=(datetime.now() - start_time).total_seconds(),
                        final_screenshot=final_screenshot,
                    )

                # Step 3: Parse action
                try:
                    action = parse_llm_response(response.content)
                except ParseError as e:
                    # Add error to history and continue
                    self.memory.add_message(
                        "assistant",
                        f"Parse error: {e}. Please respond with valid JSON.",
                    )
                    self._delay_between_steps(step)
                    continue

                # Validate action parameters
                valid, error = validate_action_params(action)
                if not valid:
                    self.memory.add_message(
                        "assistant",
                        f"Invalid action: {error}. Please fix parameters.",
                    )
                    self._delay_between_steps(step)
                    continue

                # Step 4: Check for done action
                if action.action == "done":
                    self.status = AgentStatus.COMPLETED
                    success = action.params.get("success", True)
                    result_msg = action.params.get("result", "Task completed")

                    return AgentResult(
                        success=success,
                        message=result_msg,
                        total_steps=step,
                        actions_executed=self.memory.total_actions,
                        duration_seconds=(datetime.now() - start_time).total_seconds(),
                        final_screenshot=final_screenshot,
                    )

                # Step 5: Safety check
                safe, safety_error = self.safety.validate_action(
                    action.action, action.params
                )
                if not safe:
                    self.memory.add_message(
                        "assistant",
                        f"Action blocked by safety: {safety_error}",
                    )
                    self._delay_between_steps(step)
                    continue

                # Step 6: Execute action
                result = self._execute_action(action)
                self.safety.record_action()

                # Record in memory
                self.memory.add_action(
                    action,
                    success=result.success,
                    message=result.message or result.error,
                )

                # Add to conversation history
                self.memory.add_message(
                    "assistant",
                    f"Executed: {action.action} - {'Success' if result.success else 'Failed'}: {result.message or result.error}",
                )

                # Callback
                if self._on_step:
                    self._on_step(step, action)

                self._delay_between_steps(step)

            # Max steps reached
            self.status = (
                AgentStatus.STOPPED if self._stop_requested else AgentStatus.FAILED
            )
            return AgentResult(
                success=False,
                message="Max steps reached"
                if not self._stop_requested
                else "Stopped by user",
                total_steps=step,
                actions_executed=self.memory.total_actions,
                duration_seconds=(datetime.now() - start_time).total_seconds(),
                final_screenshot=final_screenshot,
            )

        except Exception as e:
            self.status = AgentStatus.FAILED
            return AgentResult(
                success=False,
                message=f"Unexpected error: {e}",
                total_steps=step,
                actions_executed=self.memory.total_actions,
                duration_seconds=(datetime.now() - start_time).total_seconds(),
                final_screenshot=final_screenshot,
            )

    def stop(self):
        """Request the agent to stop after the current step."""
        self._stop_requested = True

    def _delay_between_steps(self, step: int) -> None:
        """Apply configured delay before the next step, if any."""
        if self.config.step_delay <= 0:
            return
        if self._stop_requested or step >= self.config.max_steps:
            return
        time.sleep(self.config.step_delay)

    def _capture_screen(self) -> Image.Image:
        """Capture and process the current screen."""
        screenshot = self.screen.get_screenshot()

        # Compress if configured
        if self.config.compress_screenshots:
            screenshot = self.processing.compress_image(
                screenshot,
                max_size=self.config.max_screenshot_size,
            )

        # Add grid overlay if configured
        if self.config.use_grid:
            grid = self.processing.draw_grids(
                screenshot.width,
                screenshot.height,
                step=self.config.grid_step,
            )
            screenshot = Image.alpha_composite(
                screenshot.convert("RGBA"),
                grid,
            ).convert("RGB")

        # Save to memory
        self.memory.add_screenshot(screenshot)

        return screenshot

    def _execute_action(self, action: ParsedAction):
        """Execute a parsed action."""
        params = action.params

        match action.action:
            case "click":
                return self.action_controller.click(
                    x=params["x"],
                    y=params["y"],
                    button=params.get("button", "left"),
                )
            case "double_click":
                return self.action_controller.double_click(
                    x=params["x"],
                    y=params["y"],
                )
            case "move":
                return self.action_controller.move(
                    x=params["x"],
                    y=params["y"],
                )
            case "type":
                return self.action_controller.type_text(
                    text=params["text"],
                )
            case "hotkey":
                return self.action_controller.hotkey(*params["keys"])
            case "scroll":
                return self.action_controller.scroll(
                    direction=params["direction"],
                    clicks=params.get("amount", 3),
                )
            case "wait":
                return self.action_controller.wait(
                    seconds=params["seconds"],
                )
            case _:
                from odin.action.controller import ActionResult

                return ActionResult(
                    success=False,
                    action=action.action,
                    error=f"Unknown action: {action.action}",
                )
