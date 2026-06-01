# Odin macOS App

Native SwiftUI shell for running the Python Odin agent from a minimal
Spotlight-style chat window. Built on macOS 26 Liquid Glass.

## Design system

The app's visual identity — **The Eye of Odin** — is structured as a strict
design system under `Sources/Odin/DesignSystem/`. Nothing in feature code
references raw colors, font sizes, or ad-hoc springs.

```
Sources/Odin/DesignSystem/
├── Tokens.swift        # Color, typography, spacing, radius, sizing tokens
├── Motion.swift        # The four named animations: rise, settle, breathe, snap
├── Surfaces.swift      # odinPanelSurface, odinCard, Hairline
├── OdinEye.swift       # The product mark (5 states: idle/watching/awaiting/done/error)
├── Field.swift         # OdinField, OdinTextArea, OdinSegmentedPicker, OdinToggle
├── ButtonStyles.swift  # Primary/Soft/Destructive/Text/IconCircle button styles
├── Chip.swift          # OdinChip, OdinLibraryCard, OdinDot, OdinMenuRow
├── Stage.swift         # StageHeader (Idle/Working/Awaiting/Done/Error) + TakeoverDetails
├── Command.swift       # CommandBar (the input + controls zone)
├── Library.swift       # LibraryStrip (pinned + recents)
├── WhisperLog.swift    # WhisperLog (timeline of recent agent actions)
├── Notifications.swift # Cross-component notification names
└── Previews.swift      # SwiftUI Preview gallery (Xcode Canvas)
```

The one chromatic color in the system is **Norse amber** (`#E8A33D` light /
`#F0B452` dark), used sparingly for: the iris when active, the primary
action, selected borders, and the success halo. Everything else is a
monochrome ramp on a liquid-glass surface.

The chat panel is organized as three calm zones — **Stage** (what's
happening), **Command** (the input), **Library** (pinned and recent
tasks) — separated by hairlines, not cards. The state of the panel is
its shape: idle is compact, working grows to show progress, awaiting
grows further to show the takeover card.

## Run

From the repo root:

```bash
swift run --package-path apps/macos/Odin Odin
```

The app launches `python -u -m odin.app_runner` (with `PYTHONUNBUFFERED=1`)
and streams JSONL trace events back into the WhisperLog strip in the
panel. The Stage shows the current step, phase, and elapsed time. After
a run finishes, the Stage switches to a "Done" state and the Library
gains the new task. "Reveal trace" in the status menu opens the JSONL
file in Finder. Settings live in the Odin menu bar icon and persist via
`UserDefaults`; provider API keys are stored in macOS Keychain.

## Settings

- Provider: OpenRouter or AWS Bedrock
- Model: optional provider-specific model ID
- API key: stored in Keychain for providers that need one
- AWS region: exported as `AWS_REGION`, `AWS_DEFAULT_REGION`, and
  `AWS_REGION_NAME`
- Repo path and Python path: used to launch the local Odin agent
- Max steps and max batch actions
- Reduce motion: hand-tuned accessibility preference

For local development, the default Python path is `<repo>/.venv/bin/python3`
when it exists. The app also sets `PYTHONPATH=<repo>/src` so the local
package is available even before installation.
