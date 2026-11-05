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
      plant: the synonym or plant, logged and replayed before it, resolved
      it; so is a synonym decision that split a name off or moved it,
      whose tree edits, replayed before it, resolve the name. A rename
      proposal's decision (`"kind" => "gall_rename"`,
      no package) is found by its Gall and the name it was decided for
      (`Gallformers.Import.GallRenames.find/2`): replaying the taxonomy
      change before it made the proposal again.
    * `:synonym_added`, `:plant_added`, `:taxonomy_edit` — the Host-name
      step's and the taxonomy admin's edits, made again on the taxa found
      by name (the newer ops, and WCVP actions logged as the state they
      left: `Gallformers.Import.TaxonomyEdits`).
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
    * `:vocab_requests_decided` — 6611's vocabulary backlog, replaced by
      the superadmin vocabulary page (`d213`); no longer written, and not
      replayed.

  Each step goes through the same functions as on preview, so the log is
  written again as it is replayed. The first entry that cannot be replayed
  stops the replay: `{:error, %{index, entry, reason}}`. Entries already
  done (a batch applied, an item decided) are skipped, so a stopped replay
  can be fixed and run again.
  """
  alias Gallformers.Audit.Actor
  alias Gallformers.Import
  alias Gallformers.Import.Batch
  alias Gallformers.Import.FactEdits
  alias Gallformers.Import.GallRenames
  alias Gallformers.Import.HostDecisions
  alias Gallformers.Import.Package
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.ReplayEntry
  alias Gallformers.Import.SourceEdits
  alias Gallformers.Import.StableRef
  alias Gallformers.Import.SynonymDecisions
  alias Gallformers.Import.TaxonomyEdits
  alias Gallformers.Import.VocabEdits

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
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, 0}, fn {entry, index}, {:ok, count} ->
      case replay(actor, entry) do
        :ok -> {:cont, {:ok, count + 1}}
        {:error, reason} -> {:halt, {:error, %{index: index, entry: entry, reason: reason}}}
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

  defp replay(actor, %{kind: :queue_decision, key: key, payload: %{"decision" => decision}}) do
    with {:ok, package} <- ensure_package(actor, key["package"]) do
      case find_item(actor, package, key) do
        {:ok, %QueueItem{status: :decided}} ->
          :ok

        {:ok, item} ->
          with {:ok, decision} <- StableRef.decode_decision(decision) do
            ok(Import.decide_queue_item(actor, item, decision))
          end

        {:error, {:no_queue_item, _key}} = error ->
          if host_done?(package, key, decision), do: :ok, else: error

        {:error, reason} ->
          {:error, reason}
      end
    end
  end

  defp replay(actor, %{kind: :synonym_added, key: %{"taxon" => taxon, "name" => name}} = entry) do
    with {:ok, taxon_id} <- StableRef.resolve_taxon(taxon) do
      opts = [sensu: entry.payload["sensu"], authorship: entry.payload["authorship"]]
      ok(Import.record_synonym_added(actor, taxon_id, name, opts))
    end
  end

  defp replay(actor, %{kind: :plant_added, key: %{"name" => name, "rank" => rank}} = entry) do
    with {:ok, parent_id} <- optional_taxon(entry.payload["parent"]) do
      ok(
        Import.record_plant_added(actor, %{
          name: name,
          rank: rank,
          parent_id: parent_id,
          authorship: entry.payload["authorship"]
        })
      )
    end
  end

  defp replay(actor, %{kind: :taxonomy_edit, key: key, payload: payload}) do
    with {:ok, edit} <- edit(key, payload) do
      ok(Import.record_taxonomy_edit(actor, edit))
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

  defp replay(_actor, entry), do: {:error, {:unknown_entry, entry}}

  defp edit(%{"op" => "place", "taxon" => taxon}, payload) do
    with {:ok, taxon_id} <- StableRef.resolve_taxon(taxon),
         {:ok, parent_id} <- optional_taxon(payload["parent"]) do
      {:ok, {:place, taxon_id, parent_id}}
    end
  end

  defp edit(%{"op" => "rename", "taxon" => taxon}, %{"name" => name}) do
    with {:ok, taxon_id} <- StableRef.resolve_taxon(taxon), do: {:ok, {:rename, taxon_id, name}}
  end

  defp edit(%{"op" => "add_common_name", "taxon" => taxon}, %{"name" => name}) do
    with {:ok, taxon_id} <- StableRef.resolve_taxon(taxon),
         do: {:ok, {:add_common_name, taxon_id, name}}
  end

  defp edit(%{"op" => "create_taxon", "name" => name, "rank" => rank}, payload) do
    with {:ok, parent_id} <- optional_taxon(payload["parent"]) do
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

  defp edit(key, payload) do
    case TaxonomyEdits.decode(key, payload) do
      :unknown -> {:error, {:unknown_edit, key}}
      decoded -> decoded
    end
  end

  defp optional_taxon(nil), do: {:ok, nil}
  defp optional_taxon(ref), do: StableRef.resolve_taxon(ref)

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

    Enum.find(items, fn item ->
      item.kind == kind and item.batch_id == batch_id and
        item.statement_ref == key["statement_ref"]
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
  defp host_done?(package, key, decision) do
    with true <- HostDecisions.adds?(decision) or SynonymDecisions.changes_tree?(decision),
         {:ok, %{"taxon_id" => taxon_id}} <- StableRef.decode_decision(decision) do
      Enum.any?(Import.list_batches(package), fn batch ->
        batch.producer_batch_id == key["batch_id"] and
          Enum.any?(
            Import.list_statements(batch),
            &(&1.kind == :taxon and &1.ref == key["statement_ref"] and &1.resolution == :resolved and
                &1.taxon_id == taxon_id)
          )
      end)
    else
      _ -> false
    end
  end

  defp ok({:ok, _value}), do: :ok
  defp ok({:error, reason}), do: {:error, reason}
end
