.PHONY: install dev test lint format typecheck run clean help

# Default target
help:
	@echo "Available targets:"
	@echo "  install    - Install project dependencies"
	@echo "  dev        - Install project with dev dependencies"
	@echo "  test       - Run tests with pytest"
	@echo "  lint       - Run ruff linter"
	@echo "  format     - Format code with ruff"
	@echo "  typecheck  - Run type checking (mypy + pyright)"
	@echo "  run        - Run the agent"
	@echo "  clean      - Clean build artifacts and caches"
	@echo "  help       - Show this help message"

# Install dependencies
install:
	uv sync

# Install with dev dependencies
dev:
	uv sync --group dev

# Run tests
test:
	uv run pytest tests/ -v

# Run linter
lint:
	uv run ruff check src/ tests/

# Format code
format:
	uv run ruff format src/ tests/
	uv run ruff check --fix src/ tests/

# Type checking
typecheck:
	uv run mypy src/
	uv run pyright src/

# Run the agent
run:
	uv run python -m odin

# Clean build artifacts
clean:
	rm -rf .pytest_cache .mypy_cache .ruff_cache __pycache__
	find . -type d -name "__pycache__" -exec rm -rf {} + 2>/dev/null || true
	find . -type f -name "*.pyc" -delete 2>/dev/null || true
