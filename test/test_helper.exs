# Exclude E2E tests from regular test runs by default.
# Run E2E tests with: make e2e
#
ExUnit.start(exclude: [:e2e, :prod_data, :typst])
Ecto.Adapters.SQL.Sandbox.mode(Gallformers.Repo, :manual)

# The private bucket's in-memory stand-in (config/test.exs).
:ok = Gallformers.Storage.PrivateStub.start()

# Start Playwright for E2E tests
if System.get_env("GALLFORMERS_E2E") == "1" do
  # Headed mode for debugging: E2E_HEADED=1 make e2e
  if System.get_env("E2E_HEADED") == "1" do
    Application.put_env(:phoenix_test_playwright, :headless, false)
  end

  {:ok, _} = PhoenixTest.Playwright.Supervisor.start_link()
  Application.put_env(:phoenix_test, :base_url, GallformersWeb.Endpoint.url())
end
