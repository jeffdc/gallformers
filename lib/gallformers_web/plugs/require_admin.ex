defmodule GallformersWeb.Plugs.RequireAdmin do
  @moduledoc """
  Plug that requires the user to be an admin.

  Redirects to the login page if the user is not authenticated.
  Shows a 403 forbidden page if the user is authenticated but not an admin.
  If the user has no display_name set, redirects to the profile page.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Gallformers.Accounts
  alias GallformersWeb.Plugs.AdminSessionHelper

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
        conn
        |> assign(:current_user, user)
        |> AdminSessionHelper.ensure_db_display_name(user)
    end
  end
end

defmodule GallformersWeb.Plugs.RequireSuperAdmin do
  @moduledoc """
  Plug that requires the user to be a superadmin.

  Redirects to the login page if the user is not authenticated.
  Shows a 403 forbidden page if the user is authenticated but not a superadmin.
  If the user has no display_name set, redirects to the profile page.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias Gallformers.Accounts
  alias GallformersWeb.Plugs.AdminSessionHelper

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
        conn
        |> assign(:current_user, user)
        |> AdminSessionHelper.ensure_db_display_name(user)
    end
  end
end

defmodule GallformersWeb.Plugs.AdminSessionHelper do
  @moduledoc false

  import Plug.Conn
  import Phoenix.Controller

  alias Gallformers.Accounts

  @exempt_paths ["/admin/profile", "/admin/refresh-session"]

  @doc """
  Ensures :db_display_name is in the session and assigns.

  If missing from the session, looks up the DB user and backfills
  the session (handles pre-existing sessions from before this feature).
  If the DB user also has no display_name, redirects to the profile page.
  """
  def ensure_db_display_name(conn, auth0_user) do
    case get_session(conn, :db_display_name) do
      name when name not in [nil, ""] ->
        assign(conn, :db_display_name, name)

      _missing ->
        backfill_from_db(conn, auth0_user)
    end
  end

  defp backfill_from_db(conn, auth0_user) do
    auth0_id = if is_map(auth0_user), do: Map.get(auth0_user, :id) || Map.get(auth0_user, "id")

    case auth0_id && Accounts.get_user_by_auth0_id(auth0_id) do
      %Accounts.User{display_name: name} when name not in [nil, ""] ->
        # Backfill session from DB — user had a display_name already
        conn
        |> put_session(:db_display_name, name)
        |> assign(:db_display_name, name)

      _ ->
        # No display_name in DB either — redirect to profile (unless already there)
        conn = assign(conn, :db_display_name, "Unknown")

        if conn.request_path in @exempt_paths do
          conn
        else
          conn
          |> put_flash(:info, "Please set your display name before continuing.")
          |> redirect(to: "/admin/profile")
          |> halt()
        end
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
