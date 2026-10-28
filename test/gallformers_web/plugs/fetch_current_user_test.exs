defmodule GallformersWeb.Plugs.FetchCurrentUserTest do
  @moduledoc """
  Tests for the FetchCurrentUser plug's dev auth bypass.
  """
  # The bypass is application config, shared by every test.
  use GallformersWeb.ConnCase, async: false

  alias Gallformers.Accounts
  alias Gallformers.Repo
  alias GallformersWeb.Plugs.FetchCurrentUser

  describe "dev auth bypass" do
    setup do
      Application.put_env(:gallformers, :dev_auth_bypass, true)
      on_exit(fn -> Application.delete_env(:gallformers, :dev_auth_bypass) end)
    end

    test "signs in the Dev Admin with a local profile, as a real login does", %{conn: conn} do
      conn =
        conn
        |> init_test_session(%{})
        |> FetchCurrentUser.call([])

      assert %{id: "dev|bypass"} = conn.assigns.current_user

      assert %Accounts.User{display_name: "Dev Admin"} =
               Accounts.get_user_by_auth0_id("dev|bypass")
    end

    test "gives a Dev Admin session from before its profile existed a profile", %{conn: conn} do
      signed_in =
        conn
        |> init_test_session(%{})
        |> FetchCurrentUser.call([])

      user = signed_in.assigns.current_user
      Repo.delete!(Accounts.get_user_by_auth0_id("dev|bypass"))

      conn
      |> init_test_session(%{current_user: user, db_display_name: "Dev Admin"})
      |> FetchCurrentUser.call([])

      assert %Accounts.User{} = Accounts.get_user_by_auth0_id("dev|bypass")
    end
  end
end
