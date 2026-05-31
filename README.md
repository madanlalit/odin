<p align="center">
  <img src="docs/assets/odin_logo.png" alt="Odin Logo" width="100%">
  <br>
  <em>AI-powered computer automation agent using vision LLMs.</em>
  <br><br>
  <a href="https://opensource.org/licenses/MIT"><img src="https://img.shields.io/badge/License-MIT-yellow.svg" alt="License: MIT"></a>
  <img src="https://img.shields.io/badge/python-3.12+-blue.svg" alt="Python 3.12+">

## Demo

![Odin Demo](docs/assets/odin_demo.gif)

## Architecture

```mermaid
graph TD
    A[Screen Capture] --> B[Image Processing]
    B --> C[LLM Vision Model]
    C --> D[Action Parser]
    D --> E[Safety Check]
    E --> F[Action Controller]
    F --> G{Task Complete?}
    G -->|No| A
    G -->|Yes| H[Return Result]
```

## Features

- **ReAct Loop**: Reason + Act pattern for intelligent automation
- **Vision LLM**: Supports optional OpenRouter and AWS Bedrock providers
- **Screen Context**: Sends active app info, window lists, mouse position, and accessibility tree alongside screenshots
- **Element Actions**: Press, click, focus, set text, and scroll by accessibility ID
- **CoreGraphics Fallbacks**: Coordinate click, type, scroll, hotkeys, and more
- **Safety Layer**: Rate limiting, bounds checking, dangerous action detection
- **Memory**: Tracks conversation history and executed actions

## Installation

```bash
# Clone the repo
git clone https://github.com/your-username/odin.git
cd odin

# Install with uv and your preferred LLM provider extra
uv sync --extra openrouter
# or
uv sync --extra bedrock
```

## Setup

Configure your LLM provider credentials:

- **OpenRouter**: Set your API key in the environment or in a local `.env` file:
  ```bash
  export OPENROUTER_API_KEY="your-api-key"
  ```
- **AWS Bedrock**: Configure standard AWS SDK credentials and region:
  ```bash
  export ODIN_LLM_PROVIDER=bedrock
  export AWS_REGION="us-east-1"
  ```

Grant permissions (macOS):
- **Screen Recording**: System Settings → Privacy & Security → Screen Recording
- **Accessibility**: System Settings → Privacy & Security → Accessibility

## Usage

```python
from odin import Agent, create_client

# Create LLM client after installing odin[openrouter]
llm = create_client(model="google/gemini-2.0-flash-001")

# Or use AWS Bedrock after installing odin[bedrock]
llm = create_client(provider="bedrock", model="us.anthropic.claude-opus-4-7")

# Create agent
agent = Agent(llm)

# Run a task
result = agent.run("Open Safari and search for 'weather today'")

print(f"Success: {result.success}")
print(f"Message: {result.message}")
print(f"Steps: {result.total_steps}")
```

## macOS App Shell

Odin includes a SwiftUI native menu-bar application with a Spotlight-style chat interface. All provider configuration, API keys, and custom parameters are managed directly from the menu bar settings.

### Development Mode

To run the application locally in developer mode:

```bash
# Run using Swift Package Manager
swift run --package-path apps/macos/Odin Odin
```

### Standalone Packaging

To bundle the application into a self-contained, standard macOS app with an embedded standalone Python runtime and dependencies:

```bash
# Build the standalone Odin.dmg installer
make bundle-app
```

This compiles the Swift application in release mode, downloads and embeds a relocatable Python runtime and pip dependencies into the bundle resources, packages everything into a drag-and-drop installer `dist/Odin.dmg`, and automatically cleans up intermediate build files.

#### Installing & Running the App

Since the app is signed ad-hoc, macOS Gatekeeper blocks it with a quarantine attribute when it's copied from a DMG. To install and start the app:

1. Double-click `dist/Odin.dmg` and drag `Odin.app` into your **Applications** folder.
2. Open your terminal and clear the quarantine attribute:
   ```bash
   xattr -cr /Applications/Odin.app
   ```
