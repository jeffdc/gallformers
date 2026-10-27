defmodule GallformersWeb.API.TaxonomyController do
  @moduledoc """
  API controller for taxonomy endpoints, read from the new taxonomy
  (`Gallformers.Taxa`). Every taxonomy ID here is a taxon ID: the IDs
  changed with the new taxonomy (gall and host IDs did not).

  A taxon's `type` is its rank's old name: "family", "genus", "section", or
  "intermediate" for a rank between family and genus (subfamily, tribe,
  subtribe), whose `rank` is then given ("Subfamily"). Its `description`
  is its common names. A genus or section's `species` are the galls whose
  inducer is in it (`taxoncode` "gall", gall IDs) and the plants in it
  (`taxoncode` "plant", host IDs).
  """

  use GallformersWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias Gallformers.{Catalog, Taxa}
  alias Gallformers.Taxa.Rank
  alias GallformersWeb.Schemas

  @new_ids "Taxonomy IDs are taxon IDs of the new taxonomy (2026), not the taxonomy IDs " <>
             "earlier responses gave."

  tags(["Taxonomy"])

  operation(:genera,
    summary: "List genera",
    description: "Lists all genera with optional search and pagination. " <> @new_ids,
    parameters: [
      q: [
        in: :query,
        type: :string,
        description: "Search query: every word in the genus's name, a synonym or a common name"
      ],
      limit: [in: :query, type: :integer, description: "Maximum number of results"],
      offset: [in: :query, type: :integer, description: "Number of results to skip"]
    ],
    responses: [
      ok: {"List of genera", "application/json", Schemas.GeneraListResponse}
    ]
  )

  @doc """
  GET /api/v2/genera
  Lists all genera with optional search and pagination.
  """
  def genera(conn, params) do
    limit = parse_int(params["limit"])
    offset = parse_int(params["offset"]) || 0

    %{entries: genera, total: total} =
      Taxa.paginate_taxa(:genus, q: params["q"], limit: limit, offset: offset)

    json(conn, %{
      data: Enum.map(genera, &taxonomy_to_map/1),
      total: total,
      limit: limit,
      offset: offset
    })
  end

  operation(:families,
    summary: "List families",
    description:
      "Lists all families with their children (intermediate ranks and genera). " <> @new_ids,
    responses: [
      ok:
        {"List of families", "application/json",
         %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :object}}}
    ]
  )

  @doc """
  GET /api/v2/families
  Lists all families with their children.
  """
  def families(conn, _params) do
    families = Taxa.paginate_taxa(:family, []).entries
    children = families |> Enum.map(& &1.id) |> Taxa.children_by_parent()

    json(conn, Enum.map(families, &family_to_map(&1, Map.get(children, &1.id, []))))
  end

  operation(:family,
    summary: "Get a family",
    description: "Gets a family by taxon ID with its children. " <> @new_ids,
    parameters: [
      id: [in: :path, type: :integer, description: "Family (taxon) ID", required: true]
    ],
    responses: [
      ok: {"Family details", "application/json", %OpenApiSpex.Schema{type: :object}},
      bad_request: {"Invalid ID", "application/json", Schemas.Error},
      not_found: {"Family not found", "application/json", Schemas.Error}
    ]
  )

  @doc """
  GET /api/v2/families/:id
  Gets a family by ID with its children (genera and intermediates).
  """
  def family(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, family} <- fetch_taxon(id, &(&1 == :family)) do
      children = [id] |> Taxa.children_by_parent() |> Map.fetch!(id)
      json(conn, family_to_map(family, children))
    else
      {:error, :invalid_id} -> bad_request(conn, "Invalid family ID")
      {:error, :not_found} -> not_found(conn, "Family not found")
    end
  end

  operation(:genus,
    summary: "Get a genus",
    description:
      "Gets a genus by taxon ID with its family and species (the galls its species induce, " <>
        "and its plants). " <> @new_ids,
    parameters: [
      id: [in: :path, type: :integer, description: "Genus (taxon) ID", required: true]
    ],
    responses: [
      ok: {"Genus details", "application/json", %OpenApiSpex.Schema{type: :object}},
      bad_request: {"Invalid ID", "application/json", Schemas.Error},
      not_found: {"Genus not found", "application/json", Schemas.Error}
    ]
  )

  @doc """
  GET /api/v2/genera/:id
  Gets a genus by ID with its family and species.
  """
  def genus(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, genus} <- fetch_taxon(id, &(&1 == :genus)) do
      family = id |> Taxa.lineage() |> Enum.find(&(&1.rank == :family))

      json(conn, %{
        id: genus.id,
        name: genus.name,
        type: "genus",
        description: genus.description,
        family: family && %{id: family.taxon_id, name: family.name},
        species: species_under(id)
      })
    else
      {:error, :invalid_id} -> bad_request(conn, "Invalid genus ID")
      {:error, :not_found} -> not_found(conn, "Genus not found")
    end
  end

  operation(:section,
    summary: "Get a section",
    description: "Gets a section by taxon ID with its species. " <> @new_ids,
    parameters: [
      id: [in: :path, type: :integer, description: "Section (taxon) ID", required: true]
    ],
    responses: [
      ok: {"Section details", "application/json", %OpenApiSpex.Schema{type: :object}},
      bad_request: {"Invalid ID", "application/json", Schemas.Error},
      not_found: {"Section not found", "application/json", Schemas.Error}
    ]
  )

  @doc """
  GET /api/v2/sections/:id
  Gets a section by ID with its species.
  """
  def section(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, section} <- fetch_taxon(id, &(&1 == :section)) do
      json(conn, %{
        id: section.id,
        name: section.name,
        type: "section",
        description: section.description,
        species: species_under(id)
      })
    else
      {:error, :invalid_id} -> bad_request(conn, "Invalid section ID")
      {:error, :not_found} -> not_found(conn, "Section not found")
    end
  end

  operation(:intermediate,
    summary: "Get an intermediate",
    description:
      "Gets an intermediate rank (subfamily, tribe, subtribe) by taxon ID with its parent " <>
        "and children. " <> @new_ids,
    parameters: [
      id: [in: :path, type: :integer, description: "Intermediate (taxon) ID", required: true]
    ],
    responses: [
      ok: {"Intermediate details", "application/json", %OpenApiSpex.Schema{type: :object}},
      bad_request: {"Invalid ID", "application/json", Schemas.Error},
      not_found: {"Intermediate not found", "application/json", Schemas.Error}
    ]
  )

  @doc """
  GET /api/v2/intermediates/:id
  Gets an intermediate taxonomy node by ID with its parent and children.
  """
  def intermediate(conn, %{"id" => id}) do
    with {:ok, id} <- parse_id(id),
         {:ok, intermediate} <- fetch_taxon(id, &intermediate?/1) do
      parent = id |> Taxa.lineage() |> Enum.drop(-1) |> List.last()
      children = [id] |> Taxa.children_by_parent() |> Map.fetch!(id)

      json(conn, %{
        id: intermediate.id,
        name: intermediate.name,
        type: "intermediate",
        rank: rank_label(intermediate.rank),
        description: intermediate.description,
        parent: parent && %{id: parent.taxon_id, name: parent.name, type: type(parent.rank)},
        children: children_to_maps(children, id)
      })
    else
      {:error, :invalid_id} -> bad_request(conn, "Invalid intermediate ID")
      {:error, :not_found} -> not_found(conn, "Intermediate not found")
    end
  end

  operation(:sections,
    summary: "List sections",
    description:
      "Lists all sections with their genus and how many species (plants) they hold. " <> @new_ids,
    responses: [
      ok:
        {"List of sections", "application/json",
         %OpenApiSpex.Schema{type: :array, items: %OpenApiSpex.Schema{type: :object}}}
    ]
  )

  @doc """
  GET /api/v2/sections
  Lists all sections with parent genus info and species count.
  """
  def sections(conn, _params) do
    json(conn, Enum.map(Taxa.list_sections(), &Map.put(&1, :type, "section")))
  end

  # Private functions

  defp parse_id(id) do
    case parse_int(id) do
      nil -> {:error, :invalid_id}
      id -> {:ok, id}
    end
  end

  # The taxon `id` (`Taxa.taxon_summary/1`) when its rank passes `rank?`.
  defp fetch_taxon(id, rank?) do
    case Taxa.taxon_summary(id) do
      %{rank: rank} = taxon -> if rank?.(rank), do: {:ok, taxon}, else: {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  defp bad_request(conn, message) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: message})
  end

  defp not_found(conn, message) do
    conn
    |> put_status(:not_found)
    |> json(%{error: message})
  end

  defp taxonomy_to_map(taxon) do
    %{
      id: taxon.id,
      name: taxon.name,
      type: type(taxon.rank),
      description: taxon.description,
      parent_id: taxon.parent_id
    }
  end

  defp family_to_map(family, children) do
    %{
      id: family.id,
      name: family.name,
      type: "family",
      description: family.description,
      children: children_to_maps(children, family.id)
    }
  end

  # A taxon's children above species rank (species are listed as `species`).
  defp children_to_maps(children, parent_id) do
    for child <- children, child.rank not in Rank.species_and_below() do
      base = %{
        id: child.taxon_id,
        name: child.name,
        type: type(child.rank),
        description: describe(child.common_names),
        parent_id: parent_id
      }

      if intermediate?(child.rank), do: Map.put(base, :rank, rank_label(child.rank)), else: base
    end
  end

  # The galls whose inducer is in the taxon's subtree and the plants in it, by name.
  defp species_under(taxon_id) do
    galls =
      [taxon_id]
      |> Taxa.subtree_ids()
      |> Map.get(taxon_id, [])
      |> Catalog.list_galls_for_inducers()
      |> Enum.map(&species_entry(&1, "gall"))

    plants = taxon_id |> Taxa.list_plants_under() |> Enum.map(&species_entry(&1, "plant"))

    Enum.sort_by(galls ++ plants, &{&1.name, &1.id})
  end

  defp species_entry(entry, taxoncode),
    do: %{id: entry.id, name: entry.name, taxoncode: taxoncode, genus_placeholder: false}

  defp type(rank) when rank in [:family, :genus, :section], do: Atom.to_string(rank)

  defp type(rank) do
    if intermediate?(rank), do: "intermediate", else: Atom.to_string(rank)
  end

  # A rank between family and genus.
  defp intermediate?(rank), do: Rank.below?(rank, :family) and Rank.below?(:genus, rank)

  defp rank_label(rank), do: rank |> Atom.to_string() |> String.capitalize()

  defp describe([]), do: nil
  defp describe(names), do: Enum.join(names, ", ")

  defp parse_int(nil), do: nil

  defp parse_int(str) when is_binary(str) do
    case Integer.parse(str) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(int) when is_integer(int), do: int
end
