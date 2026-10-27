defmodule GallformersWeb.Live.UserAuthTest do
  @moduledoc """
  Tests for the role-checking on_mount hooks in `GallformersWeb.Live.UserAuth`.

  Plugs don't run on live navigation, so these hooks are what enforce the
  superadmin / operator roles when a role-restricted LiveView mounts.
  """
  use ExUnit.Case, async: true

  alias Gallformers.Accounts.Auth0User
  alias GallformersWeb.Live.UserAuth
  alias Phoenix.LiveView.Socket

  defp user(roles) do
    %Auth0User{
      id: "auth0|user-auth-test",
      email: "user@test.com",
      name: "Test User",
      nickname: "test",
      picture: nil,
      roles: roles
    }
  end

  defp session(user), do: %{"current_user" => user}

  # A mounting LiveView's socket already carries the flash.
  defp mount(hook, session) do
    UserAuth.on_mount(hook, %{}, session, %Socket{assigns: %{__changed__: %{}, flash: %{}}})
  end

  describe "on_mount(:require_superadmin, ...)" do
    test "continues for a superadmin" do
      assert {:cont, _socket} = mount(:require_superadmin, session(user(["superadmin"])))
    end

    test "continues for a superadmin whose session user is a plain map" do
      assert {:cont, _socket} = mount(:require_superadmin, session(%{roles: ["superadmin"]}))
    end

    test "halts an admin who is not a superadmin, sending them to the admin dashboard" do
      assert {:halt, socket} = mount(:require_superadmin, session(user(["admin"])))
      assert {:redirect, %{to: "/admin"}} = socket.redirected
      assert Phoenix.Flash.get(socket.assigns.flash, :error) =~ "permission"
    end

    test "halts an operator who is not a superadmin" do
      assert {:halt, _socket} = mount(:require_superadmin, session(user(["admin", "operator"])))
    end

    test "halts a signed-out visitor, sending them to log in" do
      assert {:halt, socket} = mount(:require_superadmin, %{})
      assert {:redirect, %{to: "/auth/auth0"}} = socket.redirected
    end
  end

  describe "on_mount(:require_operator, ...)" do
    test "continues for an operator" do
      assert {:cont, _socket} = mount(:require_operator, session(user(["operator"])))
    end

    test "halts an admin who is not an operator, sending them to the admin dashboard" do
      assert {:halt, socket} = mount(:require_operator, session(user(["admin"])))
      assert {:redirect, %{to: "/admin"}} = socket.redirected
      assert Phoenix.Flash.get(socket.assigns.flash, :error) =~ "permission"
    end

    test "halts a superadmin who is not an operator" do
      assert {:halt, _socket} = mount(:require_operator, session(user(["superadmin"])))
    end

    test "halts a signed-out visitor, sending them to log in" do
      assert {:halt, socket} = mount(:require_operator, %{"current_user" => nil})
      assert {:redirect, %{to: "/auth/auth0"}} = socket.redirected
    end
  end
end
