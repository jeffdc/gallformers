# Gallformers - Makefile
#
# Phoenix/LiveView development commands

.PHONY: dev dev-cloudfront dev-lan test test-db test-prod-data test-prod-data-e2e test-prod-data-all download-db ci preflight help deps assets setup clean check-db build run-local-release dump-schema preview preview-stop preview-destroy wcvp-restore wcvp-check check-full check-bg

# Download production database for local dev
# Downloads full pg_dump from private S3 bucket and restores into local Postgres
# Requires AWS credentials (AWS_ACCESS_KEY_ID/SECRET_ACCESS_KEY in .env or ~/.aws)
DUMP_BUCKET ?= gallformers-full-backups

download-db:
	@echo "Finding latest backup..."
	$(eval LATEST_DATE := $(shell aws s3 ls s3://$(DUMP_BUCKET)/ | tail -1 | awk '{print $$2}' | tr -d '/'))
	@echo "Downloading backup from $(LATEST_DATE)..."
	aws s3 cp s3://$(DUMP_BUCKET)/$(LATEST_DATE)/gallformers.dump /tmp/gallformers.dump
	@echo "Restoring into gallformers_dev..."
	@psql -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'gallformers_dev' AND pid <> pg_backend_pid();" --quiet 2>/dev/null || true
	mix ecto.drop
	mix ecto.create
	pg_restore --no-owner --no-acl -d gallformers_dev /tmp/gallformers.dump || true
	@echo "Verifying..."
	@psql -d gallformers_dev -tAc "SELECT count(*) FROM species" | grep -qE '^[1-9]' || { \
		echo "ERROR: Restore failed — no species data found"; \
		exit 1; \
	}
	@echo "Database restored to gallformers_dev"

# =============================================================================
# Build Dependencies
# =============================================================================

# Install Elixir dependencies
deps:
	mix deps.get

# Install npm packages and build assets
assets/node_modules: assets/package.json
	cd assets && npm install
	@touch assets/node_modules

assets: assets/node_modules
	mix assets.setup
	mix assets.build

# Ensure dev database exists and has data
check-db:
	@psql -d gallformers_dev -tAc "SELECT count(*) FROM species" 2>/dev/null | grep -qE '^[1-9]' || { \
		echo ""; \
		echo "ERROR: Dev database not found or has no species data"; \
		echo "Set it up with:"; \
		echo "  make download-db"; \
		echo ""; \
		exit 1; \
	}

# Dump database schema (Postgres SQL format)
dump-schema:
	mix ecto.dump
	@echo "Schema dumped to priv/repo/structure.sql"

# Restore WCVP data from S3 into local wcvp database
wcvp-restore:
	@createdb wcvp 2>/dev/null || true
	mix gallformers.wcvp.restore

# Check that local wcvp database has data
wcvp-check:
	@psql -d wcvp -tAc "SELECT count(*) FROM wcvp_names" 2>/dev/null | grep -qE '^[1-9]' || { \
		echo ""; \
		echo "WARNING: WCVP database not found or has no data"; \
		echo "Set it up with:"; \
		echo "  make wcvp-restore"; \
		echo ""; \
	}

# Full setup (deps + assets + database)
setup: deps assets check-db wcvp-check

# =============================================================================
# Development
# =============================================================================

# Start development server (ensures deps and assets are ready)
# Loads .env if present for Auth0 and other local config
dev: setup
	@echo "Logs will be written to dev.log"
	@set -a && [ -f .env ] && . .env; set +a && PREVIEW_DEPLOY=true mix phx.server 2>&1 | tee dev.log 2>&1 | tee dev.log

# Start dev server using production CloudFront tiles (no local build needed)
dev-cloudfront: setup
	set -a && [ -f .env ] && . .env; set +a && TILES_URL=https://gallformers.org/tiles/boundaries.pmtiles PREVIEW_DEPLOY=true mix phx.server

# Start dev server on port 4002 for LAN access (dev already binds 0.0.0.0)
# Usage: make dev-lan              # default port 4002
#        make dev-lan LAN_PORT=4444 # custom port
LAN_PORT ?= 4002
dev-lan: setup
	@echo "Starting LAN dev server on port $(LAN_PORT)..."
	@echo "Access from other devices at http://$$(ipconfig getifaddr en0 2>/dev/null || hostname -I | awk '{print $$1}'):$(LAN_PORT)"
	set -a && [ -f .env ] && . .env; set +a && PHX_BIND=0.0.0.0 PORT=$(LAN_PORT) PREVIEW_DEPLOY=true mix phx.server

# =============================================================================
# Production Build
# =============================================================================

# Build production release locally
build: deps
	MIX_ENV=prod mix compile
	MIX_ENV=prod mix assets.deploy
	MIX_ENV=prod mix release --overwrite

# Run the locally built production release
# Requires SECRET_KEY_BASE and DATABASE_URL environment variables
run-local-release:
	@if [ -z "$$SECRET_KEY_BASE" ]; then \
		echo "Generating SECRET_KEY_BASE..."; \
		export SECRET_KEY_BASE=$$(mix phx.gen.secret); \
	fi; \
	DATABASE_URL=$${DATABASE_URL:-postgres://localhost/gallformers_dev} \
	PHX_HOST=localhost \
	PORT=4000 \
	_build/prod/rel/gallformers/bin/gallformers start

# =============================================================================
# Testing
# =============================================================================

# Set up fresh test database with migrations + seed data
test-db:
	@echo "Setting up test database..."
	@MIX_ENV=test mix ecto.drop --quiet 2>/dev/null || true
	@MIX_ENV=test mix ecto.create --quiet
	@MIX_ENV=test mix ecto.migrate --quiet
	@psql -d gallformers_test -f priv/repo/test_seeds.sql --quiet
	@createdb wcvp_test 2>/dev/null || true
	@psql -d wcvp_test -f priv/repo/wcvp_test_setup.sql --quiet
	@echo "Test database ready"

# Run JS unit tests (hooks, etc.)
test-js: assets/node_modules
	@cd assets && npm test

# Run tests (rebuilds test DB first, excludes E2E tests)
test: test-db test-js
	mix test

# Load production data into the test database from the daily pg_dump backup
# Requires AWS credentials (same as download-db)
load-prod-data-test:
	@echo "Loading production data into test database..."
	@if [ ! -f /tmp/gallformers.dump ]; then \
		echo "Downloading latest backup..."; \
		$(eval LATEST_DATE := $(shell aws s3 ls s3://$(DUMP_BUCKET)/ | tail -1 | awk '{print $$2}' | tr -d '/')) \
		aws s3 cp s3://$(DUMP_BUCKET)/$(LATEST_DATE)/gallformers.dump /tmp/gallformers.dump; \
	else \
		echo "Using cached /tmp/gallformers.dump"; \
	fi
	@MIX_ENV=test mix ecto.drop --quiet 2>/dev/null || true
	@MIX_ENV=test mix ecto.create --quiet
	@pg_restore --no-owner --no-acl -d gallformers_test /tmp/gallformers.dump || true
	@echo "Production data loaded into gallformers_test"

# Run context-level tests against production data (no browser)
# Validates data integrity and exercises write paths against real data
# All writes use Ecto sandbox (rolled back automatically)
# Requires AWS credentials for downloading the backup
test-prod-data: load-prod-data-test
	@echo "Running prod data context tests..."
	@mix test test/prod_data/invariants_test.exs test/prod_data/write_operations_test.exs --include prod_data; \
		status=$$?; \
		echo "Restoring test database..."; \
		$(MAKE) test-db; \
		exit $$status

# Run all prod data tests (context tests + E2E browser tests)
# E2E tests are now consolidated in test/e2e/ — use `make e2e` to run them separately
test-prod-data-all: load-prod-data-test
	@echo "Running prod data context tests..."
	@mix test test/prod_data/invariants_test.exs test/prod_data/write_operations_test.exs --include prod_data
	@echo "Running E2E browser tests..."
	@GALLFORMERS_E2E=1 mix test test/e2e --include e2e; \
		status=$$?; \
		echo "Restoring test database..."; \
		$(MAKE) test-db; \
		exit $$status

# Check for unexpected test exclusions (non-E2E tests with @tag :skip, etc.)
# Runs unit tests only — E2E tests require prod data and are excluded
test-check-exclusions:
	mix test.check_exclusions

# =============================================================================
# E2E Testing (Playwright)
# =============================================================================
# E2E tests run against a production data copy in a real Firefox browser.
# All tests are excluded from regular test runs. Use these targets to run them.
# See test/support/e2e_case.ex for documentation on writing E2E tests.

.PHONY: e2e e2e-public e2e-search e2e-browse e2e-admin e2e-auth e2e-setup e2e-headed e2e-slow e2e-changed

# Install Playwright browsers (required once, or after Playwright version bumps)
e2e-setup:
	@echo "Installing Playwright browsers..."
	@npx --prefix assets playwright install firefox --with-deps
	@echo ""
	@echo "Done. Run 'make e2e' to run E2E tests."

# Run all E2E tests (loads prod data, runs in two passes, restores test DB)
# Pass 1: main suite
# Pass 2: host admin reclassify in its own ExUnit invocation (heavy page
#          with range map — LiveView mount needs a clean process environment)
E2E_MAIN := test/e2e/public test/e2e/search test/e2e/browse test/e2e/auth \
	test/e2e/admin/admin_test.exs test/e2e/admin/reclassify_test.exs \
	test/e2e/admin/taxonomy_admin_test.exs
E2E_HOST := test/e2e/admin/reclassify_host_test.exs

e2e: load-prod-data-test
	@echo "Running E2E tests (pass 1: main suite)..."
	@GALLFORMERS_E2E=1 mix test $(E2E_MAIN) --include e2e
	@echo "Running E2E tests (pass 2: host admin)..."
	@GALLFORMERS_E2E=1 mix test $(E2E_HOST) --include e2e; \
		status=$$?; \
		echo "Restoring test database..."; \
		$(MAKE) test-db; \
		exit $$status

# Run E2E tests for public pages only
e2e-public: load-prod-data-test
	@echo "Running public pages E2E tests..."
	@GALLFORMERS_E2E=1 mix test test/e2e/public --include e2e; \
		status=$$?; \
		echo "Restoring test database..."; \
		$(MAKE) test-db; \
		exit $$status

# Run E2E tests for search functionality only
e2e-search: load-prod-data-test
	@echo "Running search E2E tests..."
	@GALLFORMERS_E2E=1 mix test test/e2e/search --include e2e; \
		status=$$?; \
		echo "Restoring test database..."; \
		$(MAKE) test-db; \
		exit $$status

# Run E2E tests for browse functionality only
e2e-browse: load-prod-data-test
	@echo "Running browse E2E tests..."
	@GALLFORMERS_E2E=1 mix test test/e2e/browse --include e2e; \
		status=$$?; \
		echo "Restoring test database..."; \
		$(MAKE) test-db; \
		exit $$status

# Run E2E tests for admin functionality only
e2e-admin: load-prod-data-test
	@echo "Running admin E2E tests..."
	@GALLFORMERS_E2E=1 mix test test/e2e/admin --include e2e; \
		status=$$?; \
		echo "Restoring test database..."; \
		$(MAKE) test-db; \
		exit $$status

# Run E2E tests for auth functionality only
e2e-auth: load-prod-data-test
	@echo "Running auth E2E tests..."
	@GALLFORMERS_E2E=1 mix test test/e2e/auth --include e2e; \
		status=$$?; \
		echo "Restoring test database..."; \
		$(MAKE) test-db; \
		exit $$status

# Run E2E tests with visible browser (for debugging)
e2e-headed: load-prod-data-test
	@echo "Running E2E tests with visible browser..."
	@GALLFORMERS_E2E=1 E2E_HEADED=1 mix test test/e2e --include e2e; \
		status=$$?; \
		echo "Restoring test database..."; \
		$(MAKE) test-db; \
		exit $$status

# Run E2E tests in slow motion (for debugging)
e2e-slow: load-prod-data-test
	@echo "Running E2E tests with visible browser (slow mode)..."
	@GALLFORMERS_E2E=1 E2E_HEADED=1 mix test test/e2e --include e2e --trace; \
		status=$$?; \
		echo "Restoring test database..."; \
		$(MAKE) test-db; \
		exit $$status

# Run only E2E tests affected by changed files (smart mode)
# Usage: make e2e-changed              # Compare against main
#        make e2e-changed REF=HEAD~3   # Compare against specific ref
e2e-changed: load-prod-data-test
	@./scripts/e2e-changed $(REF); \
		status=$$?; \
		echo "Restoring test database..."; \
		$(MAKE) test-db; \
		exit $$status

# =============================================================================

# Run CI checks (same as GitHub Actions)
ci: assets/node_modules test-db
	@echo "==> Running precommit checks (format, compile, credo, migrations, tests)..."
	mix precommit
	@echo ""
	@echo "==> Core CI checks passed! Running extended checks..."
	@echo ""
	@echo "==> Building assets (validates JS/CSS bundling)..."
	mix assets.deploy
	@echo "==> Running Dialyzer..."
	mix dialyzer
	@echo "==> All CI checks passed!"

# Full check suite (compile + credo + test) — use after major changes
check-full:
	mix compile --warnings-as-errors && mix credo --strict && mix test

# Background check — runs check-full and notifies on failure (macOS)
check-bg:
	@echo "Running full checks in background..."
	@($(MAKE) check-full 2>&1 && osascript -e 'display notification "All checks passed" with title "Gallformers"' || osascript -e 'display notification "Check failed — see terminal" with title "Gallformers"') &

# Run everything before pushing (local only, not for CI)
# Requires: Playwright browsers (make e2e-setup) and AWS credentials (for prod data tests)
preflight: ci
	@echo ""
	@echo "==> CI checks passed. Running prod data + E2E tests..."
	$(MAKE) test-prod-data-all
	@echo ""
	@echo "==> All preflight checks passed! Safe to push."

# =============================================================================
# Preview Deploys
# =============================================================================
# Deploy current branch to a disposable Fly.io preview instance.
# One-time setup: fly apps create gallformers-preview && fly secrets set ... (mirror prod secrets)

# Build and deploy preview from current local branch
preview:
	fly deploy --config fly.preview.toml

# Stop the preview machine (preserves app config and secrets)
preview-stop:
	fly machine stop --select --config fly.preview.toml

# Destroy the preview app entirely
preview-destroy:
	fly apps destroy gallformers-preview --yes

# Clean build artifacts
clean:
	rm -rf assets/node_modules
	rm -rf _build
	rm -rf deps
	rm -rf priv/static/assets

# Show help
help:
	@echo "Gallformers Makefile"
	@echo ""
	@echo "Development:"
	@echo "  make dev               Start Phoenix dev server (:4000) - auto-installs deps"
	@echo "  make dev-lan           Start dev server on :4002 for LAN access (LAN_PORT=N to override)"
	@echo "  make test              Run tests (fast, excludes E2E and prod_data)"
	@echo "  make test-prod-data    Run context tests against prod data copy (no browser)"
	@echo "  make test-prod-data-all  Run all prod data tests (context + E2E)"
	@echo "  make ci                Run all CI checks (format, compile, credo, test, dialyzer)"
	@echo "  make preflight         Run EVERYTHING before pushing (ci + prod data + E2E)"
	@echo ""
	@echo "E2E Testing (Playwright):"
	@echo "  make e2e-setup         Install Playwright browsers"
	@echo "  make e2e               Run all E2E tests (loads prod data automatically)"
	@echo "  make e2e-changed       Run E2E tests for changed files only (smart)"
	@echo "  make e2e-public        Run E2E tests for public pages only"
	@echo "  make e2e-search        Run E2E tests for search only"
	@echo "  make e2e-browse        Run E2E tests for browse only"
	@echo "  make e2e-admin         Run E2E tests for admin only"
	@echo "  make e2e-auth          Run E2E tests for auth only"
	@echo "  make e2e-headed        Run E2E tests with visible browser"
	@echo "  make e2e-slow          Run E2E tests in slow motion (debugging)"
	@echo ""
	@echo "Build:"
	@echo "  make setup             Full setup (deps + assets + db check)"
	@echo "  make deps              Install Elixir dependencies"
	@echo "  make assets            Install npm packages and build assets"
	@echo "  make build             Build production release locally"
	@echo "  make run-local-release Run the locally built production release"
	@echo "  make clean             Clean build artifacts (node_modules, _build, deps)"
	@echo ""
	@echo "Database:"
	@echo "  make download-db       Download pg_dump from S3 and restore to local Postgres"
	@echo "  make test-db           Rebuild test database (drop, create, migrate, seed)"
	@echo "  make wcvp-restore      Restore WCVP data from S3 into local wcvp database"
	@echo "  make wcvp-check        Check that local wcvp database has data"
	@echo ""
	@echo "Preview Deploys:"
	@echo "  make preview           Deploy current branch to preview (gallformers-preview.fly.dev)"
	@echo "  make preview-stop      Stop the preview machine (preserves config)"
	@echo "  make preview-destroy   Destroy the preview app entirely"
