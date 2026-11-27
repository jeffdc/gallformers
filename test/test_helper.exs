# Exclude E2E tests from regular test runs by default.
# Run E2E tests with: make e2e
#
# assert_receive's ceiling, which LiveViewTest's render_async/1 also waits:
# ExUnit's default of 100ms is too thin for pages whose async load queries the
# database (5-40ms alone) while the whole suite runs. A ceiling, not a wait: a
# passing test returns as soon as its message arrives.
ExUnit.start(exclude: [:e2e, :prod_data, :typst], assert_receive_timeout: 1_000)
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
