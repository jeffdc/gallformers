defmodule Gallformers.Taxonomy do
  @moduledoc """
  The Taxonomy context.

  Provides functions for working with taxonomic classifications.
  """

  import Ecto.Query
  alias Gallformers.Repo
  alias Gallformers.Taxonomy.{Reclassification, Search, SpeciesLink, TaxonName, Taxonomy, Tree}

  # =====================================================================
  # Delegated to Taxonomy.Tree — CRUD
  # =====================================================================

  defdelegate change_taxonomy(taxonomy, attrs \\ %{}), to: Tree
  defdelegate create_taxonomy(attrs \\ %{}), to: Tree
  defdelegate update_taxonomy(taxonomy, attrs), to: Tree
  defdelegate delete_taxonomy(taxonomy), to: Tree

  # =====================================================================
  # Delegated to Taxonomy.Tree — Lookups
  # =====================================================================

  defdelegate get_taxonomy(id), to: Tree
  defdelegate get_taxonomy!(id), to: Tree
  defdelegate get_taxonomy_by_name(name, type), to: Tree
  defdelegate get_genera_by_name(name), to: Tree
  defdelegate get_taxonomies_batch(ids), to: Tree
  defdelegate resolve_taxonomy_from_name(name), to: Tree

  # =====================================================================
  # Delegated to Taxonomy.Tree — Hierarchy
  # =====================================================================

  defdelegate get_parent(id), to: Tree
  defdelegate get_children(id), to: Tree
  defdelegate get_children_for_parents(ids), to: Tree
  defdelegate get_taxonomy_path(id), to: Tree

  # =====================================================================
  # Delegated to Taxonomy.Tree — Lists
  # =====================================================================

  defdelegate list_taxonomies(), to: Tree
  defdelegate list_taxonomies_by_type(type), to: Tree
  defdelegate list_taxonomies_with_parent(type \\ nil, opts \\ []), to: Tree
  defdelegate list_child_genera(family_id), to: Tree
  defdelegate list_child_sections(genus_id), to: Tree
  defdelegate list_sections_for_family_tree(family_id), to: Tree
  defdelegate list_sections_for_family(family_id), to: Tree
  defdelegate list_sections_for_genus(genus_id), to: Tree
  defdelegate list_families_for_select(filter \\ :all), to: Tree
  defdelegate list_genera_for_select(), to: Tree
  defdelegate list_parents_for_genus(), to: Tree

  # =====================================================================
  # Delegated to Taxonomy.Tree — Unknown/Placeholder Management
  # =====================================================================

  defdelegate get_unknown_placeholder(parent_id), to: Tree
  defdelegate find_or_create_unknown_genus(family_id), to: Tree
  defdelegate empty_unknown_genus_ids(), to: Tree

  # =====================================================================
  # Delegated to Taxonomy.Tree — Utility
  # =====================================================================

  defdelegate display_name(taxonomy), to: Tree
  defdelegate update_genus_parent(genus_id, new_parent_id), to: Tree
  defdelegate move_genera(genus_ids, old_family_id, new_family_id), to: Tree

  # =====================================================================
  # TaxonName delegates
  # =====================================================================

  @doc """
  Returns true if the given genus name represents a placeholder (Unknown) genus.
  """
  @spec placeholder_genus_name?(String.t() | nil) :: boolean()
  defdelegate placeholder_genus_name?(name), to: TaxonName, as: :unknown_genus?

  @doc """
  Extracts the epithet (everything after the genus portion) from a species name.
  Handles "Unknown (Family) epithet" and "Genus epithet" formats.
  """
  defdelegate extract_epithet(name), to: TaxonName, as: :epithet

  # =====================================================================
  # 1-arity get_taxonomy_by_name (stays — URL parameter lookup)
  # =====================================================================

  # The 1-arity version is also delegated but needs special handling since
  # defdelegate can't distinguish arities for same name. We delegate to the
  # 2-arg version in Tree won't work. Tree has both arities, so we delegate
  # the 1-arity explicitly.

  # Note: The 1-arity get_taxonomy_by_name is handled by Tree's 1-arity clause.
  # Elixir's defdelegate for 2-arity (name, type) covers calls with 2 args.
  # Calls with 1 arg go through the 2-arity defdelegate default? No — we need
  # an explicit function for 1-arity.
  def get_taxonomy_by_name(name) when is_binary(name) do
    Tree.get_taxonomy_by_name(name)
  end

  # =====================================================================
  # Delegated to Taxonomy.SpeciesLink — Species-Taxonomy Linkage
  # =====================================================================

  defdelegate extract_genus_from_name(name), to: SpeciesLink
  defdelegate link_species_to_taxonomy(species_id, taxonomy_id), to: SpeciesLink

  defdelegate link_species_taxonomy(species_id, taxonomy, genus_is_new, parent_id),
    to: SpeciesLink

  defdelegate create_genus_for_species(genus_name, family_id, species_id), to: SpeciesLink
  defdelegate update_species_genus(species_id, new_genus_id), to: SpeciesLink

  # =====================================================================
  # Delegated to Taxonomy.SpeciesLink — Taxonomy Resolution
  # =====================================================================

  defdelegate get_taxonomy_from_species_name(name), to: SpeciesLink
  defdelegate lookup_taxonomy_for_new_species(name), to: SpeciesLink
  defdelegate resolve_taxonomy_for_species(taxonomy, family_ids, opts \\ []), to: SpeciesLink
  defdelegate maybe_update_genus_section(genus_id, new, old, family_id), to: SpeciesLink
  defdelegate resolve_genus_id(genus, family), to: SpeciesLink

  # =====================================================================
  # Delegated to Taxonomy.SpeciesLink — Species-Taxonomy Queries
  # =====================================================================

  defdelegate get_taxonomy_for_species(species_id), to: SpeciesLink
  defdelegate get_taxonomy_for_species_batch(species_ids), to: SpeciesLink
  defdelegate get_species_ids_for_genus(genus_id), to: SpeciesLink
  defdelegate get_species_ids_for_genera(genus_ids), to: SpeciesLink
  defdelegate get_species_ids_for_family(family_id), to: SpeciesLink
  defdelegate get_species_ids_for_taxonomies(taxonomy_ids), to: SpeciesLink
  defdelegate get_species_for_section(section_id), to: SpeciesLink
  defdelegate count_species_for_taxonomies(taxonomy_ids), to: SpeciesLink
  defdelegate update_section_species(section_id, species_ids), to: SpeciesLink

  # =====================================================================
  # Delegated to Taxonomy.Reclassification
  # =====================================================================

  defdelegate reassign_species_taxonomy(species_id, new_genus_id, opts \\ []),
    to: Reclassification

  # =====================================================================
  # Delegated to Taxonomy.Search — Typeahead & Search Queries
  # =====================================================================

  defdelegate search_families(query, limit \\ 20), to: Search
  defdelegate search_genera(query, family_id \\ nil, limit \\ 20), to: Search
  defdelegate search_genera_and_sections(query, limit \\ 20, opts \\ []), to: Search
  defdelegate search_taxonomies(query, type \\ nil, limit \\ 50), to: Search
  defdelegate search_sections(query), to: Search

  # =====================================================================
  # Delegated to Taxonomy.Reclassification — Deletion
  # =====================================================================

  defdelegate get_deletion_impact(taxonomy), to: Reclassification
  defdelegate delete_taxonomy_cascade(taxonomy), to: Reclassification

  # =====================================================================
  # Gall-Host Taxonomy Queries (stays in Taxonomy context)
  # =====================================================================

  @doc """
  Lists families for galls that occur on a given host.
  """
  @spec list_gall_families_for_host(integer()) :: [map()]
  def list_gall_families_for_host(host_id) do
    from(f in Taxonomy,
      join: g in Taxonomy,
      on: g.parent_id == f.id,
      join: st in "species_taxonomy",
      on: st.taxonomy_id == g.id,
      join: s in Gallformers.Species.Species,
      on: st.species_id == s.id,
      join: h in Gallformers.GallHosts.GallHost,
      on: h.gall_species_id == s.id,
      where: s.taxoncode == "gall" and f.type == "family" and h.host_species_id == ^host_id,
      group_by: [f.id, f.name],
      order_by: f.name,
      select: %{
        id: f.id,
        name: f.name
      }
    )
    |> Repo.all()
  end

  @doc """
  Lists families for galls that occur on hosts in a given host genus/section.
  """
  @spec list_gall_families_for_host_genus(integer()) :: [map()]
  def list_gall_families_for_host_genus(host_genus_id) do
    from(f in Taxonomy,
      join: galler_genus in Taxonomy,
      on: galler_genus.parent_id == f.id,
      join: st in "species_taxonomy",
      on: st.taxonomy_id == galler_genus.id,
      join: s in Gallformers.Species.Species,
      on: st.species_id == s.id,
      join: h in Gallformers.GallHosts.GallHost,
      on: h.gall_species_id == s.id,
      join: host in Gallformers.Species.Species,
      on: h.host_species_id == host.id,
      join: host_tax in "species_taxonomy",
      on: host_tax.species_id == host.id,
      where:
        s.taxoncode == "gall" and f.type == "family" and
          host_tax.taxonomy_id == ^host_genus_id,
      group_by: [f.id, f.name],
      order_by: f.name,
      select: %{id: f.id, name: f.name}
    )
    |> Repo.all()
  end

  # =====================================================================
  # Sections Management (stays in Taxonomy context)
  # =====================================================================

  @doc """
  Lists all sections with their parent genus and species count.
  """
  @spec list_sections_with_details() :: [map()]
  def list_sections_with_details do
    from(s in Taxonomy,
      left_join: g in Taxonomy,
      on: s.parent_id == g.id,
      left_join: st in "species_taxonomy",
      on: st.taxonomy_id == s.id,
      where: s.type == "section",
      group_by: [s.id, s.name, s.description, g.id, g.name],
      order_by: [g.name, s.name],
      select: %{
        id: s.id,
        name: s.name,
        description: s.description,
        genus_id: g.id,
        genus_name: g.name,
        species_count: count(st.species_id)
      }
    )
    |> Repo.all()
  end

  # =====================================================================
  # PubSub (stays in Taxonomy context)
  # =====================================================================

  @doc """
  Subscribes to taxonomy changes.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Gallformers.PubSub, "taxonomy")
  end
end
