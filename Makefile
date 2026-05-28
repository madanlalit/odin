.PHONY: install dev test lint format typecheck run build-app run-app clean reset help

help:
	@echo "Available targets:"
	@echo "  install    - Install project dependencies"
	@echo "  dev        - Install project with dev dependencies"
	@echo "  test       - Run tests with pytest"
	@echo "  lint       - Run ruff linter"
	@echo "  format     - Format code with ruff"
	@echo "  typecheck  - Run type checking (mypy + pyright)"
	@echo "  run        - Run the agent"
	@echo "  build-app  - Build the macOS application"
	@echo "  run-app    - Run the macOS application"
	@echo "  clean      - Clean build artifacts and caches"
	@echo "  reset      - Reset app data, keychain credentials, and macOS permissions"
	@echo "  help       - Show this help message"

install:
	uv sync

dev:
	uv sync --group dev

test:
	uv run pytest tests/ -v

lint:
	uv run ruff check src/ tests/

format:
	uv run ruff format src/ tests/
	uv run ruff check --fix src/ tests/

typecheck:
	uv run mypy src/
	uv run pyright src/

run:
	uv run python -m odin

build-app:
	swift build --package-path apps/macos/OdinApp

run-app:
	swift run --package-path apps/macos/OdinApp Odin

clean:
	rm -rf .traces .pytest_cache .mypy_cache .ruff_cache __pycache__
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true

reset:
	@echo "Resetting Odin app data, trace logs, and preferences..."
	rm -rf .traces
	rm -f ~/Library/Preferences/Odin.plist ~/Library/Preferences/odin.plist
	killall cfprefsd 2>/dev/null || true
	@echo "Deleting Keychain stored API keys and AWS credentials..."
	security delete-generic-password -s odin.openrouter -a api-key 2>/dev/null || true
	security delete-generic-password -s odin.bedrock -a api-key 2>/dev/null || true
	security delete-generic-password -s odin.bedrock -a aws-access-key-id 2>/dev/null || true
	security delete-generic-password -s odin.bedrock -a aws-secret-access-key 2>/dev/null || true
	security delete-generic-password -s odin.bedrock -a aws-session-token 2>/dev/null || true
	@echo "Resetting macOS permissions (Accessibility & Screen Recording)..."
	tccutil reset Accessibility 2>/dev/null || true
	tccutil reset ScreenCapture 2>/dev/null || true
	@echo "Reset complete. Please restart the app and re-grant permissions."