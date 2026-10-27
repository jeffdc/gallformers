defmodule Gallformers.Catalog.GallName do
  @moduledoc """
  A Gall's name derived from its name parts (`8567` rule 9; `86e7` §1),
  used by every writer of `galls.name`: the data migration, deliberate edits
  (`Gallformers.Catalog.update_name_parts/3`), imports and rename proposals.

  ## Parts

    * `:inducer_taxon_id` — the Gall's current Inducer (its current
      `inducer_of` Fact), or nil.
    * `:generation_value_id` — its generation; the value's
      `name_qualifier` ("agamic", "sexgen", …) is written.
    * `:form_label` — free text ("australis", "bud", "leaf snap").
    * `:host_qualifier_taxon_id` — a Host taxon, written "on" its accepted
      name.
    * `:descriptor` — an undescribed Gall's descriptor
      (`q-havardii-cup-gall`).

  ## The name

  The base, from the Inducer:

    * species rank or below — its accepted name ("Neuroterus saltatorius");
      a descriptor is not used;
    * genus, subgenus or section — its genus's accepted name and the
      descriptor ("Belonocnema q-brandegeei-midrib-gall");
    * above genus — "Unknown", its family's accepted name in parentheses
      (the Inducer itself when it is a family), and the descriptor
      ("Unknown (Cynipidae) q-havardii-cup-gall");
    * no Inducer — "Unknown (Unknown)" and the descriptor.

  Then the qualifiers, each in parentheses, in this order: the form label,
  the generation, the Host qualifier — "Neuroterus quercicola (pacificus)
  (sexgen) (on Quercus douglasii)".

  A base needs a descriptor unless the Inducer is a species (or below):
  without one the result is `{:error, :no_base}`. An Inducer above family
  has no family to name (`{:error, :no_family}`), and a subgenus or section
  outside a genus no genus (`{:error, :no_genus}`). Such a Gall needs a name
  override.

  Text parts are trimmed; blank ones count as missing.
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Catalog.Vocab.GenerationValue
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.Rank

  @type parts :: %{
          optional(:inducer_taxon_id) => integer() | nil,
          optional(:generation_value_id) => integer() | nil,
          optional(:form_label) => String.t() | nil,
          optional(:host_qualifier_taxon_id) => integer() | nil,
          optional(:descriptor) => String.t() | nil
        }

  @typedoc "Why a name cannot be derived (`Gallformers.Catalog.derived_name/1` adds `:several_inducers`)."
  @type error :: :no_base | :no_family | :no_genus

  @genus_level [:genus, :subgenus, :section]

  @doc "The name `parts` give, or why they give none."
  @spec derive(parts()) :: {:ok, String.t()} | {:error, error()}
  def derive(parts) when is_map(parts) do
    with {:ok, base} <- base(parts[:inducer_taxon_id], blank_nil(parts[:descriptor])) do
      qualifiers =
        [
          blank_nil(parts[:form_label]),
          generation_qualifier(parts[:generation_value_id]),
          host_qualifier(parts[:host_qualifier_taxon_id])
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.map(&"(#{&1})")

      {:ok, Enum.join([base | qualifiers], " ")}
    end
  end

  @doc """
  The name Gall `gall`'s stored parts and its current Inducer give, or why
  they give none: `{:error, :several_inducers}` when current Sources
  disagree on its Inducer.
  """
  @spec for_gall(Gall.t()) :: {:ok, String.t()} | {:error, error() | :several_inducers}
  def for_gall(%Gall{} = gall) do
    case current_inducers(gall.id) do
      [_, _ | _] -> {:error, :several_inducers}
      inducers -> derive(parts(gall, List.first(inducers)))
    end
  end

  @doc "Gall `gall`'s stored name parts with Inducer `inducer_taxon_id`."
  @spec parts(Gall.t(), integer() | nil) :: parts()
  def parts(%Gall{} = gall, inducer_taxon_id) do
    %{
      inducer_taxon_id: inducer_taxon_id,
      generation_value_id: gall.generation_value_id,
      form_label: gall.form_label,
      host_qualifier_taxon_id: gall.host_qualifier_taxon_id,
      descriptor: gall.descriptor
    }
  end

  defp current_inducers(gall_id) do
    Repo.all(
      from(r in Current.relationships("inducer_of"),
        where: r.object_gall_id == ^gall_id,
        distinct: true,
        select: r.subject_taxon_id
      )
    )
  end

  # -- the base ----------------------------------------------------------------

  defp base(nil, nil), do: {:error, :no_base}
  defp base(nil, descriptor), do: {:ok, "Unknown (Unknown) #{descriptor}"}

  defp base(inducer_id, descriptor) do
    [_ | _] = lineage = Taxa.lineage(inducer_id)
    %{rank: rank, name: name} = List.last(lineage)

    cond do
      rank in Rank.species_and_below() -> {:ok, name}
      descriptor == nil -> {:error, :no_base}
      rank in @genus_level -> genus_base(lineage, descriptor)
      true -> family_base(lineage, descriptor)
    end
  end

  defp genus_base(lineage, descriptor) do
    case Enum.find(lineage, &(&1.rank == :genus)) do
      %{name: genus} -> {:ok, "#{genus} #{descriptor}"}
      nil -> {:error, :no_genus}
    end
  end

  defp family_base(lineage, descriptor) do
    case Enum.find(lineage, &(&1.rank == :family)) do
      %{name: family} -> {:ok, "Unknown (#{family}) #{descriptor}"}
      nil -> {:error, :no_family}
    end
  end

  # -- qualifiers --------------------------------------------------------------

  defp generation_qualifier(nil), do: nil
  defp generation_qualifier(id), do: blank_nil(Repo.get!(GenerationValue, id).name_qualifier)

  defp host_qualifier(nil), do: nil
  defp host_qualifier(taxon_id), do: "on #{Taxa.accepted_name(taxon_id)}"

  defp blank_nil(nil), do: nil

  defp blank_nil(text) when is_binary(text) do
    case String.trim(text) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
