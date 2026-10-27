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

  The potential range, Gall summaries, pages and flags
  (`Gallformers.Catalog.ReadModels`) are computed on read from current
  Facts, `host_range` and `Gallformers.Taxa`. What the ID tool and search
  read in bulk is stored: `gall_index`
  (`Gallformers.Catalog.ReadModels.GallIndex`), one row per Gall computed
  from those read models, refreshed by an Oban job when a Gall's Facts
  change standing (`Gallformers.Catalog.FactListener`, through
  `Gallformers.Facts.Events`) or its taxa move or are renamed
  (`Gallformers.Catalog.TaxonListener`).

  ## Writes

  Every write is audited (`Gallformers.Audit`) as the given actor, and can
  be nested inside an outer `Gallformers.Audit.transaction/3` with the same
  actor.
  """
  use Boundary,
    deps: [
      Gallformers.Audit,
      Gallformers.Facts,
      Gallformers.Images,
      Gallformers.Places,
      Gallformers.Ranges,
      Gallformers.Repo,
      Gallformers.Sources,
      Gallformers.Taxa,
      Gallformers.TextMatch
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
      FactListener,
      Gall,
      GallName,
      LegacyCitation,
      LegacyTraitIds,
      ReadModels.GallPage,
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
  alias Gallformers.Catalog.GallName
  alias Gallformers.Catalog.GallRenames
  alias Gallformers.Catalog.Identify
  alias Gallformers.Catalog.LegacyCitation
  alias Gallformers.Catalog.LegacyTraitIds
  alias Gallformers.Catalog.NonGallRedirect
  alias Gallformers.Catalog.ReadModels.Browse
  alias Gallformers.Catalog.ReadModels.Current
  alias Gallformers.Catalog.ReadModels.Flags
  alias Gallformers.Catalog.ReadModels.GallIndex
  alias Gallformers.Catalog.ReadModels.GallPage
  alias Gallformers.Catalog.ReadModels.GallSummary
  alias Gallformers.Catalog.ReadModels.PotentialRange
  alias Gallformers.Catalog.Vocab.GenerationGroup
  alias Gallformers.Catalog.Vocab.GenerationValue
  alias Gallformers.Catalog.Vocab.Loader
  alias Gallformers.Catalog.Vocab.TraitValue
  alias Gallformers.Ranges.DisplayRange
  alias Gallformers.Repo
  alias Gallformers.Sources

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

  @doc """
  The Trait values the import contract's `traits.json` lists (what
  `load_vocab/1` stores), as `%{trait, value, definition}`: for matching
  old vocabulary by name where `trait_values` is not loaded.
  """
  @spec contract_trait_values() :: [map()]
  def contract_trait_values, do: Loader.contract_trait_values()

  @doc """
  Old ID-tool bookmarks' Trait IDs: each old vocabulary table and row ID's
  Trait value, read from `legacy_trait_ids.csv`
  (`Gallformers.Catalog.LegacyTraitIds`; the shipped file by default).
  """
  @spec legacy_trait_values(String.t()) :: {:ok, LegacyTraitIds.values()} | {:error, String.t()}
  def legacy_trait_values(path \\ LegacyTraitIds.default_path()), do: LegacyTraitIds.read(path)

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
  (required), `:name_override`, the name parts `:form_label`,
  `:descriptor` and `:host_qualifier_taxon_id` (a plant),
  `:gallformers_code`, `:generation_value_id`, `:abundance_id`,
  `:datacomplete`, `:default_source_id` (the Source the Gall page leads
  with), and `:id` for a migrated Gall keeping its species ID (otherwise the
  shared sequence gives one). The name shown must be unique, ignoring case.
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

  # -- Gall names (`Gallformers.Catalog.GallName`) -----------------------------

  @doc """
  The name Gall `gall_id`'s stored name parts and its current Inducer give
  (`Gallformers.Catalog.GallName.derive/1`), or why they give none
  (`{:error, :several_inducers}` when current Sources disagree on its
  Inducer). Raises if there is no such Gall.
  """
  @spec derived_name(integer()) ::
          {:ok, String.t()} | {:error, GallName.error() | :several_inducers}
  def derived_name(gall_id) when is_integer(gall_id),
    do: gall_id |> get_gall!() |> GallName.for_gall()

  @doc """
  A deliberate edit of Gall `gall`'s name (`86e7` §3, §5): a curator's or a
  Gallformers batch's, applied directly — it is the review. `attrs` (atom
  keys) may set `:form_label`, `:descriptor`, `:host_qualifier_taxon_id`
  (a plant) and `:name_override` (nil clears it); nothing else, never the
  Gallformers code.

  The derived `name` is recomputed from the parts and the Gall's current
  Inducer (`derived_name/1`), in one audited transaction. Parts that give no
  name are refused unless the Gall has an override (its stored name then
  stays). A name shown by another Gall, ignoring case, is refused
  (`{:error, changeset}`, error on `:name`); nothing changes. The ID tool's
  lookup table row is refreshed (it stores the name).
  """
  @spec update_name_parts(Actor.t(), Gall.t(), map()) ::
          {:ok, Gall.t()} | {:error, Changeset.t()}
  def update_name_parts(%Actor{} = actor, %Gall{id: id}, attrs) when is_map(attrs) do
    Audit.transaction(actor, "catalog.update_name_parts", fn ->
      gall = Repo.one!(from(g in Gall, where: g.id == ^id, lock: "FOR UPDATE"))
      changeset = gall |> Gall.name_parts_changeset(attrs) |> put_derived_name()

      case Repo.update(changeset) do
        {:ok, updated} ->
          :ok = GallIndex.enqueue_refresh([updated.id])
          updated

        {:error, changeset} ->
          Repo.rollback(changeset)
      end
    end)
  end

  defp put_derived_name(%Changeset{valid?: false} = changeset), do: changeset

  defp put_derived_name(changeset) do
    case changeset |> Changeset.apply_changes() |> GallName.for_gall() do
      {:ok, name} ->
        Changeset.put_change(changeset, :name, name)

      {:error, reason} ->
        if Changeset.get_field(changeset, :name_override),
          do: changeset,
          else:
            Changeset.add_error(
              changeset,
              :name,
              "cannot be derived from the name parts (#{reason}); give a name override",
              reason: reason
            )
    end
  end

  @doc """
  The Galls without a name override whose derived name a taxonomy change
  (a `Gallformers.Taxa.Event`) may change, each as `%{gall_id, from, to,
  collision}`: its stored name, the name its parts give now (changed or
  not), and whether that is another Gall's name shown, ignoring case
  (`Gallformers.Catalog.GallRenames`). For rename proposals (`86e7` §3).
  """
  @spec gall_name_changes(Gallformers.Taxa.Event.t()) :: [GallRenames.change()]
  defdelegate gall_name_changes(event), to: GallRenames, as: :name_changes

  @doc """
  Applies an accepted rename proposal to Gall `gall_id`
  (`Gallformers.Catalog.GallRenames.accept/2`): the name its parts give now,
  with the name shown before kept as a `former_label` alias of the
  Gallformers Source. Never touches the Gallformers code.
  """
  @spec accept_gall_rename(Actor.t(), integer()) ::
          {:ok, %{gall: Gall.t(), from: String.t(), to: String.t()}}
          | {:error, GallRenames.accept_error()}
  defdelegate accept_gall_rename(actor, gall_id), to: GallRenames, as: :accept

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

  # -- old URLs (`Gallformers.Catalog.NonGallRedirect`) -------------------------

  @doc "Records the old gall IDs excluded as non-galls (maps of `:species_id`, `:name`)."
  @spec insert_non_gall_redirects(Actor.t(), [map()]) ::
          {:ok, non_neg_integer()} | {:error, term()}
  defdelegate insert_non_gall_redirects(actor, rows), to: NonGallRedirect, as: :insert_all

  @doc "Whether `id` is an old gall ID excluded as a non-gall (its URL goes to the lookalikes Article)."
  @spec non_gall?(integer()) :: boolean()
  defdelegate non_gall?(id), to: NonGallRedirect

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

  @doc """
  Records a Source's stance on a gall alias: `key` is `%{gall_id, name}`
  (the natural key) and optionally `:kind` — `:common_name` (the default
  for a new alias), `:former_label` or `:code`. A kind given sets it on an
  alias already held; none leaves the held one's kind.
  """
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

  @doc "Whether a Gall already shows `name`, ignoring case (names shown are unique)."
  @spec gall_name_taken?(String.t()) :: boolean()
  def gall_name_taken?(name) when is_binary(name) do
    Repo.exists?(
      from(g in Gall,
        where:
          fragment("lower(COALESCE(?, ?))", g.name_override, g.name) ==
            fragment("lower(?)", ^String.trim(name))
      )
    )
  end

  @doc "Whether a Gall already has Gallformers code `code` (codes are unique)."
  @spec gallformers_code_taken?(String.t()) :: boolean()
  def gallformers_code_taken?(code) when is_binary(code),
    do: Repo.exists?(from(g in Gall, where: g.gallformers_code == ^code))

  # -- read models -------------------------------------------------------------

  @doc """
  A Gall's potential range: `:everywhere` (no range data — missing data is
  not absence), or its leaf places by code
  (`Gallformers.Catalog.ReadModels.PotentialRange`).
  """
  @spec potential_range(integer()) :: PotentialRange.t()
  def potential_range(gall_id), do: PotentialRange.for_gall(gall_id)

  @doc """
  A Gall's range as the map shows it: `:everywhere` when its potential range
  is (`potential_range/1`), else the potential range's places split for
  colouring — exact, country-level (inherited) and introduced — as its
  current Hosts' `host_range` rows give them
  (`Gallformers.Catalog.ReadModels.PotentialRange.for_display/1`). The
  places shown are always the potential range's: this is a presentation of
  it, never a second definition.
  """
  @spec display_range(integer()) :: :everywhere | DisplayRange.t()
  def display_range(gall_id) when is_integer(gall_id), do: PotentialRange.for_display(gall_id)

  @doc """
  A Gall's current Inducer, Hosts and Traits
  (`Gallformers.Catalog.ReadModels.GallSummary`). Raises if there is no such
  Gall.
  """
  @spec gall_summary(integer()) :: GallSummary.t()
  def gall_summary(gall_id), do: GallSummary.for_gall(gall_id)

  @doc """
  Everything the Gall page shows of Gall `id`
  (`Gallformers.Catalog.ReadModels.GallPage`), or `:not_found` when there is
  no such Gall.
  """
  @spec gall_page(integer()) :: {:ok, GallPage.t()} | :not_found
  def gall_page(id) when is_integer(id), do: GallPage.for_gall(id)

  @doc """
  The summaries of the Galls whose current Inducer is one of `taxon_ids`,
  by Gall ID (import matching, `Gallformers.Import.GallMatcher`).
  """
  @spec list_gall_summaries_by_inducer([integer()]) :: [GallSummary.t()]
  def list_gall_summaries_by_inducer(taxon_ids) when is_list(taxon_ids),
    do: GallSummary.for_related("inducer_of", taxon_ids)

  @typedoc "A Gall as a list on a page shows it: its ID, the name shown and completeness."
  @type gall_card :: %{id: integer(), name: String.t(), datacomplete: boolean()}

  @doc """
  The Galls with a current Host among `taxon_ids` (the Host page), each
  once, by the name shown. A genus Host's Galls are listed for the genus's
  ID only, not for its species.
  """
  @spec list_galls_for_hosts([integer()]) :: [gall_card()]
  def list_galls_for_hosts([]), do: []

  def list_galls_for_hosts(taxon_ids) when is_list(taxon_ids) do
    from(r in Current.relationships("host_of"),
      where: r.subject_taxon_id in ^taxon_ids,
      select: r.object_gall_id
    )
    |> gall_cards()
  end

  @doc """
  The Galls whose current Inducer is one of `taxon_ids` (a genus page gives
  its subtree, `Gallformers.Taxa.subtree_ids/1`), each once, by the name
  shown.
  """
  @spec list_galls_for_inducers([integer()]) :: [gall_card()]
  def list_galls_for_inducers([]), do: []

  def list_galls_for_inducers(taxon_ids) when is_list(taxon_ids) do
    from(r in Current.relationships("inducer_of"),
      where: r.subject_taxon_id in ^taxon_ids,
      select: r.object_gall_id
    )
    |> gall_cards()
  end

  @doc """
  The Galls Source `source_id` speaks of (the Source page), each once, by
  the name shown: those it cites (legacy citations), those current Facts it
  attributes are about, and those with a note of it (the Gallformers
  Source's notes).
  """
  @spec list_galls_for_source(integer()) :: [gall_card()]
  def list_galls_for_source(source_id) when is_integer(source_id) do
    from(c in LegacyCitation, where: c.source_id == ^source_id, select: c.gall_id)
    |> union_all(^Current.gall_ids_attributed_by(source_id))
    |> gall_cards(Sources.list_noted_gall_ids(source_id))
  end

  # The Galls whose IDs `gall_ids` (a query) selects or `more_ids` lists, as
  # cards by name.
  defp gall_cards(gall_ids, more_ids \\ []) do
    from(g in Gall,
      where: g.id in subquery(gall_ids) or g.id in ^more_ids,
      select: %{
        id: g.id,
        name: fragment("COALESCE(?, ?)", g.name_override, g.name),
        datacomplete: g.datacomplete
      }
    )
    |> Repo.all()
    |> Enum.sort_by(&{&1.name, &1.id})
  end

  # Site-wide counts, the random Gall, the sitemap (`Gallformers.Catalog.ReadModels.Site`).

  @doc "How many Galls there are."
  @spec count_galls() :: non_neg_integer()
  defdelegate count_galls(), to: Gallformers.Catalog.ReadModels.Site

  @doc "Galls, undescribed Galls, and the families and genera of their current Inducers, counted."
  @spec gall_counts() :: Gallformers.Catalog.ReadModels.Site.gall_counts()
  defdelegate gall_counts(), to: Gallformers.Catalog.ReadModels.Site

  @doc "A random Gall with an image, with the image's URL and credits, or nil."
  @spec random_gall() :: Gallformers.Catalog.ReadModels.Site.random_gall() | nil
  defdelegate random_gall(), to: Gallformers.Catalog.ReadModels.Site

  @doc "Every Gall's ID, ascending."
  @spec list_gall_ids() :: [integer()]
  defdelegate list_gall_ids(), to: Gallformers.Catalog.ReadModels.Site

  # API v2 (`Gallformers.Catalog.ReadModels.Api`).

  @doc """
  A page of Gall rows (ID, name shown, editorial fields, `detachable`,
  `undescribed`, `aliases`; `Gallformers.Catalog.ReadModels.Api`), by the
  name shown, with the `total` in all. Options: `:q` (found as
  `search_galls/2` finds Galls), `:limit` (nil for all), `:offset`.
  """
  @spec paginate_galls(keyword()) :: %{
          entries: [Gallformers.Catalog.ReadModels.Api.row()],
          total: non_neg_integer()
        }
  defdelegate paginate_galls(opts), to: Gallformers.Catalog.ReadModels.Api

  @doc "Gall `id`'s row with its current Hosts and Trait values, or `:not_found`."
  @spec gall_details(integer()) ::
          {:ok, Gallformers.Catalog.ReadModels.Api.details()} | :not_found
  defdelegate gall_details(id), to: Gallformers.Catalog.ReadModels.Api

  @doc "Gall `id`'s Sources as its page lists them (note and legacy citations), or `:not_found`."
  @spec list_gall_sources(integer()) :: {:ok, [GallPage.source()]} | :not_found
  defdelegate list_gall_sources(id), to: Gallformers.Catalog.ReadModels.Api

  @doc "Gall cards with whether each Gall is `undescribed` (no current species-rank Inducer)."
  @spec add_undescribed([map()]) :: [map()]
  defdelegate add_undescribed(cards), to: Gallformers.Catalog.ReadModels.Api

  @doc """
  Gall cards (`list_galls_for_source/1`) with Source `source_id`'s legacy
  citation of each (`description`, `externallink`), or its newest note's
  text as `description`.
  """
  @spec add_citations([map()], integer()) :: [map()]
  defdelegate add_citations(cards, source_id), to: Gallformers.Catalog.ReadModels.Api

  # Rank pages and the Galls browse tree (`Gallformers.Catalog.ReadModels.Browse`).

  @doc """
  The Galls browse tree: Inducer family → genus → Galls, by name, in the
  `Gallformers.Taxa.TreeBuilder` shape (`Gallformers.Catalog.ReadModels.Browse`).
  """
  @spec gall_tree() :: [map()]
  defdelegate gall_tree(), to: Browse

  @doc "The Galls browse tree of the undescribed Galls (Inducer above species)."
  @spec undescribed_gall_tree() :: [map()]
  defdelegate undescribed_gall_tree(), to: Browse

  @doc "How many Galls have a current Inducer in each taxon's subtree, by taxon ID."
  @spec count_galls_under([integer()]) :: %{integer() => non_neg_integer()}
  defdelegate count_galls_under(taxon_ids), to: Browse

  @doc """
  Gall cards (`list_galls_for_inducers/1`, ...) with their first common
  name (`:common_name`) and number of current Hosts (`:host_count`).
  """
  @spec add_gall_details([gall_card()]) :: [map()]
  defdelegate add_gall_details(cards), to: Browse

  @doc "How many Galls have a current Host Fact on each taxon, by taxon ID."
  @spec count_galls_for_hosts([integer()]) :: %{integer() => non_neg_integer()}
  defdelegate count_galls_for_hosts(taxon_ids), to: Browse

  @doc """
  The genera of the current Hosts of the Galls `gall_ids`, by name, each
  with the Galls on it (the genus page's host-genus filter).
  """
  @spec host_genera_of_galls([integer()]) :: [Browse.related_genus()]
  defdelegate host_genera_of_galls(gall_ids), to: Browse

  @doc """
  The genera of the current Inducers of the Galls on `host_ids`, by name,
  each with the hosts it has Galls on (the genus page's gall-former filter).
  """
  @spec inducer_genera_on_hosts([integer()]) :: [Browse.related_genus()]
  defdelegate inducer_genera_on_hosts(host_ids), to: Browse

  @doc "The summaries of the Galls with a current Host among `taxon_ids`, by Gall ID."
  @spec list_gall_summaries_by_host([integer()]) :: [GallSummary.t()]
  def list_gall_summaries_by_host(taxon_ids) when is_list(taxon_ids),
    do: GallSummary.for_related("host_of", taxon_ids)

  # The ID tool (`Gallformers.Catalog.Identify`, over `gall_index`).

  @doc """
  The Galls matching the ID tool's `filters`, by name, each with its
  default image and current Traits (`Gallformers.Catalog.Identify` lists
  the filters).
  """
  @spec identify(Identify.filters()) :: [Identify.result()]
  defdelegate identify(filters), to: Identify

  @doc "How many Galls match the ID tool's `filters` (`identify/1`)."
  @spec count_identified(Identify.filters()) :: non_neg_integer()
  defdelegate count_identified(filters), to: Identify

  @doc "The ID tool's Trait options: each Trait's values, by Trait, each list by value."
  @spec identify_options() :: %{String.t() => [TraitValue.t()]}
  defdelegate identify_options(), to: Identify, as: :options

  @doc """
  The families of the current Inducers of the Galls with a current Host in
  the subtree of one of `taxon_ids` (a Host, or a Host genus or section),
  by name: the ID tool's family choices.
  """
  @spec gall_families_for_hosts([integer()]) :: [Identify.family()]
  defdelegate gall_families_for_hosts(taxon_ids), to: Identify

  @doc """
  The Galls whose display name, a current alias Fact, or a name (accepted
  or synonym) of their current species-rank Inducer holds every word of
  `query`, by display name, each with its `aliases` and `undescribed` flag
  (`Gallformers.Catalog.ReadModels.Search`, the global search). Options:
  `:place_ids` keeps the Galls whose potential range has one of those
  places, and every Gall found everywhere.
  """
  @spec search_galls(String.t(), keyword()) :: [Gallformers.Catalog.ReadModels.Search.hit()]
  defdelegate search_galls(query, opts \\ []),
    to: Gallformers.Catalog.ReadModels.Search,
    as: :galls

  # The ID tool's lookup table (`Gallformers.Catalog.ReadModels.GallIndex`).

  @doc """
  Recomputes the ID tool's lookup-table rows of the Galls among `gall_ids`
  now. Changes to Facts and taxa refresh them through Oban by themselves.
  """
  @spec refresh_gall_index([integer()]) :: :ok
  defdelegate refresh_gall_index(gall_ids), to: GallIndex, as: :refresh

  @doc "Recomputes every Gall's row of the ID tool's lookup table (the data migration's last step)."
  @spec rebuild_gall_index() :: :ok
  defdelegate rebuild_gall_index(), to: GallIndex, as: :rebuild_all

  @doc """
  Runs `fun` with lookup-table refreshes off for this process, returning
  its result: for bulk writes followed by `rebuild_gall_index/0`.
  """
  @spec without_gall_index_refresh((-> result)) :: result when result: var
  defdelegate without_gall_index_refresh(fun), to: GallIndex, as: :without_refresh

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
