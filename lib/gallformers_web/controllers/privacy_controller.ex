defmodule GallformersWeb.PrivacyController do
  use GallformersWeb, :controller

  def show(conn, _params) do
    conn
    |> assign(:page_title, "Privacy")
    |> assign(
      :page_description,
      "Privacy Policy - Learn how Gallformers protects your privacy with our custom analytics system."
    )
    |> assign(:page_url, "/privacy")
    |> render(:show)
  end
end
