defmodule GallformersWeb.Plugs.RequireAdmin do
  @moduledoc """
  Plug that requires the user to be an admin.

  Redirects to the login page if the user is not authenticated.
  Shows a 403 forbidden page if the user is authenticated but not an admin.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Gallformers.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user = get_session(conn, :current_user)

    cond do
      is_nil(user) ->
        conn
        |> put_flash(:error, "You must log in to access this page.")
        |> redirect(to: "/auth/auth0")
        |> halt()

      not Accounts.admin?(user) ->
        conn
        |> put_status(:forbidden)
        |> put_view(GallformersWeb.ErrorHTML)
        |> render("403.html")
        |> halt()

      true ->
        assign(conn, :current_user, user)
    end
  end
end

defmodule GallformersWeb.Plugs.RequireSuperAdmin do
  @moduledoc """
  Plug that requires the user to be a superadmin.

  Redirects to the login page if the user is not authenticated.
  Shows a 403 forbidden page if the user is authenticated but not a superadmin.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Gallformers.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    user = get_session(conn, :current_user)

    cond do
      is_nil(user) ->
        conn
        |> put_flash(:error, "You must log in to access this page.")
        |> redirect(to: "/auth/auth0")
        |> halt()

      not Accounts.superadmin?(user) ->
        conn
        |> put_status(:forbidden)
        |> put_view(GallformersWeb.ErrorHTML)
        |> render("403.html")
        |> halt()

      true ->
        assign(conn, :current_user, user)
    end
  end
end

defmodule GallformersWeb.Plugs.FetchCurrentUser do
  @moduledoc """
  Plug that fetches the current user from the session and assigns it.

  This plug does NOT require authentication - it simply makes the current user
  available if one exists. Use RequireAdmin or RequireSuperAdmin to require auth.
  """

  import Plug.Conn

  def init(opts), do: opts

  def call(conn, _opts) do
    user = get_session(conn, :current_user)
    assign(conn, :current_user, user)
  end
end
