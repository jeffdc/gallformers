defmodule GallformersWeb.AboutHTML do
  use GallformersWeb, :html

  embed_templates "about_html/*"

  defp display_name(admin) do
    cond do
      admin.display_name && admin.display_name != "" -> admin.display_name
      admin.nickname && admin.nickname != "" -> admin.nickname
      true -> "Anonymous"
    end
  end
end
