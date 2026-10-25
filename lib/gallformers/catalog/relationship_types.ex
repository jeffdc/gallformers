defmodule Gallformers.Catalog.RelationshipTypes do
  @moduledoc """
  The fixed list of Relationship types (`8567` rule 8; meanings in
  `docs/domain/domain-model.md`, *Relationships*), matching the contract's
  `priv/import/vocab/relationships.schema.json`.

  Each type has a direction (`label`, read subject → object), the label read
  the other way (`inverse_label`), and its endpoint kinds:

    * `:taxon_to_gall` — an organism (taxon) → a Gall
    * `:gall_to_gall` — a Gall → a Gall
    * `:taxon_to_taxon_in_gall` — an organism → an organism, within a Gall
      (the Relationship's Gall context)

  Qualifiers are their own Facts about a Relationship; which fit which types,
  and their values, follow the contract (`PRODUCER_GUIDE.md`, *Qualifiers*).

  The list is a system list: it changes only with a migration, since the
  `relationship_facts` check constraints hold the same lists.
  """

  @type endpoints :: :taxon_to_gall | :gall_to_gall | :taxon_to_taxon_in_gall

  @type t :: %{
          name: String.t(),
          label: String.t(),
          inverse_label: String.t(),
          endpoints: endpoints(),
          qualifiers: [String.t()]
        }

  @types [
    {"inducer_of", "inducer of", "induced by", :taxon_to_gall, []},
    {"host_of", "host of", "induced on", :taxon_to_gall, []},
    {"symbiont_of", "symbiont of", "has symbiont", :taxon_to_gall, ["required_for_formation"]},
    {"inquiline_of", "inquiline of", "has inquiline", :taxon_to_gall, ["lethality"]},
    {"cecidophage_in", "cecidophage in", "has cecidophage", :taxon_to_gall, ["lethality"]},
    {"parasitoid_in", "parasitoid in", "has parasitoid", :taxon_to_gall, ["parasitism_mode"]},
    {"emerged_from", "emerged from", "has emerged", :taxon_to_gall, []},
    {"feeds_on", "feeds on", "fed on by", :taxon_to_gall, []},
    {"herbivore_of", "herbivore of", "has herbivore", :taxon_to_gall, []},
    {"successor_in", "successor in", "habitat for", :taxon_to_gall, []},
    {"modified_form_of", "modified form of", "has modified form", :gall_to_gall, []},
    {"alternate_generation_of", "alternate generation of", "alternate generation of",
     :gall_to_gall, []},
    {"parasitoid_of", "parasitoid of", "has parasitoid", :taxon_to_taxon_in_gall,
     ["parasitism_mode"]},
    {"vectored_by", "vectored by", "is vector for", :taxon_to_taxon_in_gall, []},
    {"predator_of", "predator of", "preyed on by", :taxon_to_taxon_in_gall, []}
  ]

  @all for {name, label, inverse, endpoints, qualifiers} <- @types,
           do: %{
             name: name,
             label: label,
             inverse_label: inverse,
             endpoints: endpoints,
             qualifiers: qualifiers
           }

  @by_name Map.new(@all, &{&1.name, &1})

  @qualifier_values %{
    "required_for_formation" => ["true"],
    "lethality" => ["lethal", "non-lethal"],
    "parasitism_mode" => ["idiobiont", "koinobiont", "solitary", "gregarious", "ecto", "endo"]
  }

  @doc "Every Relationship type, in the domain model's order."
  @spec all() :: [t()]
  def all, do: @all

  @doc "Every Relationship type's name."
  @spec names() :: [String.t()]
  def names, do: Enum.map(@all, & &1.name)

  @doc "The names of the Relationship types with these endpoint kinds."
  @spec names(endpoints()) :: [String.t()]
  def names(endpoints), do: for(%{endpoints: ^endpoints, name: name} <- @all, do: name)

  @doc "A Relationship type by name, or nil."
  @spec get(String.t()) :: t() | nil
  def get(name), do: Map.get(@by_name, name)

  @doc "The qualifiers that fit a Relationship type (none for an unknown type)."
  @spec qualifiers(String.t()) :: [String.t()]
  def qualifiers(name) do
    case get(name) do
      %{qualifiers: qualifiers} -> qualifiers
      nil -> []
    end
  end

  @doc "Every qualifier's name."
  @spec qualifier_names() :: [String.t()]
  def qualifier_names, do: Map.keys(@qualifier_values)

  @doc """
  A qualifier's allowed values, as stored (`required_for_formation`'s
  contract value `true` is stored as `"true"`). Empty for an unknown qualifier.
  """
  @spec qualifier_values(String.t()) :: [String.t()]
  def qualifier_values(qualifier), do: Map.get(@qualifier_values, qualifier, [])
end
