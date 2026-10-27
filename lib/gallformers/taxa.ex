defmodule Gallformers.Taxa do
  @moduledoc """
  Taxa: taxa at every rank, their names, rank and placement in the
  editorial tree, the ancestry read model, and name resolution for import
  (`9449` §3; rules in `8567`).

  This is the taxonomy storage; nothing here reads the old `taxonomy`
  tables, which only the data migration and the old ID filter read.

  ## The editorial tree (phase 1)

  `taxa.parent_id` is the tree: the migrated skeleton plus curator edits,
  audited, with no Facts. Every parent change goes through
  `Gallformers.Taxa.Tree` (no cycles; a child ranks below its parent) and
  rebuilds the moved subtree's rows in `Gallformers.Taxa.Ancestry`.

  Moves and renames call the registered "taxon changed" listeners inside
  their transaction (`Gallformers.Taxa.Events`, `8567` rule 6).

  ## Taxonomic-act Facts

  What Sources say about taxa (placements, names, synonymies, splits,
  common names) is recorded as Facts by the `assert_*` functions
  (`Gallformers.Taxa.ActFacts`). In phase 1 they are recorded only and
  never move the editorial tree.

  ## Writes

  Every write is audited (`Gallformers.Audit`) as the given actor, and can
  be nested inside an outer `Gallformers.Audit.transaction/3` with the same
  actor (e.g. an import creating a taxon and linking a Gall to it).

  Taxa knows nothing about Galls (`8567` rule 3): it depends on `Repo`,
  `Audit` and `Facts` only.
  """
  use Boundary,
    deps: [Gallformers.Audit, Gallformers.Facts, Gallformers.Repo, Gallformers.TextMatch],
    exports: [
      ActFacts,
      ActFacts.CommonNameFact,
      ActFacts.NameFact,
      ActFacts.PlacementFact,
      ActFacts.SplitFact,
      ActFacts.SynonymyFact,
      CommonName,
      Event,
      Events,
      LegacyId,
      NameNormalizer,
      Rank,
      ReadModels.HostPage,
      Taxon,
      TaxonName,
      TreeBuilder
    ]

  import Ecto.Query

  alias Ecto.Changeset
  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Repo
  alias Gallformers.Taxa.ActFacts
  alias Gallformers.Taxa.ActFacts.CommonNameFact
  alias Gallformers.Taxa.ActFacts.NameFact
  alias Gallformers.Taxa.ActFacts.PlacementFact
  alias Gallformers.Taxa.ActFacts.SplitFact
  alias Gallformers.Taxa.ActFacts.SynonymyFact
  alias Gallformers.Taxa.Ancestry
  alias Gallformers.Taxa.CommonName
  alias Gallformers.Taxa.Event
  alias Gallformers.Taxa.Events
  alias Gallformers.Taxa.LegacyId
  alias Gallformers.Taxa.NameNormalizer
  alias Gallformers.Taxa.Rank
  alias Gallformers.Taxa.ReadModels.Browse
  alias Gallformers.Taxa.ReadModels.HostPage
  alias Gallformers.Taxa.ReadModels.Search
  alias Gallformers.Taxa.Taxon
  alias Gallformers.Taxa.TaxonName
  alias Gallformers.Taxa.Tree

  @type taxon_ref :: Taxon.t() | integer()

  @type resolution :: {:ok, Taxon.t()} | {:ambiguous, [Taxon.t()]} | :none

  # -- taxa --------------------------------------------------------------------

  @doc """
  Creates a taxon with its accepted name.

  `attrs` (atom keys): `:rank`, `:origin` (`:curated | :powo`) and `:name`
  are required; `:parent_id` (nil for a root), `:kingdom` (taken from the
  parent when not given), the name's `:sensu` and `:authorship`, a plant's
  editorial `:datacomplete` and `:abundance_id`, and `:id` for a migrated
  plant keeping its species ID (otherwise the shared sequence gives one).

  The parent is checked by the tree validator (`Gallformers.Taxa.Tree`).
  On error nothing is written and the changeset says why.
  """
  @spec create_taxon(Actor.t(), map()) :: {:ok, Taxon.t()} | {:error, Changeset.t()}
  def create_taxon(%Actor{} = actor, attrs) when is_map(attrs) do
    Audit.transaction(actor, "taxa.create_taxon", fn ->
      Tree.lock()

      changeset =
        %Taxon{}
        |> Taxon.create_changeset(attrs)
        |> require_name(attrs)
        |> inherit_kingdom()
        |> Tree.validate_parent()

      with {:ok, taxon} <- Repo.insert(changeset),
           :ok <- Ancestry.add_leaf(taxon.id, taxon.parent_id),
           {:ok, name} <- insert_name(taxon, :accepted, attrs) do
        %{taxon | names: [name]}
      else
        {:error, changeset} -> Repo.rollback(changeset)
      end
    end)
  end

  defp require_name(changeset, attrs) do
    case Map.get(attrs, :name) do
      name when is_binary(name) and name != "" -> changeset
      _ -> Changeset.add_error(changeset, :name, "can't be blank", validation: :required)
    end
  end

  defp inherit_kingdom(changeset) do
    parent_id = Changeset.get_field(changeset, :parent_id)

    if Changeset.get_field(changeset, :kingdom) == nil and parent_id != nil do
      case Repo.get(Taxon, parent_id) do
        %Taxon{kingdom: kingdom} -> Changeset.put_change(changeset, :kingdom, kingdom)
        nil -> changeset
      end
    else
      changeset
    end
  end

  defp insert_name(%Taxon{id: taxon_id}, status, attrs) do
    %TaxonName{}
    |> TaxonName.changeset(%{
      taxon_id: taxon_id,
      status: status,
      name: Map.get(attrs, :name),
      sensu: Map.get(attrs, :sensu),
      authorship: Map.get(attrs, :authorship)
    })
    |> Repo.insert()
  end

  @doc "Gets a taxon by ID with its names, or nil."
  @spec get_taxon(integer()) :: Taxon.t() | nil
  def get_taxon(id), do: Taxon |> Repo.get(id) |> Repo.preload(names: names_order())

  @doc "Gets a taxon by ID with its names, raising if there is none."
  @spec get_taxon!(integer()) :: Taxon.t()
  def get_taxon!(id), do: Taxon |> Repo.get!(id) |> Repo.preload(names: names_order())

  # Accepted name first, then synonyms in the order added.
  defp names_order, do: from(n in TaxonName, order_by: [n.status, n.id])

  @doc "A taxon's accepted name."
  @spec accepted_name(taxon_ref()) :: String.t()
  def accepted_name(%Taxon{names: names}) when is_list(names) do
    Enum.find_value(names, fn n -> n.status == :accepted && n.name end)
  end

  def accepted_name(taxon) do
    Repo.one!(
      from(n in TaxonName,
        where: n.taxon_id == ^taxon_id(taxon) and n.status == :accepted,
        select: n.name
      )
    )
  end

  # -- names -------------------------------------------------------------------

  @doc """
  Adds a synonym to a taxon. `opts`: `:sensu` (for a misapplied name, the
  usage meant, as written) and `:authorship`.
  """
  @spec add_synonym(Actor.t(), taxon_ref(), String.t(), keyword()) ::
          {:ok, TaxonName.t()} | {:error, Changeset.t()}
  def add_synonym(%Actor{} = actor, taxon, name, opts \\ []) when is_binary(name) do
    Audit.transaction(actor, "taxa.add_synonym", fn ->
      %TaxonName{}
      |> TaxonName.changeset(%{
        taxon_id: taxon_id(taxon),
        status: :synonym,
        name: name,
        sensu: opts[:sensu],
        authorship: opts[:authorship]
      })
      |> Repo.insert()
      |> unwrap_or_rollback()
    end)
  end

  @doc """
  Gives a taxon a new accepted name (an editorial rename). The old accepted
  name stays as a synonym, so Sources using it still resolve; if the new name
  is already one of the taxon's synonyms, that synonym is promoted. A new
  name that only differs from the accepted one in form (case, spacing,
  "var.") replaces it in place, keeping no synonym.

  Calls the "taxon changed" listeners with a `:rename` event
  (`Gallformers.Taxa.Events`); a listener's error rolls the rename back.
  Renaming to the current accepted name changes nothing.
  """
  @spec rename(Actor.t(), taxon_ref(), String.t()) ::
          {:ok, Taxon.t()} | {:error, Changeset.t() | Events.rejection()}
  def rename(%Actor{} = actor, taxon, new_name) when is_binary(new_name) do
    Audit.transaction(actor, "taxa.rename", fn ->
      id = taxon_id(taxon)
      new_name = String.trim(new_name)

      accepted =
        Repo.one!(
          from(n in TaxonName,
            where: n.taxon_id == ^id and n.status == :accepted,
            lock: "FOR UPDATE"
          )
        )

      cond do
        accepted.name == new_name ->
          :ok

        accepted.normalized_name == NameNormalizer.normalize(new_name) ->
          accepted
          |> TaxonName.changeset(%{name: new_name})
          |> Repo.update()
          |> unwrap_or_rollback()

          rename_event(id, accepted.name, new_name)

        true ->
          accepted
          |> TaxonName.status_changeset(:synonym)
          |> Repo.update()
          |> unwrap_or_rollback()

          promote_or_insert_name(id, new_name)
          rename_event(id, accepted.name, new_name)
      end

      get_taxon!(id)
    end)
  end

  defp promote_or_insert_name(taxon_id, name) do
    normalized = NameNormalizer.normalize(name)

    synonym =
      Repo.one(
        from(n in TaxonName,
          where: n.taxon_id == ^taxon_id and n.normalized_name == ^normalized and is_nil(n.sensu)
        )
      )

    (synonym || %TaxonName{})
    |> TaxonName.changeset(%{taxon_id: taxon_id, name: name, status: :accepted})
    |> Repo.insert_or_update()
    |> unwrap_or_rollback()
  end

  defp rename_event(taxon_id, old_name, new_name) do
    :ok =
      Events.dispatch(%Event{
        type: :rename,
        taxon_id: taxon_id,
        old_name: old_name,
        new_name: new_name
      })
  end

  @doc "Adds a common name to a taxon (held once per taxon, ignoring case)."
  @spec add_common_name(Actor.t(), taxon_ref(), String.t()) ::
          {:ok, CommonName.t()} | {:error, Changeset.t()}
  def add_common_name(%Actor{} = actor, taxon, name) when is_binary(name) do
    Audit.transaction(actor, "taxa.add_common_name", fn ->
      %CommonName{}
      |> CommonName.changeset(%{taxon_id: taxon_id(taxon), name: name})
      |> Repo.insert()
      |> unwrap_or_rollback()
    end)
  end

  @doc "A taxon's common names, in the order added."
  @spec list_common_names(taxon_ref()) :: [CommonName.t()]
  def list_common_names(taxon) do
    Repo.all(from(c in CommonName, where: c.taxon_id == ^taxon_id(taxon), order_by: c.id))
  end

  @doc """
  Removes a synonym (a `Gallformers.Taxa.TaxonName` or its ID): the name no
  longer resolves to the taxon. `{:error, :accepted_name}` for the accepted
  name (rename the taxon instead), `{:error, :not_found}` when there is no
  such name.
  """
  @spec remove_synonym(Actor.t(), TaxonName.t() | integer()) ::
          {:ok, TaxonName.t()} | {:error, :accepted_name | :not_found | Changeset.t()}
  def remove_synonym(%Actor{} = actor, name) do
    Audit.transaction(actor, "taxa.remove_synonym", fn ->
      case Repo.get(TaxonName, row_id(name)) do
        %TaxonName{status: :synonym} = synonym -> synonym |> Repo.delete() |> unwrap_or_rollback()
        %TaxonName{status: :accepted} -> Repo.rollback(:accepted_name)
        nil -> Repo.rollback(:not_found)
      end
    end)
  end

  @doc """
  Removes a common name (a `Gallformers.Taxa.CommonName` or its ID).
  `{:error, :not_found}` when there is no such name.
  """
  @spec remove_common_name(Actor.t(), CommonName.t() | integer()) ::
          {:ok, CommonName.t()} | {:error, :not_found | Changeset.t()}
  def remove_common_name(%Actor{} = actor, common_name) do
    Audit.transaction(actor, "taxa.remove_common_name", fn ->
      case Repo.get(CommonName, row_id(common_name)) do
        %CommonName{} = found -> found |> Repo.delete() |> unwrap_or_rollback()
        nil -> Repo.rollback(:not_found)
      end
    end)
  end

  # -- editorial flags ---------------------------------------------------------

  @doc """
  Sets a plant's editorial flags (`803b` decision 6): `:datacomplete`
  (every gall known on the plant is in the database) and `:abundance_id`
  (how common it is; nil for unknown). Other keys in `attrs` are ignored.
  """
  @spec update_editorial(Actor.t(), taxon_ref(), map()) ::
          {:ok, Taxon.t()} | {:error, Changeset.t()}
  def update_editorial(%Actor{} = actor, taxon, attrs) when is_map(attrs) do
    Audit.transaction(actor, "taxa.update_editorial", fn ->
      Taxon
      |> Repo.get!(taxon_id(taxon))
      |> Taxon.editorial_changeset(attrs)
      |> Repo.update()
      |> unwrap_or_rollback()
    end)
  end

  @doc "The abundances a plant can be given, as `{name, id}`, by ID."
  @spec abundance_options() :: [{String.t(), integer()}]
  def abundance_options,
    do: Repo.all(from(a in "abundance", order_by: a.id, select: {a.abundance, a.id}))

  # -- deleting ----------------------------------------------------------------

  @typedoc """
  Rows that refer to a taxon: `count` rows of `table` name it in `column`.
  """
  @type taxon_reference :: %{table: String.t(), column: String.t(), count: pos_integer()}

  @doc """
  The columns that refer to a taxon and keep it from being deleted, as
  `{table, column}`: every foreign key to `taxa` that does not delete its
  rows with the taxon — its children (`taxa.parent_id`), Facts and their
  attributions, Galls, Host ranges and images (whose keys would only be
  cleared), generation groups, import statements. Read from the database's
  foreign keys, so a new one is checked without naming it here. Rows whose
  key deletes with the taxon (its names, common names, crosswalk entries,
  ancestry, WCVP link) are the taxon's own.
  """
  @spec reference_columns() :: [{String.t(), String.t()}]
  def reference_columns do
    """
    SELECT c.conrelid::regclass::text, a.attname::text
    FROM pg_constraint c
    JOIN pg_attribute a ON a.attrelid = c.conrelid AND a.attnum = ANY (c.conkey)
    WHERE c.contype = 'f' AND c.confrelid = 'taxa'::regclass AND c.confdeltype <> 'c'
    ORDER BY 1, 2
    """
    |> Repo.query!()
    |> Map.fetch!(:rows)
    |> Enum.map(fn [table, column] -> {table, column} end)
  end

  @doc """
  What refers to `taxon` (`reference_columns/0`), by table and column; empty
  when nothing does and the taxon can be deleted (`delete_taxon/2`).
  """
  @spec references(taxon_ref()) :: [taxon_reference()]
  def references(taxon) do
    sql =
      Enum.map_join(reference_columns(), " UNION ALL ", fn {table, column} ->
        ~s|SELECT '#{table}', '#{column}', count(*) FROM "#{table}" WHERE "#{column}" = $1|
      end)

    sql
    |> Repo.query!([taxon_id(taxon)])
    |> Map.fetch!(:rows)
    |> Enum.filter(fn [_table, _column, count] -> count > 0 end)
    |> Enum.map(fn [table, column, count] -> %{table: table, column: column, count: count} end)
  end

  @doc "Whether anything refers to `taxon` (`references/1`)."
  @spec referenced?(taxon_ref()) :: boolean()
  def referenced?(taxon), do: references(taxon) != []

  @doc """
  Deletes a taxon nothing refers to (`a856` decision 8), with its own rows:
  its names, common names and crosswalk entries (and its ancestry rows and
  WCVP link, whose keys delete with it). `{:error, {:referenced,
  references}}` when anything refers to it (`references/1`); nothing is
  deleted then.
  """
  @spec delete_taxon(Actor.t(), taxon_ref()) ::
          {:ok, Taxon.t()} | {:error, {:referenced, [taxon_reference()]} | Changeset.t()}
  def delete_taxon(%Actor{} = actor, taxon) do
    Audit.transaction(actor, "taxa.delete_taxon", fn ->
      Tree.lock()
      id = taxon_id(taxon)

      # Locked, so no row can come to refer to it before the delete commits.
      found = Repo.one!(from(t in Taxon, where: t.id == ^id, lock: "FOR UPDATE"))

      case references(id) do
        [] ->
          Repo.delete_all(from(n in TaxonName, where: n.taxon_id == ^id))
          Repo.delete_all(from(c in CommonName, where: c.taxon_id == ^id))
          Repo.delete_all(from(l in LegacyId, where: l.taxon_id == ^id))
          found |> Repo.delete() |> unwrap_or_rollback()

        references ->
          Repo.rollback({:referenced, references})
      end
    end)
  end

  # -- legacy crosswalk --------------------------------------------------------

  @doc """
  Maps an identifier of the old model to `taxon` (`Gallformers.Taxa.LegacyId`
  for the kinds). `legacy_name` is the old row's name as it was.
  """
  @spec add_legacy_id(Actor.t(), taxon_ref(), LegacyId.kind(), integer(), String.t() | nil) ::
          {:ok, LegacyId.t()} | {:error, Changeset.t()}
  def add_legacy_id(%Actor{} = actor, taxon, kind, legacy_id, legacy_name \\ nil) do
    Audit.transaction(actor, "taxa.add_legacy_id", fn ->
      %LegacyId{}
      |> LegacyId.changeset(%{
        taxon_id: taxon_id(taxon),
        kind: kind,
        legacy_id: legacy_id,
        legacy_name: legacy_name
      })
      |> Repo.insert()
      |> unwrap_or_rollback()
    end)
  end

  @doc "The taxon an old identifier maps to, or nil."
  @spec get_by_legacy_id(LegacyId.kind(), integer()) :: Taxon.t() | nil
  def get_by_legacy_id(kind, legacy_id) do
    Repo.one(
      from(t in Taxon,
        join: l in LegacyId,
        on: l.taxon_id == t.id,
        where: l.kind == ^kind and l.legacy_id == ^legacy_id
      )
    )
  end

  # -- the tree ----------------------------------------------------------------

  @doc """
  Moves `taxon` under `parent` (a taxon, an ID, or nil to make it a root),
  through the tree validator, and rebuilds the moved subtree's ancestry.

  A cycle or rank inversion is `{:error, changeset}` with the error on
  `:parent_id` (`validation: :cycle | :rank_inversion`); nothing changes.

  A move calls the "taxon changed" listeners with a `:move` event
  (`Gallformers.Taxa.Events`); a listener's error rolls the move back and
  returns `{:error, {:rejected, listener, reason}}`. Placing a taxon where
  it already is changes nothing and calls no listener.
  """
  @spec place(Actor.t(), taxon_ref(), taxon_ref() | nil) ::
          {:ok, Taxon.t()} | {:error, Changeset.t() | Events.rejection()}
  def place(%Actor{} = actor, taxon, parent) do
    Audit.transaction(actor, "taxa.place", fn ->
      Tree.lock()

      current = Repo.get!(Taxon, taxon_id(taxon))
      parent_id = parent && taxon_id(parent)

      changeset =
        current
        |> Taxon.parent_changeset(parent_id)
        |> Tree.validate_parent()
        |> validate_section_genus(current)

      cond do
        not changeset.valid? ->
          Repo.rollback(changeset)

        parent_id == current.parent_id ->
          current

        true ->
          moved = changeset |> Repo.update() |> unwrap_or_rollback()
          :ok = Ancestry.move_subtree(moved.id, parent_id)

          :ok =
            Events.dispatch(%Event{
              type: :move,
              taxon_id: moved.id,
              from_parent_id: current.parent_id,
              to_parent_id: parent_id
            })

          moved
      end
    end)
  end

  # A section's members share one genus: a plant at species rank or below
  # placed in a section must be named in the section's genus (the genus
  # above it), compared as names are normalized.
  defp validate_section_genus(%Changeset{valid?: false} = changeset, _current), do: changeset

  defp validate_section_genus(changeset, %Taxon{kingdom: "Plantae"} = current) do
    parent_id = Changeset.get_field(changeset, :parent_id)

    with true <- current.rank in Rank.species_and_below(),
         %Taxon{rank: :section} <- parent_id && Repo.get(Taxon, parent_id),
         %Taxon{} = genus <- Enum.find(ancestors(parent_id), &(&1.rank == :genus)),
         genus_name = accepted_name(genus),
         false <- genus_word(accepted_name(current)) == NameNormalizer.normalize(genus_name) do
      Changeset.add_error(changeset, :parent_id, "must be in the section's genus, %{genus}",
        validation: :section_genus,
        genus: genus_name
      )
    else
      _ -> changeset
    end
  end

  defp validate_section_genus(changeset, _current), do: changeset

  defp genus_word(name), do: name |> NameNormalizer.normalize() |> String.split() |> List.first()

  @doc "The taxa above `taxon`, nearest first."
  @spec ancestors(taxon_ref()) :: [Taxon.t()]
  def ancestors(taxon) do
    from(t in Taxon,
      join: a in Ancestry,
      on: a.ancestor_id == t.id,
      where: a.descendant_id == ^taxon_id(taxon) and a.depth > 0,
      order_by: a.depth
    )
    |> Repo.all()
  end

  @typedoc "A taxon in a lineage: its ID, accepted name and rank."
  @type lineage_entry :: %{taxon_id: integer(), name: String.t(), rank: Gallformers.Taxa.Rank.t()}

  @doc """
  `taxon` and the taxa above it, root first, each with its accepted name and
  rank (a breadcrumb).
  """
  @spec lineage(taxon_ref()) :: [lineage_entry()]
  def lineage(taxon) do
    from(t in Taxon,
      join: a in Ancestry,
      on: a.ancestor_id == t.id,
      join: n in TaxonName,
      on: n.taxon_id == t.id and n.status == :accepted,
      where: a.descendant_id == ^taxon_id(taxon),
      order_by: [desc: a.depth],
      select: %{taxon_id: t.id, name: n.name, rank: t.rank}
    )
    |> Repo.all()
  end

  @doc "A taxon's synonyms (not its accepted name), in the order added."
  @spec list_synonyms(taxon_ref()) :: [TaxonName.t()]
  def list_synonyms(taxon) do
    Repo.all(
      from(n in TaxonName,
        where: n.taxon_id == ^taxon_id(taxon) and n.status == :synonym,
        order_by: n.id
      )
    )
  end

  @doc "The taxa below `taxon`, nearest first."
  @spec descendants(taxon_ref()) :: [Taxon.t()]
  def descendants(taxon) do
    from(t in Taxon,
      join: a in Ancestry,
      on: a.descendant_id == t.id,
      where: a.ancestor_id == ^taxon_id(taxon) and a.depth > 0,
      order_by: [a.depth, t.id]
    )
    |> Repo.all()
  end

  # -- read models -------------------------------------------------------------

  @doc """
  What the Host page shows of plant taxon `id`
  (`Gallformers.Taxa.ReadModels.HostPage`), or `:not_found` when there is no
  such taxon or it is not a plant at species rank or below.
  """
  @spec host_page(integer()) :: {:ok, HostPage.t()} | :not_found
  def host_page(id) when is_integer(id), do: HostPage.for_taxon(id)

  # Rank pages and the Hosts browse tree (`Gallformers.Taxa.ReadModels.Browse`).

  @doc """
  The taxa of `rank` whose accepted name is `name`, by ID (a rank page's
  lookup). Names are not unique: a genus name can be used in two kingdoms.
  """
  @spec get_by_name(String.t(), Gallformers.Taxa.Rank.t()) :: [Taxon.t()]
  defdelegate get_by_name(name, rank), to: Browse

  @doc "The taxa with no parent (the tree's roots), by name, as `children_with_ranks/1` gives taxa."
  @spec root_taxa() :: [Browse.child()]
  defdelegate root_taxa(), to: Browse, as: :roots

  @doc "The taxa directly under a taxon, by name, with their ranks and common names."
  @spec children_with_ranks(integer()) :: [Browse.child()]
  defdelegate children_with_ranks(taxon_id), to: Browse

  @doc "Each taxon's direct children (as `children_with_ranks/1`), by parent ID."
  @spec children_by_parent([integer()]) :: %{integer() => [Browse.child()]}
  defdelegate children_by_parent(taxon_ids), to: Browse

  @doc """
  How many plants (Plantae at species rank or below) each taxon's subtree
  holds, itself included, by taxon ID.
  """
  @spec count_plants_under([integer()]) :: %{integer() => non_neg_integer()}
  defdelegate count_plants_under(taxon_ids), to: Browse

  @doc "The plants in a taxon's subtree, by name, each with its first common name."
  @spec list_plants_under(integer()) :: [Browse.plant()]
  defdelegate list_plants_under(taxon_id), to: Browse

  @doc "Each taxon's lineage (as `lineage/1`), by taxon ID."
  @spec lineages([integer()]) :: %{integer() => [lineage_entry()]}
  defdelegate lineages(taxon_ids), to: Browse

  @doc "Each taxon's ID and the IDs of the taxa below it, by taxon ID."
  @spec subtree_ids([integer()]) :: %{integer() => [integer()]}
  defdelegate subtree_ids(taxon_ids), to: Browse

  @doc "Each taxon's common names, in the order added, by taxon ID (taxa without any left out)."
  @spec common_names([integer()]) :: %{integer() => [String.t()]}
  defdelegate common_names(taxon_ids), to: Browse

  @doc """
  The Hosts browse tree: plant families → genera → plants, by name, in the
  `Gallformers.Taxa.TreeBuilder` shape.
  """
  @spec plant_tree() :: [map()]
  defdelegate plant_tree(), to: Browse

  # Site-wide counts and the sitemap (`Gallformers.Taxa.ReadModels.Site`).

  @doc "How many plants (Plantae at species rank or below) there are."
  @spec count_plants() :: non_neg_integer()
  defdelegate count_plants(), to: Gallformers.Taxa.ReadModels.Site

  @doc "How many plants, and how many plant families and genera hold at least one."
  @spec plant_counts() :: Gallformers.Taxa.ReadModels.Site.plant_counts()
  defdelegate plant_counts(), to: Gallformers.Taxa.ReadModels.Site

  @doc "Every plant's ID, ascending."
  @spec list_plant_ids() :: [integer()]
  defdelegate list_plant_ids(), to: Gallformers.Taxa.ReadModels.Site

  @doc "The taxa at ranks with a page, as `%{rank, name}`, each name and rank once."
  @spec list_rank_pages() :: [Gallformers.Taxa.ReadModels.Site.rank_page()]
  defdelegate list_rank_pages(), to: Gallformers.Taxa.ReadModels.Site

  # API v2 (`Gallformers.Taxa.ReadModels.Api`).

  @doc """
  A page of plants (Plantae at species rank or below), by accepted name,
  each `%{id, name, datacomplete}`, with the `total` in all. Options: `:q`
  (found as `search_ids/2` finds taxa), `:limit` (nil for all), `:offset`.
  """
  @spec paginate_plants(keyword()) :: Gallformers.Taxa.ReadModels.Api.page(map())
  defdelegate paginate_plants(opts), to: Gallformers.Taxa.ReadModels.Api

  @doc """
  A page of the taxa of `rank`, by accepted name, each with its parent ID and
  its common names as `description`, with the `total` in all. Options as
  `paginate_plants/1`.
  """
  @spec paginate_taxa(Gallformers.Taxa.Rank.t(), keyword()) ::
          Gallformers.Taxa.ReadModels.Api.page(Gallformers.Taxa.ReadModels.Api.summary())
  defdelegate paginate_taxa(rank, opts), to: Gallformers.Taxa.ReadModels.Api

  @doc "One taxon as `paginate_taxa/2` lists it, or nil."
  @spec taxon_summary(integer()) :: Gallformers.Taxa.ReadModels.Api.summary() | nil
  defdelegate taxon_summary(id), to: Gallformers.Taxa.ReadModels.Api

  @doc "Every section with its genus and how many plants it holds, by genus name and name."
  @spec list_sections() :: [Gallformers.Taxa.ReadModels.Api.section()]
  defdelegate list_sections(), to: Gallformers.Taxa.ReadModels.Api

  @doc """
  Each taxon's synonyms as `%{id, name, sensu}`, in the order added, by taxon
  ID (taxa without any left out).
  """
  @spec list_synonyms_by_taxon([integer()]) :: %{
          integer() => [Gallformers.Taxa.ReadModels.Api.synonym()]
        }
  defdelegate list_synonyms_by_taxon(taxon_ids), to: Gallformers.Taxa.ReadModels.Api

  # Typeaheads (`Gallformers.Taxa.ReadModels.Search`).

  @doc """
  Plants (Plantae at species rank or below) whose accepted name, synonyms
  or common names match every word of `query`, at most `limit`: an exact
  name first, then names starting with the query, then the rest, each by
  accepted name. Each with its rank, data-complete flag and `aliases`
  (synonyms, then common names).
  """
  @spec search_plants(String.t(), pos_integer()) :: [Search.plant()]
  defdelegate search_plants(query, limit), to: Search, as: :plants

  @doc """
  Genera, subgenera and sections whose name (accepted or synonym) starts
  with `query` or whose common name contains it, at most `limit`, genera
  first, each by name, with its common names as `description`. Options:
  `:kingdom` (e.g. `"Plantae"`).
  """
  @spec search_genera_and_sections(String.t(), pos_integer(), keyword()) :: [Search.group()]
  defdelegate search_genera_and_sections(query, limit, opts \\ []),
    to: Search,
    as: :genera_and_sections

  # Global search (`Gallformers.Taxa.ReadModels.Search`).

  @doc """
  Taxa one of whose names (accepted, synonym or common) holds every word
  of `query` (a word may also be in the accepted name), by accepted name,
  each with its rank, kingdom, parent ID, data-complete flag and `aliases`
  (synonyms, then common names). Options: `:ranks` (a list of ranks),
  `:kingdom` (e.g. `"Plantae"`).
  """
  @spec search(String.t(), keyword()) :: [Search.hit()]
  defdelegate search(query, opts \\ []), to: Search, as: :taxa

  @doc "The IDs of the taxa `search/2` finds, unordered."
  @spec search_ids(String.t(), keyword()) :: [integer()]
  defdelegate search_ids(query, opts \\ []), to: Search, as: :taxon_ids

  # -- taxonomic-act Facts -----------------------------------------------------

  @doc """
  Records a Source's stance on a placement: `key` is
  `%{taxon_id, parent_id}`. Finds or creates the Fact (slot
  `"taxon:<id>:placement"`), then attributes it with `attribution` (as
  `Gallformers.Facts.attribute/2` takes it, without `:fact_id`). Recorded
  only: the editorial tree does not move. See `Gallformers.Taxa.ActFacts`.
  """
  @spec assert_placement(Actor.t(), map(), map()) ::
          {:ok, ActFacts.result()} | {:error, Changeset.t()}
  def assert_placement(actor, key, attribution),
    do: ActFacts.assert(PlacementFact, actor, key, attribution)

  @doc """
  Records a Source's stance on a name: `key` is `%{taxon_id, name, rank}`
  (slot `"taxon:<id>:name"`). Give the Source's authorship as
  `:authorship_as_written` in `attribution`. Recorded only.
  """
  @spec assert_name(Actor.t(), map(), map()) ::
          {:ok, ActFacts.result()} | {:error, Changeset.t()}
  def assert_name(actor, key, attribution),
    do: ActFacts.assert(NameFact, actor, key, attribution)

  @doc """
  Records a Source's stance on a synonymy: `key` is
  `%{name, accepted_taxon_id}` (the synonym as a name). Recorded only.
  """
  @spec assert_synonymy(Actor.t(), map(), map()) ::
          {:ok, ActFacts.result()} | {:error, Changeset.t()}
  def assert_synonymy(actor, key, attribution),
    do: ActFacts.assert(SynonymyFact, actor, key, attribution)

  @doc """
  Records a Source's stance on a split: `key` is
  `%{taxon_id, into_taxon_ids}` (two or more daughters, any order).
  Recorded only.
  """
  @spec assert_split(Actor.t(), map(), map()) ::
          {:ok, ActFacts.result()} | {:error, Changeset.t()}
  def assert_split(actor, key, attribution),
    do: ActFacts.assert(SplitFact, actor, key, attribution)

  @doc """
  Records a Source's stance on a common name: `key` is
  `%{taxon_id, common_name}`. Recorded only.
  """
  @spec assert_common_name(Actor.t(), map(), map()) ::
          {:ok, ActFacts.result()} | {:error, Changeset.t()}
  def assert_common_name(actor, key, attribution),
    do: ActFacts.assert(CommonNameFact, actor, key, attribution)

  @act_kinds %{
    name: NameFact,
    placement: PlacementFact,
    synonymy: SynonymyFact,
    split: SplitFact,
    common_name: CommonNameFact
  }

  @typedoc "A taxonomic act kind, as the import contract names it."
  @type act_kind :: :name | :placement | :synonymy | :split | :common_name

  @doc """
  Records a Source's stance on an act of `kind` (`:name`, `:placement`,
  `:synonymy`, `:split`, `:common_name`): the same as the `assert_*`
  function of that kind.
  """
  @spec assert_act(act_kind(), Actor.t(), map(), map()) ::
          {:ok, ActFacts.result()} | {:error, Changeset.t()}
  def assert_act(kind, actor, key, attribution),
    do: ActFacts.assert(Map.fetch!(@act_kinds, kind), actor, key, attribution)

  @doc """
  Finds the act Fact of `kind` with natural key `key` without writing:
  `{:ok, fact_id}`, `{:ok, nil}` when there is none yet, or
  `{:error, changeset}` when the key is invalid.
  """
  @spec find_act_fact(act_kind(), map()) :: {:ok, integer() | nil} | {:error, Changeset.t()}
  def find_act_fact(kind, key) do
    with {:ok, detail} <- ActFacts.find(Map.fetch!(@act_kinds, kind), key) do
      {:ok, detail && detail.fact_id}
    end
  end

  @doc "A taxon's placement Facts (with their Facts and standings), oldest first."
  @spec list_placement_facts(taxon_ref()) :: [PlacementFact.t()]
  def list_placement_facts(taxon), do: ActFacts.list_placement_facts(taxon_id(taxon))

  # -- resolution --------------------------------------------------------------

  @doc """
  Resolves a name as a Source writes it to a taxon, matching accepted names
  and synonyms through the normalized name (`Gallformers.Taxa.NameNormalizer`:
  case, whitespace, "var.", subgenus in parentheses, hybrid sign). No fuzzy
  matching.

  Options:

    * `:rank` — only taxa of this rank
    * `:kingdom` — only taxa of this kingdom (e.g. `"Plantae"`)
    * `:sensu` — match only misapplied names recorded with this sensu
      (case-insensitive); without it, misapplied names are skipped

  Returns `{:ok, taxon}` for one taxon, `{:ambiguous, taxa}` (by ID) for
  several (names are not globally unique), or `:none`. Each returned taxon's
  `matched_name` is the name that matched, so a match through a synonym can
  be told from one through the accepted name.
  """
  @spec resolve_name(String.t(), keyword()) :: resolution()
  def resolve_name(name, opts \\ []) when is_binary(name) do
    normalized = NameNormalizer.normalize(name)

    from(n in TaxonName,
      join: t in assoc(n, :taxon),
      where: n.normalized_name == ^normalized,
      order_by: [t.id, n.status, n.id],
      select: {t, n}
    )
    |> filter_rank(opts[:rank])
    |> filter_kingdom(opts[:kingdom])
    |> filter_sensu(opts[:sensu])
    |> resolution()
  end

  defp resolution(query) do
    query
    |> Repo.all()
    |> Enum.uniq_by(fn {taxon, _name} -> taxon.id end)
    |> Enum.map(fn {taxon, name} -> %{taxon | matched_name: name} end)
    |> case do
      [] -> :none
      [taxon] -> {:ok, taxon}
      taxa -> {:ambiguous, taxa}
    end
  end

  @doc """
  Resolves a species epithet in any genus: the taxa with a binomial name
  (accepted or synonym) whose second word is `epithet`, compared normalized.
  Used for 19th-century oak-gall names whose genus has changed ("Cynips q.
  spongifica" is today's epithet *quercusspongifica*, usually in another
  genus). Options as `resolve_name/2`; `:rank` defaults to `:species`.
  """
  @spec resolve_epithet(String.t(), keyword()) :: resolution()
  def resolve_epithet(epithet, opts \\ []) when is_binary(epithet) do
    case NameNormalizer.normalize(epithet) |> String.split() do
      [word] ->
        from(n in TaxonName,
          join: t in assoc(n, :taxon),
          where:
            fragment("split_part(?, ' ', 2)", n.normalized_name) == ^word and
              fragment("split_part(?, ' ', 3)", n.normalized_name) == "",
          order_by: [t.id, n.status, n.id],
          select: {t, n}
        )
        |> filter_rank(Keyword.get(opts, :rank, :species))
        |> filter_kingdom(opts[:kingdom])
        |> filter_sensu(opts[:sensu])
        |> resolution()

      _ ->
        :none
    end
  end

  @doc """
  The names among `names` that are names (accepted or synonym) of genus-rank
  taxa, compared normalized, returned as given.
  """
  @spec genus_names([String.t()]) :: [String.t()]
  def genus_names([]), do: []

  def genus_names(names) when is_list(names) do
    normalized = Map.new(names, &{&1, NameNormalizer.normalize(&1)})

    found =
      from(n in TaxonName,
        join: t in assoc(n, :taxon),
        where: t.rank == :genus and n.normalized_name in ^Enum.uniq(Map.values(normalized)),
        distinct: true,
        select: n.normalized_name
      )
      |> Repo.all()
      |> MapSet.new()

    Enum.filter(names, &MapSet.member?(found, normalized[&1]))
  end

  defp filter_rank(query, nil), do: query
  defp filter_rank(query, rank), do: where(query, [_n, t], t.rank == ^rank)

  defp filter_kingdom(query, nil), do: query
  defp filter_kingdom(query, kingdom), do: where(query, [_n, t], t.kingdom == ^kingdom)

  defp filter_sensu(query, nil), do: where(query, [n], is_nil(n.sensu))

  defp filter_sensu(query, sensu) do
    wanted = sensu |> String.trim() |> String.downcase()
    where(query, [n], fragment("lower(trim(?))", n.sensu) == ^wanted)
  end

  # -- helpers -----------------------------------------------------------------

  defp taxon_id(%Taxon{id: id}), do: id
  defp taxon_id(id) when is_integer(id), do: id

  defp row_id(%{id: id}), do: id
  defp row_id(id) when is_integer(id), do: id

  defp unwrap_or_rollback({:ok, value}), do: value
  defp unwrap_or_rollback({:error, changeset}), do: Repo.rollback(changeset)
end
