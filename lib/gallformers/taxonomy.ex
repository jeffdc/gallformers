defmodule Gallformers.Taxonomy do
  @moduledoc """
  The Taxonomy context.

  Provides functions for working with taxonomic classifications.
  """

  alias Gallformers.Taxonomy.{Reclassification, Search, SpeciesLink, TaxonName, Tree}

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
  defdelegate get_family(id), to: Tree
  defdelegate get_genus_lineage(id), to: Tree
  defdelegate get_section_lineage(id), to: Tree
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
  defdelegate list_genera_for_select(filter \\ :all), to: Tree

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

  defdelegate find_taxonomy_by_name(name), to: Tree

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
  defdelegate resolve_taxonomy_for_species(taxonomy, family_ids), to: SpeciesLink
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

  defdelegate reclassify_species(species_id, params), to: Reclassification

  defdelegate reassign_species_taxonomy(species_id, new_genus_id, opts \\ []),
    to: Reclassification

  # =====================================================================
  # Delegated to Taxonomy.Search — Typeahead & Search Queries
  # =====================================================================

  defdelegate search_families(query, opts \\ []), to: Search
  defdelegate search_genera(query, family_id \\ nil, opts \\ []), to: Search
  defdelegate search_genera_and_sections(query, limit \\ 20, opts \\ []), to: Search
  defdelegate search_taxonomies(query, type \\ nil, limit \\ 50), to: Search
  defdelegate search_sections(query), to: Search

  # =====================================================================
  # Delegated to Taxonomy.Reclassification — Deletion
  # =====================================================================

  defdelegate get_deletion_impact(taxonomy), to: Reclassification
  defdelegate delete_taxonomy_cascade(taxonomy), to: Reclassification

  # =====================================================================
  # Delegated to Taxonomy.Tree — Cross-domain Queries
  # =====================================================================

  defdelegate list_gall_families_for_host(host_id), to: Tree
  defdelegate list_gall_families_for_host_genus(host_genus_id), to: Tree
  defdelegate list_sections_with_details(), to: Tree

  # =====================================================================
  # PubSub
  # =====================================================================

  @doc """
  Subscribes to taxonomy changes.
  """
  @spec subscribe() :: :ok | {:error, term()}
  def subscribe do
    Phoenix.PubSub.subscribe(Gallformers.PubSub, "taxonomy")
  end
end
