defmodule Gallformers.Catalog do
  @moduledoc """
  The gall catalog (`9449` §4; rules in `8567`): Galls, the Fact kinds about
  them, the Trait vocabularies, generation groups and the Relationship-type
  list.

  This is the new gall system. It lives beside today's `Gallformers.Galls`
  (old `species`, `gall_traits`, `gallhost`, … tables) until the public
  pages are re-pointed; nothing here reads or writes the old gall tables.
  It reads `host_range` (by its `taxon_id`, filled by the data migration)
  and `place` for potential ranges. Today's record-level citations,
  carried over by the data migration until the backscan replaces them,
  are `Gallformers.Catalog.LegacyCitation`s (not Facts).

  Taxa are known only by ID and through `Gallformers.Taxa` (`8567` rule 3).
  The Catalog hears about taxon changes through
  `Gallformers.Catalog.TaxonListener`.

  ## Read models

  The potential range, Gall summaries and flags
  (`Gallformers.Catalog.ReadModels`) are computed on read from current
  Facts, `host_range` and `Gallformers.Taxa`. The plan (`9449` §4) has them
  rebuilt asynchronously; they are not materialized yet because on-read
  queries are simple and always fresh, and nothing reads them at volume
  until the public pages are re-pointed. When the ID tool or search needs
  them in bulk, materialize them (tables refreshed by an Oban worker on
  Fact and taxon changes — standing changes in `Gallformers.Facts`, events
  in the listener) behind these same functions.

  ## Writes

  Every write is audited (`Gallformers.Audit`) as the given actor, and can
  be nested inside an outer `Gallformers.Audit.transaction/3` with the same
  actor.
  """
  use Boundary,
    deps: [
      Gallformers.Audit,
      Gallformers.Facts,
      Gallformers.Places,
      Gallformers.Repo,
      Gallformers.Sources,
      Gallformers.Taxa
    ],
    exports: [
      Assert,
      Facts.AliasFact,
      Facts.DescriptionFact,
      Facts.OccurrenceFact,
      Facts.QualifierFact,
      Facts.RangeFact,
      Facts.RelationshipFact,
      Facts.TraitFact,
      Gall,
      LegacyCitation,
      ReadModels.GallSummary,
      RelationshipTypes,
      TaxonListener,
      Vocab.GenerationGroup,
      Vocab.GenerationGroupTaxon,
      Vocab.GenerationValue,
      Vocab.TraitTermMapping,
      Vocab.TraitValue
    ]

  import Ecto.Query

  alias Ecto.Changeset
  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog.Assert
  alias Gallformers.Catalog.Facts.AliasFact
  alias Gallformers.Catalog.Facts.DescriptionFact
  alias Gallformers.Catalog.Facts.OccurrenceFact
  alias Gallformers.Catalog.Facts.QualifierFact
  alias Gallformers.Catalog.Facts.RangeFact
  alias Gallformers.Catalog.Facts.RelationshipFact
  alias Gallformers.Catalog.Facts.TraitFact
  alias Gallformers.Catalog.Gall
  alias Gallformers.Catalog.LegacyCitation
  alias Gallformers.Catalog.ReadModels.Flags
  alias Gallformers.Catalog.ReadModels.GallSummary
  alias Gallformers.Catalog.ReadModels.PotentialRange
  alias Gallformers.Catalog.Vocab.GenerationGroup
  alias Gallformers.Catalog.Vocab.GenerationValue
  alias Gallformers.Catalog.Vocab.Loader
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Repo

  # -- vocabularies ------------------------------------------------------------

  @doc """
  Loads the Trait values, term mappings and generation groups
  (`Gallformers.Catalog.Vocab.Loader`). Idempotent; returns how many rows
  of each table were inserted or updated.
  """
  @spec load_vocab(Actor.t()) :: {:ok, Loader.counts()}
  def load_vocab(%Actor{} = actor), do: Loader.load(actor)

  @doc "Every Trait value, by trait then value."
  @spec list_trait_values() :: [TraitValue.t()]
  def list_trait_values, do: Repo.all(from(t in TraitValue, order_by: [t.trait, t.value]))

  @doc "A Trait value, or nil."
  @spec get_trait_value(String.t(), String.t()) :: TraitValue.t() | nil
  def get_trait_value(trait, value), do: Repo.get_by(TraitValue, trait: trait, value: value)

  @doc "The generation groups, by name, with their values in order."
  @spec list_generation_groups() :: [GenerationGroup.t()]
  def list_generation_groups do
    Repo.all(from(g in GenerationGroup, order_by: g.name, preload: :values))
  end

  @doc "A generation value, with its group, or nil."
  @spec get_generation_value(String.t()) :: GenerationValue.t() | nil
  def get_generation_value(value) do
    Repo.one(from(v in GenerationValue, where: v.value == ^value, preload: :group))
  end

  # -- Galls -------------------------------------------------------------------

  @doc """
  Creates a Gall (`Gallformers.Catalog.Gall`). `attrs` (atom keys): `:name`
  (required), `:name_override`, `:gallformers_code`,
  `:generation_value_id`, `:abundance_id`, `:datacomplete`, and `:id` for a
  migrated Gall keeping its species ID (otherwise the shared sequence gives
  one).
  """
  @spec create_gall(Actor.t(), map()) :: {:ok, Gall.t()} | {:error, Changeset.t()}
  def create_gall(%Actor{} = actor, attrs) when is_map(attrs) do
    Audit.transaction(actor, "catalog.create_gall", fn ->
      case %Gall{} |> Gall.create_changeset(attrs) |> Repo.insert() do
        {:ok, gall} -> gall
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  @doc "Gets a Gall by ID, or nil."
  @spec get_gall(integer()) :: Gall.t() | nil
  def get_gall(id), do: Repo.get(Gall, id)

  @doc "Gets a Gall by ID, raising if there is none."
  @spec get_gall!(integer()) :: Gall.t()
  def get_gall!(id), do: Repo.get!(Gall, id)

  # -- legacy citations --------------------------------------------------------

  @doc """
  Records today's record-level citations of Galls
  (`Gallformers.Catalog.LegacyCitation`), as the data migration carries
  them over: `rows` are maps of `:gall_id`, `:source_id`, `:description`,
  `:useasdefault`, `:externallink` and `:legacy_id`. Returns how many were
  inserted.
  """
  @spec insert_legacy_citations(Actor.t(), [map()]) :: {:ok, non_neg_integer()}
  def insert_legacy_citations(%Actor{} = actor, rows) when is_list(rows) do
    Audit.transaction(actor, "catalog.insert_legacy_citations", fn ->
      rows
      |> Enum.chunk_every(1_000)
      |> Enum.reduce(0, fn chunk, total ->
        {count, _} = Repo.insert_all(LegacyCitation, chunk)
        total + count
      end)
    end)
  end

  @doc """
  A Gall's legacy citations, the default description first, then by
  Source ID.
  """
  @spec list_legacy_citations(integer()) :: [LegacyCitation.t()]
  def list_legacy_citations(gall_id) when is_integer(gall_id) do
    Repo.all(
      from(c in LegacyCitation,
        where: c.gall_id == ^gall_id,
        order_by: [desc: c.useasdefault, asc: c.source_id]
      )
    )
  end

  # -- gall Facts --------------------------------------------------------------
  #
  # Each finds or creates a Fact by its kind's natural key, then records a
  # Source's stance with `attribution` (as `Gallformers.Facts.attribute/2`
  # takes it, without `:fact_id`). See `Gallformers.Catalog.Assert`.

  @doc """
  Records a Source's stance on a Relationship: `key` is `%{type, ...}` with
  the endpoints the type takes (`Gallformers.Catalog.Facts.RelationshipFact`):
  `subject_taxon_id` or `subject_gall_id`, `object_taxon_id` or
  `object_gall_id`, and `gall_context_id` for organism-to-organism types.
  A `host_of` subject must be a plant.
  """
  @spec assert_relationship(Actor.t(), map(), map()) ::
          {:ok, Assert.result()} | {:error, Changeset.t()}
  def assert_relationship(actor, key, attribution),
    do: Assert.assert(RelationshipFact, actor, key, attribution)

  @doc """
  Records a Source's stance on a qualifier of a Relationship Fact: `key` is
  `%{of_fact_id, qualifier, value}`.
  """
  @spec assert_qualifier(Actor.t(), map(), map()) ::
          {:ok, Assert.result()} | {:error, Changeset.t()}
  def assert_qualifier(actor, key, attribution),
    do: Assert.assert(QualifierFact, actor, key, attribution)

  @doc """
  Records a Source's stance on a Trait value: `key` is
  `%{gall_id, trait, value}` (names, e.g. `"color"`, `"red"`). `detachable`
  Facts compete in the slot `"gall:<id>:detachable"`. Give the Source's own
  word as `:value_as_written` in `attribution`.
  """
  @spec assert_trait(Actor.t(), map(), map()) ::
          {:ok, Assert.result()} | {:error, Changeset.t()}
  def assert_trait(actor, key, attribution),
    do: Assert.assert(TraitFact, actor, key, attribution)

  @doc """
  Records a Source's stance on a range adjustment: `key` is
  `%{gall_id, adjustment, place_id}`, `adjustment` `:exclude` or `:only`.
  The adjustments for one Gall and place compete in the slot
  `"gall:<id>:place:<place_id>"`: the newest statement wins. Nothing widens
  a Gall's range beyond its Hosts' ranges; a place where it occurs but no
  Host grows is a recorded occurrence (`assert_occurrence/3`).
  """
  @spec assert_range(Actor.t(), map(), map()) ::
          {:ok, Assert.result()} | {:error, Changeset.t()}
  def assert_range(actor, key, attribution),
    do: Assert.assert(RangeFact, actor, key, attribution)

  @doc """
  Records a Source's stance on a recorded occurrence: `key` is
  `%{gall_id, place_id}`. Give when and at what stage as
  `:when_as_written` and `:stage_as_written` in `attribution`.
  """
  @spec assert_occurrence(Actor.t(), map(), map()) ::
          {:ok, Assert.result()} | {:error, Changeset.t()}
  def assert_occurrence(actor, key, attribution),
    do: Assert.assert(OccurrenceFact, actor, key, attribution)

  @doc "Records a Source's stance on a common name: `key` is `%{gall_id, name}`."
  @spec assert_alias(Actor.t(), map(), map()) ::
          {:ok, Assert.result()} | {:error, Changeset.t()}
  def assert_alias(actor, key, attribution),
    do: Assert.assert(AliasFact, actor, key, attribution)

  @doc """
  Records a Source's description of a Gall: `key` is `%{gall_id}`; the
  description is the attribution's evidence (quotes).
  """
  @spec assert_description(Actor.t(), map(), map()) ::
          {:ok, Assert.result()} | {:error, Changeset.t()}
  def assert_description(actor, key, attribution),
    do: Assert.assert(DescriptionFact, actor, key, attribution)

  @fact_kinds %{
    relationship: RelationshipFact,
    qualifier: QualifierFact,
    trait: TraitFact,
    range: RangeFact,
    occurrence: OccurrenceFact,
    alias: AliasFact,
    description: DescriptionFact
  }

  @typedoc "A gall Fact kind, as the import contract names it."
  @type fact_kind ::
          :relationship | :qualifier | :trait | :range | :occurrence | :alias | :description

  @doc "The gall Fact kinds (`facts.kind` is `\"gall_\"` plus the kind)."
  @spec fact_kinds() :: [fact_kind()]
  def fact_kinds, do: Map.keys(@fact_kinds)

  @doc """
  Records a Source's stance on a gall Fact of `kind` (one of
  `fact_kinds/0`): the same as the `assert_*` function of that kind.
  """
  @spec assert_fact(fact_kind(), Actor.t(), map(), map()) ::
          {:ok, Assert.result()} | {:error, Changeset.t()}
  def assert_fact(kind, actor, key, attribution),
    do: Assert.assert(Map.fetch!(@fact_kinds, kind), actor, key, attribution)

  @doc """
  Finds the gall Fact of `kind` with natural key `key` without writing:
  `{:ok, fact_id}`, `{:ok, nil}` when there is none yet, or
  `{:error, changeset}` when the key is invalid (a Host that is not a plant,
  an unknown Trait value, ...).
  """
  @spec find_fact(fact_kind(), map()) :: {:ok, integer() | nil} | {:error, Changeset.t()}
  def find_fact(kind, key) do
    with {:ok, detail} <- Assert.find(Map.fetch!(@fact_kinds, kind), key) do
      {:ok, detail && detail.fact_id}
    end
  end

  @doc "Whether a Gall already shows `name` (names shown are unique)."
  @spec gall_name_taken?(String.t()) :: boolean()
  def gall_name_taken?(name) when is_binary(name) do
    Repo.exists?(
      from(g in Gall, where: fragment("COALESCE(?, ?)", g.name_override, g.name) == ^name)
    )
  end

  # -- read models -------------------------------------------------------------

  @doc """
  A Gall's potential range: `:everywhere` (no range data — missing data is
  not absence), or its leaf places by code
  (`Gallformers.Catalog.ReadModels.PotentialRange`).
  """
  @spec potential_range(integer()) :: PotentialRange.t()
  def potential_range(gall_id), do: PotentialRange.for_gall(gall_id)

  @doc """
  A Gall's current Inducer, Hosts and Traits
  (`Gallformers.Catalog.ReadModels.GallSummary`). Raises if there is no such
  Gall.
  """
  @spec gall_summary(integer()) :: GallSummary.t()
  def gall_summary(gall_id), do: GallSummary.for_gall(gall_id)

  @doc """
  The summaries of the Galls whose current Inducer is one of `taxon_ids`,
  by Gall ID (import matching, `Gallformers.Import.GallMatcher`).
  """
  @spec list_gall_summaries_by_inducer([integer()]) :: [GallSummary.t()]
  def list_gall_summaries_by_inducer(taxon_ids) when is_list(taxon_ids),
    do: GallSummary.for_related("inducer_of", taxon_ids)

  @doc "The summaries of the Galls with a current Host among `taxon_ids`, by Gall ID."
  @spec list_gall_summaries_by_host([integer()]) :: [GallSummary.t()]
  def list_gall_summaries_by_host(taxon_ids) when is_list(taxon_ids),
    do: GallSummary.for_related("host_of", taxon_ids)

  @doc """
  Alternate-generation mismatches across the catalog
  (`Gallformers.Catalog.ReadModels.Flags`).
  """
  @spec alternate_generation_flags() :: [Flags.flag()]
  def alternate_generation_flags, do: Flags.alternate_generations()

  @doc """
  Galls whose generation is outside their Inducer's generation groups
  (`Gallformers.Catalog.ReadModels.Flags`).
  """
  @spec generation_group_flags() :: [Flags.flag()]
  def generation_group_flags, do: Flags.generation_groups()

  @doc "The generation-group flags of the Galls among `gall_ids` (an import's Galls)."
  @spec generation_group_flags([integer()]) :: [Flags.flag()]
  def generation_group_flags(gall_ids) when is_list(gall_ids),
    do: Flags.generation_groups(gall_ids)
end
