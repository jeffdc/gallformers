defmodule GallformersWeb.Admin.ReclassifyHelpers do
  @moduledoc """
  Shared helpers for parent LiveViews that host the ReclassifyLive component.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  @doc """
  Adapts a taxonomy map's family fields for ReclassifyLive's current_family assign.
  """
  def reclassify_family(nil), do: nil
  def reclassify_family(%{family_id: nil}), do: nil
  def reclassify_family(%{family_id: id, family: name}), do: %{id: id, name: name}
  def reclassify_family(_), do: nil

  @doc """
  Adapts a taxonomy map's genus fields for ReclassifyLive's current_genus assign.
  """
  def reclassify_genus(nil), do: nil
  def reclassify_genus(%{genus_id: nil}), do: nil
  def reclassify_genus(%{genus_id: id, genus: name}), do: %{id: id, name: name}
  def reclassify_genus(%{genus_id: id}), do: %{id: id}
  def reclassify_genus(_), do: nil

  @doc """
  Resolves a family selection from the genus disambiguation modal.

  Finds the selected family in `possible_families`, builds the resolved taxonomy map,
  and updates common assigns. Returns `{:ok, socket, selected}` on success so the
  caller can add form-specific assigns (e.g. sections for hosts), or
  `{:error, socket}` if the family wasn't found.
  """
  def apply_family_disambiguation(socket, family_id_str) do
    family_id = String.to_integer(family_id_str)
    possible_families = socket.assigns.possible_families
    selected = Enum.find(possible_families, &(&1.family_id == family_id))

    if selected do
      taxonomy = %{
        genus: socket.assigns.taxonomy.genus,
        genus_id: selected.genus_id,
        genus_is_new: false,
        section: selected.section,
        section_id: selected.section_id,
        family: selected.family,
        family_id: selected.family_id
      }

      socket =
        socket
        |> assign(:taxonomy, taxonomy)
        |> assign(:selected_family_id, family_id)
        |> assign(:possible_families, [])
        |> assign(:show_genus_disambiguation, false)

      {:ok, socket, selected}
    else
      {:error, put_flash(socket, :error, "Family not found")}
    end
  end
end
