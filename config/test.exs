import Config

config :gallformers, env: :test

config :gallformers, Oban, testing: :inline

# Tiles URL for test — matches dev (local file, though tests don't render maps)
config :gallformers, tiles_url: "/data/boundaries.pmtiles"

# The old-domain admin screens stay on in test so their LiveView and e2e tests
# keep running until the screens are deleted (matter a856). Off in dev and prod
# (config.exs). Tests that need them off flip it with Application.put_env/3.
config :gallformers, legacy_admin_enabled: true

# Run async tasks synchronously to avoid sandbox connection issues
config :gallformers, async_tasks: false

# Configure your database
# Use a schema-only test database (no production data)
config :gallformers, Gallformers.Repo,
  database: "gallformers_test",
  username: System.get_env("PGUSER", System.get_env("USER")),
  password: System.get_env("PGPASSWORD"),
  hostname: System.get_env("PGHOST", "localhost"),
  # Explicit because ecto_sql defaults the port to 5432 before Postgrex reads PGPORT.
  port: String.to_integer(System.get_env("PGPORT", "5432")),
  # Every test holds one sandbox connection for its whole run, so the pool must
  # cover every test that can run at once: ExUnit's default max_cases is
  # schedulers_online * 2. A smaller pool makes tests queue for a connection,
  # and under load DBConnection drops queued checkouts ("connection not
  # available and request was dropped from queue").
  pool_size: System.schedulers_online() * 2,
  pool: Ecto.Adapters.SQL.Sandbox

# Use stub instead of real WCVP database for WCVP lookups in most tests
config :gallformers, wcvp_lookup: Gallformers.Wcvp.LookupStub

# No `pool: Ecto.Adapters.SQL.Sandbox` — WCVP is read-only reference data.
# Fixture data is loaded once by `make test-db` (via wcvp_test_setup.sql).
# Tests read concurrently without write isolation.
config :gallformers, Gallformers.Repo.WCVP,
  database: "wcvp_test",
  username: System.get_env("PGUSER", System.get_env("USER")),
  password: System.get_env("PGPASSWORD"),
  hostname: System.get_env("PGHOST", "localhost"),
  port: String.to_integer(System.get_env("PGPORT", "5432"))

# Server is disabled by default for fast unit tests.
# E2E tests enable the server via GALLFORMERS_E2E=1 environment variable (in runtime.exs).
config :gallformers, GallformersWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "QXMJq8FP0hqnpEVCf4NmW0l3LLZMBoncyOmBqm2OrxKFnFuPBa7iIlHN6+5sD8dE"

# PhoenixTest + Playwright E2E configuration (only used when GALLFORMERS_E2E=1)
#
# IMPORTANT: phoenix_test_playwright config quirks (hard-won knowledge):
#
# 1. Namespace: The library reads config from `:phoenix_test, :playwright` —
#    NOT from `:phoenix_test_playwright`. Using the wrong namespace silently
#    falls back to defaults (chromium).
#
# 2. browser_pools must be explicit: Setting `browser: :firefox` at the top
#    level is NOT enough. The browser pool gets its own defaults via
#    NimbleOptions schema, and the library's `replace_lazy` merge only runs
#    when `browser_pools` is already present in the config. If omitted,
#    NimbleOptions applies the schema default `[[id: :default_pool]]` AFTER
#    the merge attempt, so the pool never sees the top-level `browser` setting
#    and defaults to `:chromium`. You must set the browser in BOTH places.
#
# 3. Multi-browser: browser_pools supports multiple pools for cross-browser
#    testing (e.g. firefox, webkit, chromium). Each pool needs its own id
#    and browser setting.
config :phoenix_test, otp_app: :gallformers

# 4. timeout: the library default is 2s per action, and `visit` waits for the
#    page's `load` event. On production-sized data a Gall page loads many
#    remote images and map tiles, which can take longer than that.
config :phoenix_test, :playwright,
  browser: :firefox,
  browser_pools: [[id: :default_pool, browser: :firefox]],
  timeout: 10_000,
  screenshot: true,
  screenshot_dir: "test/screenshots"

# In test we don't send emails
config :gallformers, Gallformers.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Disable real S3 calls in tests - functions return mock/empty data instead
config :gallformers, s3_enabled: false

# The private bucket is an in-memory stub in tests (test/support/private_storage_stub.ex)
config :gallformers, :private_storage, adapter: Gallformers.Storage.PrivateStub

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
