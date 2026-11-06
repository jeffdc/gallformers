defmodule GallformersWeb.AdminRedirectController do
  @moduledoc """
  Permanent redirects from the URLs of the deleted old-domain admin screens
  to the screens that replaced them (matter a856), and from the item-first
  review queue's to the Source-down review (`6611`), and from the
  vocabulary requests to the vocabulary page (`d213`). Old admin URLs with no
  sensible new screen have no route and are not found.

  Plant IDs are taxon IDs and Gall IDs are the old species IDs, so a
  species ID in an old URL finds its Gall or taxon.
  """
  use GallformersWeb, :controller

  alias Gallformers.{Catalog, Taxa}

  @doc "`/admin/hosts` and `/admin/section*` → the taxonomy admin."
  @spec taxonomy(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def taxonomy(conn, _params), do: moved(conn, ~p"/admin/taxonomy")

  @doc "`/admin/hosts/new` → adding a taxon (or a plant from WCVP)."
  @spec new_taxon(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def new_taxon(conn, _params), do: moved(conn, ~p"/admin/taxonomy/new")

  @doc "`/admin/hosts/:id` → the plant's taxon page."
  @spec host(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def host(conn, %{"id" => id}) do
    case Integer.parse(id) do
      {taxon_id, ""} -> moved(conn, ~p"/admin/taxonomy/#{taxon_id}")
      _ -> not_found(conn)
    end
  end

  @doc "`/admin/species-sources/*` → the Source editor."
  @spec sources(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def sources(conn, _params), do: moved(conn, ~p"/admin/sources")

  @doc "`/admin/galls` (the old Gall search) → Browse Galls."
  @spec galls(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def galls(conn, _params), do: moved(conn, ~p"/galls")

  @doc "`/admin/galls/:id` (the old admin Gall page) → the Gall page in Edit mode."
  @spec gall(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def gall(conn, %{"id" => id}) do
    case Integer.parse(id) do
      {gall_id, ""} -> moved(conn, edit_gall_path(gall_id))
      _ -> not_found(conn)
    end
  end

  @doc "`/admin/gallhost?id=` → the Gall page in Edit mode; without a Gall, Browse Galls."
  @spec gall_host(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def gall_host(conn, params) do
    case Integer.parse(params["id"] || "") do
      {gall_id, ""} -> moved(conn, edit_gall_path(gall_id))
      _ -> moved(conn, ~p"/galls")
    end
  end

  defp edit_gall_path(gall_id), do: "/gall/#{gall_id}?edit"

  @doc """
  `/admin/images?species_id=` → the images section of the Gall page or of
  the taxon page; not found when the ID is neither.
  """
  @spec images(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def images(conn, params) do
    with {id, ""} <- Integer.parse(params["species_id"] || ""),
         path when is_binary(path) <- images_path(id) do
      moved(conn, path)
    else
      _ -> not_found(conn)
    end
  end

  @doc """
  `/admin/queue` (the item-first review queue, `6611`) → the Sources to
  review; filtered to rename proposals (`?kind=gall_rename`), their page.
  """
  @spec queue(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def queue(conn, %{"kind" => "gall_rename"}), do: moved(conn, ~p"/admin/review/renames")
  def queue(conn, _params), do: moved(conn, ~p"/admin/review")

  @doc "`/admin/queue/packages/:id` → the package's review page."
  @spec queue_package(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def queue_package(conn, %{"id" => id}) do
    case Integer.parse(id) do
      {package_id, ""} -> moved(conn, ~p"/admin/review/packages/#{package_id}")
      _ -> not_found(conn)
    end
  end

  @doc "`/admin/vocab-requests` (6611's vocabulary backlog) → the vocabulary page (`d213`)."
  @spec vocab_requests(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def vocab_requests(conn, _params), do: moved(conn, ~p"/admin/vocabulary")

  defp images_path(id) do
    cond do
      Catalog.get_gall(id) -> edit_gall_path(id)
      Taxa.get_taxon(id) -> ~p"/admin/taxonomy/#{id}" <> "#images"
      true -> nil
    end
  end

  defp moved(conn, path) do
    conn
    |> put_status(:moved_permanently)
    |> redirect(to: path)
  end

  defp not_found(conn) do
    conn
    |> put_status(:not_found)
    |> put_view(GallformersWeb.ErrorHTML)
    |> render(:"404")
  end
end
