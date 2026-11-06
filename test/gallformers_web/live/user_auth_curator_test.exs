defmodule GallformersWeb.Live.UserAuthCuratorTest do
  @moduledoc """
  `on_mount(:fetch_curator, ...)` (matter ec2c): on the public pages, an
  admin is a curator, with the `Gallformers.Audit.Actor` their tray's calls
  take (`:curator`); anyone else, or an admin with no local user, has none.
  It never halts: the public page shows either way.
  """
  use Gallformers.DataCase, async: true

  alias Gallformers.Accounts
  alias Gallformers.Accounts.Auth0User
  alias Gallformers.Audit.Actor
  alias GallformersWeb.Live.UserAuth
  alias Phoenix.LiveView.Socket

  defp session_user(auth0_id, roles) do
    %Auth0User{
      id: auth0_id,
      email: "c@test.com",
      name: "C",
      nickname: "c",
      picture: nil,
      roles: roles
    }
  end

  defp mount(session) do
    UserAuth.on_mount(:fetch_curator, %{}, session, %Socket{
      assigns: %{__changed__: %{}, flash: %{}}
    })
  end

  test "an admin with a local user: their Actor" do
    {:ok, user} =
      Accounts.create_user(%{auth0_id: "auth0|curator-1", display_name: "Ada Curator"})

    assert {:cont, socket} =
             mount(%{"current_user" => session_user("auth0|curator-1", ["admin"])})

    assert %Actor{type: :user, id: id, name: "Ada Curator"} = socket.assigns.curator
    assert id == user.id
  end

  test "a signed-in visitor who isn't an admin: none" do
    {:ok, _} = Accounts.create_user(%{auth0_id: "auth0|visitor-1", display_name: "Bo"})

    assert {:cont, socket} = mount(%{"current_user" => session_user("auth0|visitor-1", [])})
    assert socket.assigns.curator == nil
  end

  test "signed out, or an admin with no local user: none" do
    assert {:cont, socket} = mount(%{})
    assert socket.assigns.curator == nil

    assert {:cont, socket} =
             mount(%{"current_user" => session_user("auth0|no-such-user", ["admin"])})

    assert socket.assigns.curator == nil
  end
end
