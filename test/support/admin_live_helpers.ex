defmodule GallformersWeb.AdminLiveHelpers do
  @moduledoc """
  Signing in for tests of the admin screens on the new back-end (the
  `:admin` live session, matter a856): their on_mount hook needs an admin
  in the session and a local user to name as the actor.
  """

  import Phoenix.ConnTest, only: [init_test_session: 2]
  import Plug.Conn, only: [put_session: 3]

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Audit.Actor

  @doc """
  Signs `conn` in as an admin with a local user named `name`, and makes that
  user the test's actor (`Gallformers.DataCase.put_test_actor/1`): a test
  runs in one sandbox transaction, which records one actor, so the
  fixtures' writes and the screen's must name the same one. Call it before
  any audited write (before `setup :audit_test_metadata`). `roles` are the
  session user's (`["superadmin"]` for a superadmin). Returns the conn and
  the local user.
  """
  def log_in_admin(conn, name \\ "Ada Admin", roles \\ ["admin"]) do
    auth0_id = "auth0|admin-#{System.unique_integer([:positive])}"
    {:ok, user} = Accounts.create_user(%{auth0_id: auth0_id, display_name: name})
    :ok = Gallformers.DataCase.put_test_actor(Actor.user(user.id, name))

    session_user = %Auth0User{
      id: auth0_id,
      email: "admin@test.com",
      name: name,
      nickname: "admin",
      picture: nil,
      roles: roles
    }

    conn =
      conn
      |> init_test_session(%{})
      |> put_session(:current_user, session_user)
      |> put_session(:db_display_name, name)

    {conn, user}
  end
end
