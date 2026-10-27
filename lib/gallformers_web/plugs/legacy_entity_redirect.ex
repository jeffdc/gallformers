defmodule GallformersWeb.Plugs.LegacyEntityRedirect do
  @moduledoc """
  301-redirects old entity URLs whose record became no page in the new
  back-end (`803b` §4):

    * `/gall/:id` of an old gall row excluded as a non-gall
      (`Gallformers.Catalog.non_gall?/1`) → the gall-lookalikes Article.
    * `/host/:id` of an old genus placeholder plant ("Quercus spp"), which
      became no taxon → its genus page, through the crosswalk
      (`Gallformers.Taxa.get_by_legacy_id/2`, kind `:genus_placeholder`).

  A plug, not the LiveViews, so the redirect is permanent (a LiveView's
  redirect is a 302). Every other request passes through.
  """
  import Plug.Conn

  alias Gallformers.Catalog
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Taxon
  alias GallformersWeb.TaxonomyURL

  @lookalikes "/articles/gall-lookalikes"
  # IDs are bigints; a larger number is no ID (and would not encode).
  @max_id 9_223_372_036_854_775_807

  def init(opts), do: opts

  def call(%Plug.Conn{path_info: [kind, id_str]} = conn, _opts) when kind in ["gall", "host"] do
    case Integer.parse(id_str) do
      {id, ""} when id in 1..@max_id//1 -> kind |> target(id) |> redirect(conn)
      _ -> conn
    end
  end

  def call(conn, _opts), do: conn

  defp target("gall", id), do: if(Catalog.non_gall?(id), do: @lookalikes)

  defp target("host", id) do
    with %Taxon{} = genus <- Taxa.get_by_legacy_id(:genus_placeholder, id) do
      TaxonomyURL.public_path(%{rank: genus.rank, name: Taxa.accepted_name(genus)})
    end
  end

  defp redirect(nil, conn), do: conn

  defp redirect(path, conn) do
    conn
    |> put_resp_header("location", path)
    |> send_resp(:moved_permanently, "")
    |> halt()
  end
end