3. Run `Odin` from Applications or Spotlight.

## Configuration

```python
from odin import Agent, AgentConfig
from odin.action.safety import SafetyConfig

config = AgentConfig(
    max_steps=100,          # Max steps before stopping
    step_delay=0.5,         # Delay between steps
    use_accessibility=True, # Include macOS accessibility tree context
    max_batch_actions=5,    # Max actions accepted per LLM call
    safety=SafetyConfig(
        max_actions_per_minute=60,
        min_action_delay=0.1,
    ),
)

agent = Agent(llm, config=config)
```

## Screen Context & Accessibility

Alongside the screenshot, Odin compiles a structured, prompt-safe text context detailing the system state. This context includes:

1. **Coordinate System**: The resolution of the screenshot and display size, helping the model align clicks correctly.
2. **Mouse Position**: The active coordinates of the mouse pointer.
3. **App Context**: Information about the frontmost application, running user-facing apps, window bounds, and visible windows across spaces.
4. **macOS Accessibility Tree (AX Tree)**: A hierarchy of UI elements (up to `accessibility_max_nodes` limits) including roles, labels, values, states (focused/enabled), native actions, and frames.

The model can utilize element-based actions directly referencing accessibility IDs:

```json
{"thought": "The Submit button is visible.", "actions": [{"action": "press_element", "params": {"element_id": "ax_12"}}]}
```

Supported element actions include `click_element`, `double_click_element`, `press_element`, `focus_element`, `set_text`, and `scroll_element`. Odin tries native AX actions first where possible and falls back to the element frame center using Quartz mouse/keyboard events when appropriate.

## Tracing

Odin can write structured JSONL traces for each agent run:

```bash
uv run python -m odin "Open Safari" \
  --trace-path .traces/run.jsonl \
  --trace-screenshots
```

Trace events include run lifecycle, screenshot capture, LLM request/response,
parse results, safety decisions, action execution, failures, token usage, and
final result metadata. `--trace-screenshots` saves PNG artifacts next to the
trace file.

For Bedrock, Odin records `usage.inputTokens`, `usage.outputTokens`, and
`usage.totalTokens` from the Converse response. Estimated USD cost is included
when token prices are configured. Claude Opus 4.7 standard rates are built in
for `anthropic.claude-opus-4-7` and its `us.`, `eu.`, `jp.`, `au.`, and
`global.` inference profile IDs. Override rates for a specific model, region,
or tier when needed:

```bash
export ODIN_BEDROCK_INPUT_COST_PER_1K_TOKENS="0.005"
export ODIN_BEDROCK_OUTPUT_COST_PER_1K_TOKENS="0.025"
```

Use the current AWS Bedrock pricing page for the model and region you run.

To inspect the exact system prompt sent to the model:

```bash
uv run python -m odin --show-system-prompt
```

Odin expects batch-style model responses by default. Even one action is returned
inside an `actions` array, and `--max-batch-actions` limits the accepted batch
size:

```bash
uv run python -m odin "Open Safari" --max-batch-actions 5
```

## Project Structure

```
src/odin/
├── agent/           # ReAct loop agent
│   ├── core.py      # Main agent class
│   ├── memory.py    # Conversation/action history
│   ├── parser.py    # LLM response parser
│   └── tracing.py   # Structured JSONL tracing
├── action/          # GUI automation
│   ├── controller.py # Quartz backend GUI actions
│   └── safety.py    # Safety checks
├── llm/             # LLM integration
│   ├── base.py      # Provider protocol and response types
│   ├── factory.py   # Provider selection and client construction
│   ├── providers/   # Optional provider implementations
│   │   ├── openrouter.py
│   │   └── bedrock.py
│   └── prompts.py   # System prompts
└── perception/      # Screen capture
    ├── accessibility.py # macOS AX tree capture and element lookup
    ├── screen.py    # Screenshot capture
    └── processing.py # Image processing
```

## License

MIT
