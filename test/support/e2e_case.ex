defmodule GallformersWeb.E2ECase do
  @moduledoc """
  Test case for E2E browser tests using Playwright.

  All E2E tests run against a production data copy and exercise the full
  browser stack (LiveView, Phoenix, Ecto) in a real browser via Playwright.
  Writes use the Ecto sandbox so they roll back automatically.

  ## Prerequisites

  Install Playwright browsers:

      make e2e-setup

  Load production data into the test database:

      make load-prod-data-test

  ## Running E2E Tests

      make e2e              # Run all E2E tests (loads prod data automatically)
      make e2e-admin        # Admin tests only
      make e2e-public       # Public pages only
      make e2e-headed       # Run with visible browser

  ## Writing E2E Tests

  All E2E tests must be tagged with `@moduletag :e2e` plus an area tag:

      defmodule GallformersWeb.E2E.SomeTest do
        use GallformersWeb.E2ECase

        @moduletag :e2e
        @moduletag :e2e_public

        test "page loads", %{conn: conn} do
          conn
          |> visit("/")
          |> assert_has("h1", text: "Welcome")
        end
      end

  Available area tags:
  - `:e2e_public` - Public browsing pages (home, about, glossary, etc.)
  - `:e2e_search` - Search and ID tool
  - `:e2e_browse` - Species, hosts, galls browsing
  - `:e2e_admin` - Admin dashboard and CRUD
  - `:e2e_auth` - Authentication flows
  """

  use ExUnit.CaseTemplate
  use Playwright.Test

  import Ecto.Query

  @min_species_count 1000

  using do
    quote do
      use Playwright.Test

      import Fluffy.PhoenixTest
    end
  end

  setup_all do
    # Verify production data is loaded
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Gallformers.Repo, shared: true)

    count =
      Gallformers.Repo.one(from s in "species", select: count(s.id))

    Ecto.Adapters.SQL.Sandbox.stop_owner(pid)

    if count < @min_species_count do
      raise """
      E2E tests require production data (found #{count} species, need >= #{@min_species_count}).

      Run `make e2e` which loads production data automatically,
      or `make load-prod-data-test` to load it manually.
      """
    end

    :ok
  end

  setup context do
    # Enable auth bypass so admin pages work without Auth0
    Application.put_env(:gallformers, :dev_auth_bypass, true)
    on_exit(fn -> Application.delete_env(:gallformers, :dev_auth_bypass) end)

    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Gallformers.Repo, shared: not context.async)
    on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)

    %{conn: Fluffy.PhoenixTest.start_session(:playwright)}
  end
end
