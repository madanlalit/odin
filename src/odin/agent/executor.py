"""Action dispatch and execution for the agent loop."""

from odin.action.controller import ActionController, ActionResult
from odin.action.elements import ElementActionHandler
from odin.agent.parser import ParsedAction
from odin.perception.accessibility import Accessibility


class ActionExecutor:
    """
    Dispatches parsed actions to the appropriate controller method.

    Coordinates raw actions (click, type, hotkey, scroll, etc.)
    and delegates element-based actions to :class:`ElementActionHandler`.
    """

    def __init__(
        self,
        action_controller: ActionController,
        element_handler: ElementActionHandler,
        accessibility: Accessibility,
    ):
        self.action_controller = action_controller
        self.element_handler = element_handler
        self.accessibility = accessibility

    def execute(self, action: ParsedAction) -> ActionResult:
        """Execute a parsed action."""
        params = action.params

        match action.action:
            case "click":
                return self.action_controller.click(
                    x=params["x"],
                    y=params["y"],
                    button=params.get("button", "left"),
                )
            case "click_element":
                return self.element_handler.click_element(
                    params["element_id"],
                    button=params.get("button", "left"),
                )
            case "double_click":
                return self.action_controller.double_click(
                    x=params["x"],
                    y=params["y"],
                )
            case "drag":
                return self.action_controller.drag(
                    start_x=params["start_x"],
                    start_y=params["start_y"],
                    end_x=params["end_x"],
                    end_y=params["end_y"],
                    duration=params.get("duration", 0.5),
                )
            case "double_click_element":
                return self.element_handler.double_click_element(params["element_id"])
            case "focus_element":
                return self.element_handler.focus_element(params["element_id"])
            case "move":
                return self.action_controller.move(
                    x=params["x"],
                    y=params["y"],
                )
            case "press_element":
                return self.element_handler.press_element(params["element_id"])
            case "type":
                return self.action_controller.type_text(
                    text=params["text"],
                )
            case "set_text":
                return self.element_handler.set_text_element(
                    params["element_id"],
                    params["text"],
                )
            case "hotkey":
                return self.action_controller.hotkey(*params["keys"])
            case "scroll":
                return self.action_controller.scroll(
                    direction=params["direction"],
                    clicks=params.get("amount", 3),
                    x=params.get("x"),
                    y=params.get("y"),
                )
            case "scroll_element":
                return self.element_handler.scroll_element(
                    params["element_id"],
                    direction=params["direction"],
                    amount=params.get("amount", 3),
                )
            case "wait":
                return self.action_controller.wait(
                    seconds=params["seconds"],
                )
            case _:
                return ActionResult(
                    success=False,
                    action=action.action,
                    error=f"Unknown action: {action.action}",
                )

    def visual_target(
        self,
        action: ParsedAction,
    ) -> dict[str, object] | None:
        """Return a screen-space point the macOS app can use for a visual cursor."""
        params = action.params

        if action.action in {"click", "double_click", "move"}:
            x = params.get("x")
            y = params.get("y")
            if isinstance(x, int | float) and isinstance(y, int | float):
                return {
                    "x": int(x),
                    "y": int(y),
                    "source": "coordinates",
                }

        if action.action == "drag":
            x = params.get("start_x")
            y = params.get("start_y")
            if isinstance(x, int | float) and isinstance(y, int | float):
                return {
                    "x": int(x),
                    "y": int(y),
                    "source": "coordinates",
                }

        if action.action == "scroll":
            x = params.get("x")
            y = params.get("y")
            if isinstance(x, int | float) and isinstance(y, int | float):
                return {
                    "x": int(x),
                    "y": int(y),
                    "source": "coordinates",
                }
            return None

        if action.action in {
            "click_element",
            "double_click_element",
            "focus_element",
            "press_element",
            "scroll_element",
            "set_text",
        }:
            element_id = params.get("element_id")
            if not isinstance(element_id, str):
                return None

            frame = self.accessibility.frame(element_id)
            if frame is None:
                return None

            x, y = frame.center
            return {
                "x": x,
                "y": y,
                "source": "accessibility",
                "element_id": element_id,
                "frame": frame.to_dict(),
            }

        return None
