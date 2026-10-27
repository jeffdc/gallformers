defmodule GallformersWeb.E2ECase do
  @moduledoc """
  Test case for E2E browser tests using Playwright.

  All E2E tests run against a converted production data copy (old tables
  plus the new back-end the public pages read) and exercise the full
  browser stack (LiveView, Phoenix, Ecto) in a real browser via Playwright.
  Writes use the Ecto sandbox so they roll back automatically.

  ## Prerequisites

  Install Playwright browsers:

      make e2e-setup

  Load converted production data into the test database:

      make load-prod-data-test                              # download + convert
      make load-prod-data-test PROD_DATA_DB=gallformers_taxogall  # clone a converted copy

  Every `make e2e*` target takes the same `PROD_DATA_DB`.

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

  @min_gall_count 1000

  using do
    quote do
      import PhoenixTest

      import PhoenixTest.Playwright,
        only: [
          click: 2,
          click: 3,
          click: 4,
          click_button: 4,
          click_link: 4,
          evaluate: 2,
          evaluate: 3,
          evaluate: 4,
          type: 3,
          type: 4,
          press: 3,
          press: 4,
          screenshot: 2,
          screenshot: 3,
          step: 3,
          visit: 3,
          with_dialog: 3
        ]
    end
  end

  setup_all context do
    # Verify converted production data is loaded
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Gallformers.Repo, shared: true)
    count = Gallformers.Catalog.count_galls()
    Ecto.Adapters.SQL.Sandbox.stop_owner(pid)

    if count < @min_gall_count do
      raise """
      E2E tests require converted production data (found #{count} Galls, need >= #{@min_gall_count}).

      Run `make e2e` which loads production data automatically,
      or `make load-prod-data-test` to load it manually
      (`PROD_DATA_DB=gallformers_taxogall` clones an already converted copy).
      """
    end

    # Launch browser via Playwright
    PhoenixTest.Playwright.Case.do_setup_all(context)
  end

  setup context do
    # Enable auth bypass so admin pages work without Auth0
    Application.put_env(:gallformers, :dev_auth_bypass, true)
    on_exit(fn -> Application.delete_env(:gallformers, :dev_auth_bypass) end)

    # Create Playwright session (handles Ecto sandbox internally)
    PhoenixTest.Playwright.Case.do_setup(context)
  end
end
