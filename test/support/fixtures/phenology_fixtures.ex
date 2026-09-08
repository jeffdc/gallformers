defmodule Gallformers.PhenologyFixtures do
  @moduledoc false
  alias Gallformers.Phenology
  alias Gallformers.Repo
  alias Gallformers.Species.Species
  alias Gallformers.Taxonomy.Taxonomy

  def insert_gall(name \\ "Acraspis testica (agamic)") do
    {:ok, sp} =
      Repo.insert(%Species{name: name, taxoncode: "gall", datacomplete: false})

    sp
  end

  def insert_taxon(attrs) do
    {:ok, node} =
      Repo.insert(struct(Taxonomy, Map.put_new(attrs, :is_placeholder, false)))

    node
  end

  def link_taxon(species_id, taxonomy_id) do
    Repo.insert_all("species_taxonomy", [
      %{species_id: species_id, taxonomy_id: taxonomy_id}
    ])
  end

  def insert_gall_traits(species_id) do
    Repo.insert_all("gall_traits", [%{species_id: species_id}])
  end

  def insert_color(name) do
    {1, [%{id: id}]} = Repo.insert_all("color", [%{color: name}], returning: [:id])
    id
  end

  def link_color(species_id, color_id) do
    Repo.insert_all("gall_color", [%{species_id: species_id, color_id: color_id}])
  end

  def insert_place(name, type) do
    code = "zt-#{System.unique_integer([:positive])}"

    {1, [%{id: id}]} =
      Repo.insert_all("place", [%{name: name, type: type, code: code}], returning: [:id])

    id
  end

  def link_place_hierarchy(parent_id, child_id) do
    Repo.insert_all("place_hierarchy", [%{parent_id: parent_id, place_id: child_id}])
  end

  def link_gall_range(species_id, place_id) do
    Repo.insert_all("gall_range", [
      %{species_id: species_id, place_id: place_id, precision: "exact"}
    ])
  end

  def valid_attrs(species_id, overrides \\ %{}) do
    Map.merge(
      %{
        species_id: species_id,
        source_type: "literature",
        date: ~D[2024-06-15],
        doy: 167,
        latitude: 42.0,
        longitude: -83.0
      },
      overrides
    )
  end

  def insert_obs(species_id, attrs) do
    species_id
    |> valid_attrs(Map.put_new(attrs, :phenophase, "maturing"))
    |> Phenology.create_observation()
  end

  def insert_filter_field(table, column, name) do
    {1, [%{id: id}]} = Repo.insert_all(table, [%{column => name}], returning: [:id])
    id
  end

  def link_shape(species_id, shape_id) do
    Repo.insert_all("gall_shape", [%{species_id: species_id, shape_id: shape_id}])
  end
end
