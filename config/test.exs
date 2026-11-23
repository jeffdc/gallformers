import Config

config :gallformers, env: :test

config :gallformers, Oban, testing: :inline

# Tiles URL for test — matches dev (local file, though tests don't render maps)
config :gallformers, tiles_url: "/data/boundaries.pmtiles"

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
  pool_size: 5,
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

# Fluffy + Playwright E2E configuration (only used when GALLFORMERS_E2E=1)
config :fluffy, endpoint: GallformersWeb.Endpoint, ecto_repos: [Gallformers.Repo]

config :playwright, :test,
  browser_name: :firefox,
  # Headed mode for debugging: E2E_HEADED=1 make e2e
  headless: System.get_env("E2E_HEADED") != "1",
  screenshot: :on

# In test we don't send emails
config :gallformers, Gallformers.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

# Disable real S3 calls in tests - functions return mock/empty data instead
config :gallformers, s3_enabled: false

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
