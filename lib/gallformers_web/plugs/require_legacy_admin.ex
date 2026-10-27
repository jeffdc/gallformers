defmodule GallformersWeb.Plugs.RequireLegacyAdmin do
  @moduledoc """
  Plug for the old-domain admin routes (matter `a856`): when
  `GallformersWeb.LegacyAdmin.enabled?/0` is false, halts the request and
  renders the "being rebuilt" page in place (status 200) instead of mounting
  the old screen.

  Runs after `:admin` / `:superadmin`, so who may reach a gated URL, and the
  read-only check, are unchanged. Live navigation and socket connects skip
  plugs; `GallformersWeb.LegacyAdmin.on_mount/4` covers those.
  """

  import Plug.Conn
  import Phoenix.Controller

  alias GallformersWeb.LegacyAdmin

  @spec init(keyword()) :: keyword()
  def init(opts), do: opts

  @spec call(Plug.Conn.t(), keyword()) :: Plug.Conn.t()
  def call(conn, _opts) do
    if LegacyAdmin.enabled?() do
      conn
    else
      conn
      |> put_view(html: GallformersWeb.LegacyAdminHTML)
      |> render(:being_rebuilt, page_title: LegacyAdmin.notice())
      |> halt()
    end
  end
end
