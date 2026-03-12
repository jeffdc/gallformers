# Exclude E2E tests from regular test runs by default.
# Run E2E tests with: GALLFORMERS_E2E=1 mix test --include e2e
#
ExUnit.start(exclude: [:e2e, :prod_data, :typst])
Ecto.Adapters.SQL.Sandbox.mode(Gallformers.Repo, :manual)

# Start Wallaby for E2E tests (it's configured with runtime: false in mix.exs)
if System.get_env("GALLFORMERS_E2E") == "1" do
  {:ok, _} = Application.ensure_all_started(:wallaby)
end
