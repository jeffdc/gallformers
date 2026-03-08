defmodule GallformersWeb.KeysController do
  use GallformersWeb, :controller

  alias Gallformers.Keys

  def index(conn, _params) do
    keys = Keys.list_keys()

    conn
    |> assign(:page_title, "Identification Keys")
    |> assign(:page_description, "Dichotomous identification keys for gall-associated organisms.")
    |> assign(:page_url, "/keys")
    |> assign(:keys, keys)
    |> render(:index)
  end
end
