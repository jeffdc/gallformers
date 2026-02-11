defmodule GallformersWeb.Admin.ReclassifyHelpers do
  @moduledoc """
  Shared helpers for parent LiveViews that host the ReclassifyLive component.
  """

  alias Gallformers.Taxonomy.{Genus, Lineage}

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  @doc """
  Resolves a family selection from the genus disambiguation modal.

  Finds the selected family in `possible_families`, builds a resolved Lineage,
  and updates common assigns. Returns `{:ok, socket, selected}` on success so the
  caller can add form-specific assigns (e.g. sections for hosts), or
  `{:error, socket}` if the family wasn't found.
  """
  def apply_family_disambiguation(socket, family_id_str) do
    family_id = String.to_integer(family_id_str)
    possible_families = socket.assigns.possible_families
    selected = Enum.find(possible_families, &(&1.family.id == family_id))

    if selected do
      lineage = %Lineage{
        genus: %Genus{id: selected.genus_id, name: socket.assigns.taxonomy.genus.name},
        family: selected.family,
        section: selected.section
      }

      socket =
        socket
        |> assign(:taxonomy, lineage)
        |> assign(:selected_family_id, family_id)
        |> assign(:possible_families, [])
        |> assign(:show_genus_disambiguation, false)

      {:ok, socket, selected}
    else
      {:error, put_flash(socket, :error, "Family not found")}
    end
  end
end
