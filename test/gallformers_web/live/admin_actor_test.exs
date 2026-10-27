defmodule GallformersWeb.Live.AdminActorTest do
  @moduledoc """
  The `:require_admin_actor` on_mount hook (`GallformersWeb.Live.UserAuth`)
  that guards the new admin screens' `:admin` live session (matter a856,
  Task 1): it requires an admin and resolves the session user to the local
  user, assigning `:current_user` and the `Gallformers.Audit.Actor` their
  audited writes name.
  """
  use GallformersWeb.ConnCase, async: true

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Audit.Actor
  alias GallformersWeb.Live.UserAuth
  alias Phoenix.LiveView.Socket

  defp auth0_user(roles, auth0_id \\ "auth0|admin-actor-#{System.unique_integer([:positive])}") do
    %Auth0User{
      id: auth0_id,
      email: "admin@test.com",
      name: "Auth0 Name",
      nickname: "admin",
      picture: nil,
      roles: roles
    }
  end

  defp local_user!(%{id: auth0_id}, attrs \\ %{}) do
    {:ok, user} =
      Accounts.create_user(
        Map.merge(%{auth0_id: auth0_id, display_name: "Ada Admin", nickname: "ada"}, attrs)
      )

    user
  end

  # A mounting LiveView's socket already carries the flash.
  defp mount(session) do
    UserAuth.on_mount(
      :require_admin_actor,
      %{},
      session,
      %Socket{assigns: %{__changed__: %{}, flash: %{}}}
    )
  end

  test "an admin gets their session user and an actor for their local user" do
    session_user = auth0_user(["admin"])
    user = local_user!(session_user)

    assert {:cont, socket} = mount(%{"current_user" => session_user})
    assert socket.assigns.current_user == session_user
    assert socket.assigns.actor == Actor.user(user.id, "Ada Admin")
  end

  test "a superadmin is an admin too" do
    session_user = auth0_user(["superadmin"])
    user = local_user!(session_user)

    assert {:cont, socket} = mount(%{"current_user" => session_user})
    assert %Actor{type: :user, id: id} = socket.assigns.actor
    assert id == user.id
  end

  test "the actor is named by the nickname when the local user has no display name" do
    session_user = auth0_user(["admin"])
    local_user!(session_user, %{display_name: nil})

    assert {:cont, socket} = mount(%{"current_user" => session_user})
    assert socket.assigns.actor.name == "ada"
  end

  test "a session user deserialized as a plain map is resolved too" do
    session_user = auth0_user(["admin"])
    user = local_user!(session_user)

    assert {:cont, socket} = mount(%{"current_user" => Map.from_struct(session_user)})
    assert socket.assigns.actor.id == user.id
  end

  test "an admin with no local user is sent back to the admin dashboard" do
    assert {:halt, socket} = mount(%{"current_user" => auth0_user(["admin"])})
    assert {:redirect, %{to: "/admin"}} = socket.redirected
    assert Phoenix.Flash.get(socket.assigns.flash, :error) =~ "profile"
  end

  test "a signed-in user who is not an admin is halted" do
    session_user = auth0_user([])
    local_user!(session_user)

    assert {:halt, socket} = mount(%{"current_user" => session_user})
    assert {:redirect, %{to: "/admin"}} = socket.redirected
    assert Phoenix.Flash.get(socket.assigns.flash, :error) =~ "permission"
  end

  test "a signed-out visitor is sent to log in" do
    assert {:halt, socket} = mount(%{})
    assert {:redirect, %{to: "/auth/auth0"}} = socket.redirected
  end

  # Plugs don't run on live navigation; the on_mount hook is what checks the
  # admin when one of the session's screens mounts over the socket.
  describe "the :admin live session" do
    for path <- ["/admin/queue", "/admin/queue/packages/1"] do
      test "#{path} mounts through the :require_admin_actor hook" do
        %{phoenix_live_view: {_view, _action, _opts, live_session}} =
          Phoenix.Router.route_info(GallformersWeb.Router, "GET", unquote(path), "localhost")

        assert live_session.name == :admin
        hook_ids = Enum.map(live_session.extra.on_mount, & &1.id)
        assert {UserAuth, :require_admin_actor} in hook_ids
      end
    end
  end
end
