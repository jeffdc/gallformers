# Exclude E2E tests from regular test runs by default.
# Run E2E tests with: make e2e
#
ExUnit.start(exclude: [:e2e, :prod_data, :typst])
Ecto.Adapters.SQL.Sandbox.mode(Gallformers.Repo, :manual)
