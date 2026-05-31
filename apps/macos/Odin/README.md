# Odin macOS App

Native SwiftUI shell for running the Python Odin agent from a minimal
Spotlight-style chat window.

## Run

From the repo root:

```bash
cd apps/macos/OdinApp
swift run OdinApp
```

The app launches `python -u -m odin.app_runner` (with `PYTHONUNBUFFERED=1`) and
streams JSONL trace events back into a live status line: current step, latest
thought, request count, and estimated cost. Toggle the activity log with the
list button next to the input to see each parsed step, executed action, and
error in order. After a run finishes, "Reveal trace" opens the JSONL file in
Finder. Settings live in the Odin menu bar icon and persist via `UserDefaults`;
provider API keys are stored in macOS Keychain.

## Settings

- Provider: OpenRouter or AWS Bedrock
- Model: optional provider-specific model ID
- API key: stored in Keychain for providers that need one
- AWS region: exported as `AWS_REGION`, `AWS_DEFAULT_REGION`, and
  `AWS_REGION_NAME`
- Repo path and Python path: used to launch the local Odin agent
- Max steps and max batch actions

For local development, the default Python path is `<repo>/.venv/bin/python3`
when it exists. The app also sets `PYTHONPATH=<repo>/src` so the local package is
available even before installation.
