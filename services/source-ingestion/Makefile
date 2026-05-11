## Makefile for the source-ingestion Python sub-project.
##
## All targets run inside the project's uv-managed venv. Run from this directory
## (services/source-ingestion). The `help` target lists what's available.

PYTHON      := uv run python
PYTEST      := uv run pytest
RUFF        := uv run ruff
PYRIGHT     := uv run pyright

SRC_DIRS    := src tests scripts
SCHEMAS_DIR := schemas
OUTPUT_DIR  := output

.PHONY: help sync test test-verbose lint lint-fix format format-check typecheck \
        schemas schemas-check ci clean clean-output

help: ## Print available targets
	@awk 'BEGIN {FS = ":.*##"} /^[a-zA-Z_-]+:.*##/ { printf "  \033[36m%-18s\033[0m %s\n", $$1, $$2 }' $(MAKEFILE_LIST)

## ─── Setup ────────────────────────────────────────────────────────────────

sync: ## Install/sync dependencies (uv)
	uv sync

## ─── Tests ────────────────────────────────────────────────────────────────

test: ## Run the test suite
	$(PYTEST)

test-verbose: ## Run tests with verbose output
	$(PYTEST) -v

## ─── Lint and format ──────────────────────────────────────────────────────

lint: ## Run ruff lint (no fixes)
	$(RUFF) check $(SRC_DIRS)

lint-fix: ## Run ruff lint with auto-fix
	$(RUFF) check --fix $(SRC_DIRS)

format: ## Run ruff formatter (rewrites in place)
	$(RUFF) format $(SRC_DIRS)

format-check: ## Verify formatting without rewriting
	$(RUFF) format --check $(SRC_DIRS)

## ─── Type check ───────────────────────────────────────────────────────────

typecheck: ## Run pyright
	$(PYRIGHT)

## ─── Schemas ──────────────────────────────────────────────────────────────

schemas: ## Regenerate JSON Schemas from the Pydantic source
	$(PYTHON) scripts/generate_schemas.py

schemas-check: schemas ## Fail if regenerating schemas produces a diff
	@if [ -n "$$(git status --porcelain $(SCHEMAS_DIR))" ]; then \
		echo "schemas/ drifted from the Pydantic source. Run 'make schemas' and commit."; \
		git status --porcelain $(SCHEMAS_DIR); \
		exit 1; \
	fi

## ─── CI bundle ────────────────────────────────────────────────────────────

ci: lint format-check typecheck test schemas-check ## All checks; what CI runs

## ─── Cleanup ──────────────────────────────────────────────────────────────

clean: ## Remove pytest/ruff/pyright caches
	rm -rf .pytest_cache .ruff_cache .pyright
	find . -type d -name __pycache__ -prune -exec rm -rf {} +

clean-output: ## Remove per-pipeline output artifacts (keeps the directory itself if .gitkeep'd)
	rm -rf $(OUTPUT_DIR)/*
