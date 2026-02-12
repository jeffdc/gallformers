defmodule Gallformers.Taxonomy.Lineage do
  @moduledoc """
  The taxonomic placement of a species: Family → Genus → Section (optional).

  This is the "address" of a species in the taxonomy tree. Unlike the Taxonomy
  Ecto schema (which models a single tree node), a Lineage models the *path*
  from family down to genus, composed of proper domain types.

  Includes species_id and species_name because a lineage is always for a
  specific species (or a species being created). These fields are nil during
  creation before the species is persisted.

  Companion to TaxonName: TaxonName parses species name strings (bootstrapping).
  Lineage models where the species sits in the tree (structured data with IDs).
  """

  alias Gallformers.Taxonomy.{Family, Genus, Section, TaxonName}
  alias Gallformers.Taxonomy.Taxonomy, as: TaxonomySchema

  defstruct [:species_id, :species_name, :family, :genus, :section]

  @type t :: %__MODULE__{
          species_id: integer() | nil,
          species_name: String.t() | nil,
          family: Family.t() | nil,
          genus: Genus.t(),
          section: Section.t() | nil
        }

  @type family_candidate :: %{
          genus_id: integer(),
          section: Section.t() | nil,
          family: Family.t()
        }

  @type lookup_result ::
          {:ok, t()}
          | {:new_genus, t()}
          | {:ambiguous, String.t(), [family_candidate()]}

  # -------------------------------------------------------------------
  # Constructors
  # -------------------------------------------------------------------

  @doc """
  Build a Lineage from a Taxonomy genus record and its preloaded parent.

  The genus must have its `:parent` association preloaded (the parent is
  always a family, or nil for orphan genera).
  """
  @spec from_genus(TaxonomySchema.t()) :: t()
  def from_genus(%TaxonomySchema{type: "genus"} = genus) do
    family =
      case genus.parent do
        nil -> nil
        %TaxonomySchema{} = f -> %Family{id: f.id, name: f.name, description: f.description}
      end

    %__MODULE__{
      genus: %Genus{id: genus.id, name: genus.name, description: genus.description},
      family: family
    }
  end

  @doc """
  Build a Lineage from a Taxonomy section record and its parent genus
  (which must have its `:parent` association preloaded).

  Models the full path: Family → Genus → Section.
  """
  @spec from_section(TaxonomySchema.t(), TaxonomySchema.t()) :: t()
  def from_section(
        %TaxonomySchema{type: "section"} = section,
        %TaxonomySchema{type: "genus"} = genus
      ) do
    lineage = from_genus(genus)

    %{
      lineage
      | section: %Section{id: section.id, name: section.name, description: section.description}
    }
  end

  @doc """
  Build a Lineage for a new genus that doesn't exist in the DB yet.
  """
  @spec new_genus(String.t()) :: t()
  def new_genus(genus_name) do
    %__MODULE__{
      genus: %Genus{name: genus_name}
    }
  end

  @doc """
  Build a Lineage from the result maps returned by SpeciesLink queries.

  Used by `get_taxonomy_for_species` and similar query functions to convert
  their raw query results into a Lineage.
  """
  @spec from_query_result(map(), map() | nil) :: t()
  def from_query_result(genus_result, section_result \\ nil) do
    family =
      if genus_result[:family_id] do
        %Family{
          id: genus_result.family_id,
          name: genus_result.family,
          description: genus_result[:family_description]
        }
      end

    section =
      if section_result && section_result[:section_id] do
        %Section{
          id: section_result.section_id,
          name: section_result.section,
          description: section_result[:section_description]
        }
      end

    %__MODULE__{
      genus: %Genus{
        id: genus_result.genus_id,
        name: genus_result.genus,
        description: genus_result[:genus_description]
      },
      family: family,
      section: section
    }
  end

  # -------------------------------------------------------------------
  # Behavior
  # -------------------------------------------------------------------

  @doc "Is the genus resolved (has a DB id)? False for new genera during creation."
  @spec resolved?(t()) :: boolean()
  def resolved?(%__MODULE__{genus: %Genus{id: nil}}), do: false
  def resolved?(%__MODULE__{}), do: true

  @doc "Is the genus a placeholder 'Unknown (Family)' name?"
  @spec placeholder_genus?(t()) :: boolean()
  def placeholder_genus?(%__MODULE__{genus: %Genus{name: name}}),
    do: TaxonName.unknown_genus?(name)

  @doc "Does this lineage include a section?"
  @spec has_section?(t()) :: boolean()
  def has_section?(%__MODULE__{section: nil}), do: false
  def has_section?(%__MODULE__{}), do: true

  @doc "Parse the species_name into a TaxonName struct."
  @spec parsed_name(t()) :: TaxonName.t() | nil
  def parsed_name(%__MODULE__{species_name: nil}), do: nil
  def parsed_name(%__MODULE__{species_name: name}), do: TaxonName.parse(name)
end
