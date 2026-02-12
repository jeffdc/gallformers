defmodule GallformersWeb.ProdDataE2ECase do
  @moduledoc """
  Case template for E2E browser tests that run against a copy of the production database.

  Combines ProdDataCase's real-data guard with E2ECase's Wallaby setup. Tests using
  this template exercise the full browser stack (LiveView, Phoenix, Ecto) against real
  production data. All writes use the Ecto sandbox so they roll back automatically.

  ## Auth

  Enables `dev_auth_bypass` so admin pages work without Auth0. The bypass injects a
  fake admin user into the session via the `FetchCurrentUser` plug.

  ## Usage

      defmodule GallformersWeb.ProdDataE2E.SomeTest do
        use GallformersWeb.ProdDataE2ECase

        @moduletag :prod_data

        test "admin page loads with real data", %{session: session} do
          session
          |> visit("/admin/galls")
          |> assert_has(css(".phx-connected"))
        end
      end

  Run with:

      make test-prod-data-e2e

  NOTE: Like ProdDataCase, async: true is NOT supported with SQLite.
  """

  use ExUnit.CaseTemplate

  import Ecto.Query

  @min_species_count 1000

  using do
    quote do
      use Wallaby.Feature

      alias Wallaby.Query

      # Only import non-conflicting functions from Query
      # Use Query.text/1 explicitly when needed to avoid conflicts with Wallaby.Browser.text/1
      import Wallaby.Query, only: [css: 1, css: 2, button: 1, link: 1, fillable_field: 1]

      @endpoint GallformersWeb.Endpoint
    end
  end

  setup_all _tags do
    # Verify we have real production data
    pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Gallformers.Repo, shared: true)

    count =
      Gallformers.Repo.one(from s in "species", select: count(s.id))

    Ecto.Adapters.SQL.Sandbox.stop_owner(pid)

    if count < @min_species_count do
      raise """
      Prod data E2E tests require a real database (found #{count} species, need >= #{@min_species_count}).

      Run `make test-prod-data-e2e` which copies priv/gallformers.sqlite to the test DB.
      """
    end

    :ok
  end

  setup tags do
    if tags[:async] do
      raise "async: true is not supported with SQLite. Use async: false (the default)."
    end

    # Enable auth bypass so admin pages work without Auth0
    Application.put_env(:gallformers, :dev_auth_bypass, true)

    # Set up database sandbox in shared mode (required for Wallaby —
    # the browser process needs to see the same DB state as the test process)
    :ok = Ecto.Adapters.SQL.Sandbox.checkout(Gallformers.Repo)
    Ecto.Adapters.SQL.Sandbox.mode(Gallformers.Repo, {:shared, self()})

    # Allow Wallaby's browser process to access the database
    metadata = Phoenix.Ecto.SQL.Sandbox.metadata_for(Gallformers.Repo, self())
    {:ok, session} = Wallaby.start_session(metadata: metadata)

    on_exit(fn ->
      Application.delete_env(:gallformers, :dev_auth_bypass)
    end)

    {:ok, session: session}
  end
end
