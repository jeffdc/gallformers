defmodule Gallformers.Import.Replay do
  @moduledoc """
  Replays the replay log (`9449` §5, Task 14) against a database the
  cutover data migration has just filled, so the backscan done on preview
  is not lost.

  The log (`Gallformers.Import.ReplayEntry`, exported from preview with
  `Gallformers.Import.list_replay_entries/0`) is replayed in order, each
  entry by its stable keys (`Gallformers.Import.StableRef`):

    * `:batch_applied` (`%{"package", "batch_id"}`) — the package is
      registered again from its files in the private bucket
      (`import/<key>/`), validated (with the readiness gate unless every
      batch is Gallformers' own) and resolved, if it is not yet; then the
      batch is resolved again and applied. A batch already applied is
      skipped.
    * `:queue_decision` (`%{"package", "batch_id", "kind",
      "statement_ref"}`) — the package is made ready as above, the item is
      found by its batch, kind and statement ref (resolving the package
      again if a later resolution made it), and decided with the logged
      decision, its taxa, Galls and Sources found by their stable
      references. A Host decision that added a synonym or a plant is done
      when no item asks for the Host any more because it resolves to that
      plant (for a WCVP decision, also a plant linked to the record, or
      holding its name at its rank): the synonym or plant, logged and
      replayed before it, resolved it; so is a synonym decision that split
      a name off or moved it, whose tree edits, replayed before it,
      resolve the name. A rename
      proposal's decision (`"kind" => "gall_rename"`,
      no package) is found by its Gall and the name it was decided for
      (`Gallformers.Import.GallRenames.find/2`): replaying the taxonomy
      change before it made the proposal again. A split question's answer
      (`"kind" => "split_inducer"`, no package) is found by its Gall and
      the split taxon (`Gallformers.Import.SplitQuestions.find/2`):
      replaying the split's acceptance asked it again.
    * `:queue_decision_undone` (keyed as the decision's `:queue_decision`)
      — the item is found as the decision's is (resolving the package
      again; none, when no item asks for it any more), reopened if it is
      decided, the reverse tree edits the entry holds made where not done
      already, and the package resolved again (`Gallformers.Import.Undo`).
    * `:synonym_added`, `:plant_added`, `:taxonomy_edit` — the Host-name
      step's and the taxonomy admin's edits, made again on the taxa found
      by name (the newer ops, and WCVP actions logged as the state they
      left: `Gallformers.Import.TaxonomyEdits`), unless the tree holds
      them: the taxon has the synonym in that sense, a taxon of that name
      (or the name a later rename gives it) and rank exists, the taxon
      is under that parent, has that accepted name or common name, or
      holds the flags, authorship, range or WCVP link; a synonym or common
      name to remove is gone, a taxon to delete no longer named. A log of
      the old WCVP bug, which added a genus record as a one-word species
      under a genus of the same name (Stephanomeria), replays to the genus:
      that species is not made, and the edits and decisions naming it go
      to the genus.
    * `:package_denied` (`%{"package"}`) — the package, registered from its
      files if it is not yet, is denied with the logged reason.
    * `:batch_denied` (`%{"package", "batch_id"}`) — the package is made
      ready as for `:batch_applied`, and the batch denied with the logged
      reason.
    * `:source_edit` (`%{"op", "source"}`) — the Source editor's edit, made
      again on the Sources found by title
      (`Gallformers.Import.SourceEdits.from_entry/2`).
    * `:trait_value_added` (`%{"trait", "value"}`), `:trait_term_edit`
      (`%{"op", "trait", "term"}`) and 6611's `:term_mapping_added`
      (`%{"trait", "term"}`) — a change to the Trait vocabulary (a value
      added; a term placed, marked ambiguous or unambiguous or as fitting
      no category, moved or spot-checked), made again unless the database
      holds it (`Gallformers.Import.VocabEdits`). A term a superadmin placed
      settles its uses again (`Gallformers.Import.settle_placed_term/4`).
    * `:fact_edit`, `:fact_edit_removed` (`%{"package", "batch_id",
      "statement_ref", "kind"}`) — a curator's edit on a package's Fact
      before approval, made again (or removed) on the package made ready
      as above (`Gallformers.Import.FactEdits`), before its batch is
      applied.
    * `:fact_note` (`%{"gall", "fact"}`), `:taxon_note` (`%{"taxon",
      "about"}`) — a curator's note on a Fact or on a plant's edit, written
      again unless it is there (`Gallformers.Import.CurationNotes`).
    * `:deletion` (`%{"type", "gall" | "taxon"}`), `:merge` (`%{"type",
      "absorbed", "survivor"}`) — a Gall or taxon deleted, a Gall or plant
      merged, done again unless the record is gone already
      (`Gallformers.Import.Deletion`, `Gallformers.Import.Merge`). A
      same-date conflict a merge brought about (no package) is decided
      again by its Gall and statement ref (`"merge" => true`).
    * `:taxonomic_decision` (`%{"op", "source", "kind", "fact"}`) — a
      Source's taxonomic statement accepted, declined (the payload's
      `"reason"`) or reopened, found by the Source's title and the act's
      natural key by stable references, and decided again unless it is in
      that state already (`Gallformers.Import.TaxonomicDecisions`).
    * `:taxonomic_statement` (`%{"source", "kind", "fact"}`) — a statement
      the taxonomy admin credited to a Source (or Gallformers), recorded
      again on the Source found by title and the act's taxa by stable
      references (`Gallformers.Import.TaxonomyStatements`); its acceptance
      is the `:taxonomic_decision` entry after it. A citation the curator
      entered is a `:source_edit` `"create"` entry before it.
    * `:source_correction` (`%{"source", "gall", "fact"}` for a gall Fact,
      `%{"source", "kind", "fact"}` for a taxonomic act) — a curator's
      correction to a Source's applied Facts, made again on the Fact found
      by those keys, the Source's words found there carried over, unless
      the Source no longer states it (`Gallformers.Import.SourceCorrections`).
      An acceptance in the same step is the `:taxonomic_decision` entry
      after it.
    * `:vocab_requests_decided` — 6611's vocabulary backlog, replaced by
      the superadmin vocabulary page (`d213`); no longer written, and not
      replayed.

  Each step goes through the same functions as on preview, so the log is
  written again as it is replayed. The first entry that cannot be replayed
  stops the replay: `{:error, %{index, entry, reason}}`.

  ## Running it again

  A stopped replay can be fixed and run again from the start: each entry
  whose effect the database holds already is skipped (`:ok`, nothing
  written or logged), told from the data, not from a mark of what was
  replayed, so a replay over a database that holds an edit already skips
  it too. A batch applied, an item decided, a package or batch denied, a
  note, statement, decision, correction, Trait term or Source edit in
  place, a Gall or taxon gone, and the tree edits above. A curator's edit
  on a package's Fact is done once its batch is applied. A taxon renamed
  later in the log is found, by an entry before the rename, through the
  synonym the rename kept or the name the log's renames give it
  (`StableRef.resolve_current_taxon/1`).

  A change the log takes back later (a retraction lifted, a decision
  undone, a common name added and removed) can't be told done from the
  data: run again, both are made again, ending as they ended.
  """
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Catalog.Vocab.TraitTermMapping
  alias Gallformers.Import
  alias Gallformers.Import.Batch
  alias Gallformers.Import.CurationNotes
  alias Gallformers.Import.Deletion
  alias Gallformers.Import.FactEdits
  alias Gallformers.Import.GallRenames
  alias Gallformers.Import.HostDecisions
  alias Gallformers.Import.Merge
  alias Gallformers.Import.Package
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.ReplayEntry
  alias Gallformers.Import.SourceCorrections
  alias Gallformers.Import.SourceEdits
  alias Gallformers.Import.SplitQuestions
  alias Gallformers.Import.StableRef
  alias Gallformers.Import.SynonymDecisions
  alias Gallformers.Import.TaxonomicDecisions
  alias Gallformers.Import.TaxonomyEdits
  alias Gallformers.Import.TaxonomyStatements
  alias Gallformers.Import.TraitTerms
  alias Gallformers.Import.VocabEdits
  alias Gallformers.Taxa

  @typedoc "A log entry: a `ReplayEntry` or a map with its `kind`, `key` and `payload`."
  @type entry :: ReplayEntry.t() | map()

  @doc """
  Replays `entries` in order. Options: `:actor` (default the system actor
  `"replay"`). Returns how many entries were replayed.
  """
  @spec run([entry()], keyword()) ::
          {:ok, non_neg_integer()}
          | {:error, %{index: non_neg_integer(), entry: map(), reason: term()}}
  def run(entries, opts \\ []) do
    actor = Keyword.get_lazy(opts, :actor, fn -> Actor.system("replay") end)

    entries
    |> Enum.map(&normalize/1)
    |> with_later_renames()
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, 0}, fn {entry, index}, {:ok, count} ->
      case replay(actor, entry) do
        :ok ->
          {:cont, {:ok, count + 1}}

        {:error, reason} ->
          entry = Map.delete(entry, :later_renames)
          {:halt, {:error, %{index: index, entry: entry, reason: reason}}}
      end
    end)
  end

  defp normalize(%ReplayEntry{kind: kind, key: key, payload: payload}),
    do: %{kind: kind, key: key, payload: payload || %{}}

  defp normalize(entry) do
    kind = entry[:kind] || entry["kind"]

    %{
      kind: if(is_binary(kind), do: String.to_existing_atom(kind), else: kind),
      key: entry[:key] || entry["key"],
      payload: entry[:payload] || entry["payload"] || %{}
    }
  end

  # -- entries -----------------------------------------------------------------

  defp replay(actor, %{kind: :batch_applied, key: %{"package" => key, "batch_id" => batch_id}}) do
    with {:ok, package} <- ensure_package(actor, key) do
      case Enum.find(Import.list_batches(package), &(&1.producer_batch_id == batch_id)) do
        %Batch{status: :applied} -> :ok
        %Batch{} -> ok(Import.apply_batch_for_replay(actor, package, batch_id))
        nil -> {:error, {:no_batch, batch_id}}
      end
    end
  end

  defp replay(actor, %{
         kind: :queue_decision,
         key: %{"kind" => "gall_rename"} = key,
         payload: %{"decision" => decision}
       }) do
    with {:ok, gall_id} <- StableRef.resolve_gall(key["gall"]) do
      case GallRenames.find(gall_id, key["to"]) do
        nil ->
          {:error, {:no_queue_item, key}}

        %QueueItem{status: :decided} ->
          :ok

        item ->
          with {:ok, decision} <- StableRef.decode_decision(decision) do
            ok(Import.decide_queue_item(actor, item, decision))
          end
      end
    end
  end

  defp replay(actor, %{
         kind: :queue_decision,
         key: %{"kind" => "split_inducer"} = key,
         payload: %{"decision" => decision}
       }) do
    with {:ok, gall_id} <- StableRef.resolve_gall(key["gall"]),
         {:ok, taxon_id} <- StableRef.resolve_taxon(key["taxon"]) do
      case SplitQuestions.find(gall_id, taxon_id) do
        nil ->
          {:error, {:no_queue_item, key}}

        %QueueItem{status: :decided} ->
          :ok

        item ->
          with {:ok, decision} <- StableRef.decode_decision(decision) do
            ok(Import.decide_queue_item(actor, item, decision))
          end
      end
    end
  end

  defp replay(actor, %{
         kind: :queue_decision,
         key: %{"kind" => "same_date_conflict", "merge" => true} = key,
         payload: %{"decision" => decision}
       }) do
    with {:ok, gall_id} <- optional_gall(key["gall"]) do
      case Merge.find_conflict(gall_id, key["statement_ref"]) do
        nil ->
          {:error, {:no_queue_item, key}}

        %QueueItem{status: :decided} ->
          :ok

        item ->
          with {:ok, decision} <- StableRef.decode_decision(decision) do
            ok(Import.decide_queue_item(actor, item, decision))
          end
      end
    end
  end

  defp replay(actor, %{kind: :queue_decision, key: key, payload: %{"decision" => decision}}) do
    decision = bug_genus(decision)

    with {:ok, package} <- ensure_package(actor, key["package"]) do
      case find_item(actor, package, key) do
        {:ok, %QueueItem{status: :decided}} ->
          :ok

        {:ok, item} ->
          with {:ok, decision} <- StableRef.decode_decision(decision) do
            ok(Import.decide_queue_item(actor, item, decision))
          end

        {:error, {:no_queue_item, _key}} = error ->
          if host_done?(package, key, decision) or term_done?(key, decision),
            do: :ok,
            else: error

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  # An undo: its item found as its decision's is (none, when no item asks
  # any more), reopened, the tree edits it logged reversed where not done.
  defp replay(actor, %{kind: :queue_decision_undone, key: key, payload: payload}) do
    with {:ok, item, package} <- undone_item(actor, key) do
      ok(Import.replay_undo(actor, item, package, key, payload))
    end
  end

  # Done when the taxon holds the name in that sense already.
  defp replay(actor, %{kind: :synonym_added, key: %{"taxon" => taxon, "name" => name}} = entry) do
    with {:ok, taxon_id} <- current_taxon(entry, taxon) do
      sensu = entry.payload["sensu"]

      if holds_name?(taxon_id, name, sensu) do
        :ok
      else
        opts = [sensu: sensu, authorship: entry.payload["authorship"]]
        ok(Import.record_synonym_added(actor, taxon_id, name, opts))
      end
    end
  end

  # Done when a plant of that name (or one the log renames it to) and rank
  # is in the tree; or, for the old WCVP bug's species named as its parent
  # genus (`as_genus/1`), once the genus is: it is not made.
  defp replay(actor, %{kind: :plant_added, key: %{"name" => name, "rank" => rank}} = entry) do
    parent = entry.payload["parent"]

    with {:ok, parent_id} <- optional_taxon(entry, parent) do
      if created?(entry, name, rank, "Plantae") or own_genus?(name, rank, parent) do
        :ok
      else
        ok(
          Import.record_plant_added(actor, %{
            name: name,
            rank: rank,
            parent_id: parent_id,
            authorship: entry.payload["authorship"],
            origin: String.to_existing_atom(entry.payload["origin"] || "powo")
          })
        )
      end
    end
  end

  defp replay(actor, %{kind: :taxonomy_edit, key: key, payload: payload} = entry) do
    case edit(entry, key, payload) do
      {:ok, edit} -> ok(Import.record_taxonomy_edit(actor, edit))
      :done -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp replay(actor, %{kind: :package_denied, key: %{"package" => key}, payload: payload}) do
    package =
      case Import.get_package_by_key(key) do
        nil -> Import.register_package(actor, key)
        package -> {:ok, package}
      end

    case package do
      {:ok, %Package{status: :denied}} -> :ok
      {:ok, package} -> ok(Import.deny_package(actor, package, payload["reason"]))
      {:error, reason} -> {:error, reason}
    end
  end

  defp replay(actor, %{
         kind: :batch_denied,
         key: %{"package" => key, "batch_id" => batch_id},
         payload: payload
       }) do
    with {:ok, package} <- ensure_package(actor, key) do
      case Enum.find(Import.list_batches(package), &(&1.producer_batch_id == batch_id)) do
        %Batch{status: :denied} -> :ok
        %Batch{} = batch -> ok(Import.deny_batch(actor, batch, payload["reason"]))
        nil -> {:error, {:no_batch, batch_id}}
      end
    end
  end

  defp replay(actor, %{kind: :source_edit, key: key, payload: payload}) do
    case SourceEdits.from_entry(key, payload) do
      {:ok, edit} -> ok(Import.record_source_edit(actor, edit))
      :done -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # A superadmin's placement settles the term's uses again (`Import.place_term/4`),
  # under its one category or each of several.
  defp replay(actor, %{
         kind: :trait_term_edit,
         key: %{"op" => "place", "trait" => trait, "term" => term} = key,
         payload: %{"placed_by" => "superadmin"} = payload
       }) do
    with :ok <- VocabEdits.replay(actor, :trait_term_edit, key, payload) do
      case VocabEdits.logged_categories_of(payload) do
        {:ok, categories} -> ok(Import.settle_placed_term(actor, trait, term, categories))
        :error -> :ok
      end
    end
  end

  defp replay(actor, %{kind: kind, key: key, payload: payload})
       when kind in [:trait_value_added, :trait_term_edit, :term_mapping_added],
       do: VocabEdits.replay(actor, kind, key, payload)

  defp replay(actor, %{kind: kind, key: %{"package" => key} = entry_key, payload: payload})
       when kind in [:fact_edit, :fact_edit_removed] do
    with {:ok, package} <- ensure_package(actor, key),
         do: FactEdits.replay(actor, package, kind, entry_key, payload)
  end

  defp replay(actor, %{kind: kind, key: key, payload: payload})
       when kind in [:fact_note, :taxon_note],
       do: CurationNotes.replay(actor, kind, key, payload)

  defp replay(actor, %{kind: :deletion, key: key}) do
    case Deletion.decode(key) do
      {:ok, subject} -> ok(Import.record_deletion(actor, subject))
      :done -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp replay(actor, %{kind: :merge, key: key}) do
    case Merge.decode(key) do
      {:ok, spec} -> ok(Import.record_merge(actor, spec))
      :done -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp replay(actor, %{kind: :taxonomic_decision, key: key, payload: payload}),
    do: TaxonomicDecisions.replay(actor, key, payload)

  defp replay(actor, %{kind: :taxonomic_statement, key: key, payload: payload}),
    do: TaxonomyStatements.replay(actor, key, payload)

  defp replay(actor, %{kind: :source_correction, key: key, payload: payload}),
    do: SourceCorrections.replay(actor, key, payload)

  defp replay(_actor, entry),
    do: {:error, {:unknown_entry, Map.delete(entry, :later_renames)}}

  # The edit an entry stands for, or `:done` when the tree holds it already.
  defp edit(entry, %{"op" => "place", "taxon" => taxon}, payload) do
    with {:ok, taxon_id} <- current_taxon(entry, taxon),
         {:ok, parent_id} <- optional_taxon(entry, payload["parent"]) do
      if Taxa.get_taxon!(taxon_id).parent_id == parent_id,
        do: :done,
        else: {:ok, {:place, taxon_id, parent_id}}
    end
  end

  # Renamed already when no taxon has the old name but one has the new
  # name (or a name the log renames it to later).
  defp edit(entry, %{"op" => "rename", "taxon" => taxon}, %{"name" => name}) do
    case StableRef.resolve_taxon(taxon) do
      {:ok, taxon_id} ->
        if Taxa.accepted_name(taxon_id) == String.trim(name),
          do: :done,
          else: {:ok, {:rename, taxon_id, name}}

      {:error, {:taxon_not_found, _}} = error ->
        if match?({:ok, _}, current_taxon(entry, %{taxon | "name" => name})),
          do: :done,
          else: error

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp edit(entry, %{"op" => "add_common_name", "taxon" => taxon}, %{"name" => name}) do
    with {:ok, taxon_id} <- current_taxon(entry, taxon) do
      held = for common <- Taxa.list_common_names(taxon_id), do: String.downcase(common.name)

      if String.downcase(String.trim(name)) in held,
        do: :done,
        else: {:ok, {:add_common_name, taxon_id, name}}
    end
  end

  defp edit(entry, %{"op" => "create_taxon", "name" => name, "rank" => rank}, payload) do
    with {:ok, parent_id} <- optional_taxon(entry, payload["parent"]) do
      kingdom = payload["kingdom"] || (parent_id && Taxa.get_taxon!(parent_id).kingdom)

      if created?(entry, name, rank, kingdom) do
        :done
      else
        {:ok,
         {:create_taxon,
          %{
            name: name,
            rank: rank,
            parent_id: parent_id,
            kingdom: payload["kingdom"],
            origin: String.to_existing_atom(payload["origin"] || "curated")
          }}}
      end
    end
  end

  defp edit(entry, key, payload) do
    case TaxonomyEdits.decode(key, payload, &current_taxon(entry, &1)) do
      :unknown -> {:error, {:unknown_edit, key}}
      decoded -> decoded
    end
  end

  # A taxon created already: one of that rank (and kingdom) has the name,
  # or the name the log renames it to later, as its accepted name.
  defp created?(entry, name, rank, kingdom) do
    names = [name | List.wrap(later_name(entry, name, rank))]
    ref = %{"rank" => rank, "kingdom" => kingdom}

    Enum.any?(names, fn name ->
      case StableRef.resolve_taxon(Map.put(ref, "name", name)) do
        {:ok, _id} -> true
        {:error, {:taxon_ambiguous, _ref}} -> true
        {:error, _reason} -> false
      end
    end)
  end

  # The taxon a stable reference names now. On a log replayed again, a
  # taxon renamed later in the log is found by its old name: through the
  # synonym the rename kept (`StableRef.resolve_current_taxon/1`), or by the
  # name the log's later renames give it. The old WCVP bug's species, not
  # made, is its genus (`as_genus/1`).
  defp current_taxon(entry, ref) do
    with {:error, {:taxon_not_found, _}} = error <- named_taxon(entry, ref) do
      case as_genus(ref) do
        nil -> error
        genus -> with({:error, _} <- named_taxon(entry, genus), do: error)
      end
    end
  end

  defp named_taxon(entry, ref) do
    with {:error, {:taxon_not_found, _}} = error <- StableRef.resolve_current_taxon(ref) do
      case later_name(entry, ref["name"], ref["rank"]) do
        nil -> error
        name -> StableRef.resolve_taxon(%{ref | "name" => name})
      end
    end
  end

  # The old WCVP bug (Stephanomeria): a WCVP genus record was
  # added from the Host step or the taxonomy admin as a species of the
  # genus's own name, under a genus of that name made for it, and its range
  # and link went on the species. A species is named by two words at
  # least, so a one-word species is that bug's: its genus, where the log
  # names it (the species is not made, `own_genus?/3`).
  defp as_genus(%{"rank" => "species", "name" => name} = ref) when is_binary(name) do
    if match?([_], String.split(name)), do: %{ref | "rank" => "genus"}
  end

  defp as_genus(_ref), do: nil

  # A plant added as a species of its parent genus's own name: the bug's.
  defp own_genus?(name, "species", %{"name" => name, "rank" => "genus"}),
    do: as_genus(%{"rank" => "species", "name" => name}) != nil

  defp own_genus?(_name, _rank, _parent), do: false

  # The name the log's renames after `entry` (`with_later_renames/1`) give
  # a taxon of `rank` named `name`, or nil if none renames it.
  defp later_name(entry, name, rank) do
    renamed =
      entry
      |> Map.get(:later_renames, [])
      |> Enum.reduce(name, fn {old, old_rank, new}, current ->
        if old == current and old_rank == rank, do: new, else: current
      end)

    if renamed != name, do: renamed
  end

  # Each entry with the taxonomy admin's renames logged after it, in order
  # (`{old name, rank, new name}`); a rename's own counts as after it.
  defp with_later_renames(entries) do
    {entries, _renames} =
      List.foldr(entries, {[], []}, fn entry, {done, renames} ->
        renames =
          case entry do
            %{
              kind: :taxonomy_edit,
              key: %{"op" => "rename", "taxon" => %{"name" => old, "rank" => rank}},
              payload: %{"name" => new}
            } ->
              [{old, rank, String.trim(new)} | renames]

            _entry ->
              renames
          end

        {[Map.put(entry, :later_renames, renames) | done], renames}
      end)

    entries
  end

  # Whether the taxon holds `name` (accepted or synonym) in the sense
  # `sensu` (nil: its own), as the names' unique index counts them.
  defp holds_name?(taxon_id, name, sensu) do
    sensu = if is_binary(sensu) and String.trim(sensu) != "", do: sensu

    case Taxa.resolve_name(name, sensu: sensu) do
      {:ok, taxon} -> taxon.id == taxon_id
      {:ambiguous, taxa} -> Enum.any?(taxa, &(&1.id == taxon_id))
      :none -> false
    end
  end

  defp optional_taxon(_entry, nil), do: {:ok, nil}
  defp optional_taxon(entry, ref), do: current_taxon(entry, ref)

  defp optional_gall(nil), do: {:ok, nil}
  defp optional_gall(ref), do: StableRef.resolve_gall(ref)

  # -- packages and queue items ------------------------------------------------

  # The package with `key`, registered, validated and resolved from its
  # files if it is not yet.
  defp ensure_package(actor, key) do
    package =
      case Import.get_package_by_key(key) do
        nil -> Import.register_package(actor, key)
        package -> {:ok, package}
      end

    with {:ok, package} <- package, do: ready(actor, package)
  end

  defp ready(actor, %Package{status: :received} = package) do
    with {:ok, files} <- Import.read_package_files(package),
         {:ok, package} <-
           Import.validate_package(actor, package, review: Import.review_required?(files)) do
      ready(actor, package)
    end
  end

  defp ready(_actor, %Package{status: :invalid} = package),
    do: {:error, {:invalid_package, package.key, package.problems}}

  defp ready(actor, %Package{status: status} = package) when status in [:validated, :resolving],
    do: Import.resolve_package(actor, package)

  defp ready(_actor, package), do: {:ok, package}

  # The queue item by its batch, kind and statement ref; resolving the
  # package again first if a later resolution made it.
  defp find_item(actor, package, key) do
    with nil <- lookup_item(package, key),
         {:ok, package} <- resolve_again(actor, package),
         nil <- lookup_item(package, key) do
      {:error, {:no_queue_item, key}}
    else
      %QueueItem{} = item -> {:ok, item}
      {:error, reason} -> {:error, reason}
    end
  end

  defp resolve_again(actor, %Package{status: :awaiting_review} = package),
    do: Import.resolve_package(actor, package)

  defp resolve_again(_actor, package), do: {:ok, package}

  # A name both batches declare is queued once, on one batch's item, which
  # names the other batch's ref in `subject["also"]` (`Queue.share_names/1`).
  # A decision logged on the other copy (or before names were shared) is
  # found on that item, whatever its kind.
  defp lookup_item(package, key) do
    batch =
      key["batch_id"] &&
        Enum.find(Import.list_batches(package), &(&1.producer_batch_id == key["batch_id"]))

    batch_id = batch && batch.id
    items = Import.list_queue_items(package, status: :all)
    kind = String.to_existing_atom(key["kind"])

    ref = TraitTerms.current_ref(key["statement_ref"])

    Enum.find(items, fn item ->
      item.kind == kind and item.batch_id == batch_id and item.statement_ref == ref
    end) ||
      (batch &&
         Enum.find(items, fn item ->
           %{"batch" => batch.file, "ref" => key["statement_ref"]} in List.wrap(
             item.subject["also"]
           )
         end))
  end

  # A Host decision that added a synonym or a plant is done when the Host
  # resolves to its plant without it: the synonym or plant, replayed before
  # it (`Gallformers.Import.HostDecisions`), resolved the name when the
  # package was resolved, so no item asks for it. So is a synonym decision
  # that split a name off or moved it (`Gallformers.Import.SynonymDecisions`):
  # its tree edits, replayed before it, resolve the name to its taxon.
  #
  # A WCVP decision's plant is also any the tree links to the record, or
  # holds by its name at its rank (`HostDecisions.plant_ids/1`): the plant a
  # log of the old WCVP bug names is its genus.
  defp host_done?(package, key, decision) do
    with true <- HostDecisions.adds?(decision) or SynonymDecisions.changes_tree?(decision),
         [_ | _] = taxon_ids <- decided_taxa(decision) do
      Enum.any?(Import.list_batches(package), fn batch ->
        batch.producer_batch_id == key["batch_id"] and
          Enum.any?(
            Import.list_statements(batch),
            &(&1.kind == :taxon and &1.ref == key["statement_ref"] and &1.resolution == :resolved and
                &1.taxon_id in taxon_ids)
          )
      end)
    else
      _ -> false
    end
  end

  defp decided_taxa(decision) do
    decoded =
      case StableRef.decode_decision(decision) do
        {:ok, %{"taxon_id" => taxon_id}} -> [taxon_id]
        _ -> []
      end

    wcvp = if is_binary(decision["wcvp_id"]), do: HostDecisions.plant_ids(decision["wcvp_id"])
    decoded ++ List.wrap(wcvp)
  end

  # A decision on the old WCVP bug's species (`as_genus/1`), not made: on
  # its genus.
  defp bug_genus(%{"taxon" => %{} = ref} = decision) do
    with {:error, {:taxon_not_found, _}} <- StableRef.resolve_taxon(ref),
         %{} = genus <- as_genus(ref) do
      %{decision | "taxon" => genus}
    else
      _ -> decision
    end
  end

  defp bug_genus(decision), do: decision

  # A trait term's placement the vocabulary already holds (its mapping
  # replayed before the decision): the replayed import asks no question,
  # so the decision is done. A long term's ref is hashed and can't be read
  # back, so it stays a missing question.
  defp term_done?(%{"kind" => "trait_term", "statement_ref" => "u:" <> rest}, %{
         "place" => place
       }) do
    with [trait, term] <- String.split(rest, ":", parts: 2),
         %{status: :placed, categories: categories} <- Catalog.get_term(trait, term) do
      TraitTermMapping.same_categories?(categories, place)
    else
      _ -> false
    end
  end

  defp term_done?(_key, _decision), do: false

  # The item an undo entry's key names, as its decision's entry finds it,
  # with its package (nil for a question of no package).
  defp undone_item(_actor, %{"kind" => "gall_rename"} = key) do
    with {:ok, gall_id} <- StableRef.resolve_gall(key["gall"]),
         do: {:ok, GallRenames.find(gall_id, key["to"]), nil}
  end

  defp undone_item(_actor, %{"kind" => "split_inducer"} = key) do
    with {:ok, gall_id} <- StableRef.resolve_gall(key["gall"]),
         {:ok, taxon_id} <- StableRef.resolve_taxon(key["taxon"]),
         do: {:ok, SplitQuestions.find(gall_id, taxon_id), nil}
  end

  defp undone_item(_actor, %{"kind" => "same_date_conflict", "merge" => true} = key) do
    with {:ok, gall_id} <- optional_gall(key["gall"]),
         do: {:ok, Merge.find_conflict(gall_id, key["statement_ref"]), nil}
  end

  defp undone_item(actor, key) do
    with {:ok, package} <- ensure_package(actor, key["package"]) do
      case find_item(actor, package, key) do
        {:ok, item} -> {:ok, item, package}
        {:error, {:no_queue_item, _key}} -> {:ok, nil, Import.get_package!(package.id)}
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp ok({:ok, _value}), do: :ok
  defp ok({:error, reason}), do: {:error, reason}
end
