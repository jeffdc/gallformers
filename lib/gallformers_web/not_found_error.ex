defmodule GallformersWeb.NotFoundError do
  @moduledoc """
  Raised when a page's subject doesn't exist (an unknown name on a rank
  page, an unknown old numeric ID). Phoenix answers it with the 404 page
  (`plug_status`); a live navigation to it reloads into that page.
  """
  defexception message: "Not found", plug_status: 404
end
