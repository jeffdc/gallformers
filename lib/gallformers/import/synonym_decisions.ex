defmodule Gallformers.Import.SynonymDecisions do
  @moduledoc """
  Synonymy changed from the review page (matter `d213`, Task 9). On a
  synonym question — a `:taxonomy_disagreement` on a taxon ref: the tree
  holds the Source's name as a synonym of X, and the Source treats it as
  valid — "the Source is right: change the tree" is decided

    * `%{"split" => true}` — the name becomes a species of its own again:
      its synonym is removed from X (`{:remove_synonym, name}`) and a
      species of that name created under its genus (`{:create_taxon, attrs}`,
      the tree's spelling, X's kingdom). The genus is the name's first word,
      held by the tree under its accepted name; when it is not, the
      decision is refused (add the genus first).
    * `%{"synonym_of" => taxon_id}` — the name becomes a synonym of another
      taxon: removed from X, added to it
      (`Gallformers.Import.record_synonym_added/4`).

  Both are tree edits for every Source, through
  `Gallformers.Import.record_taxonomy_edit/2` and the Host-name step's
  recorder, so they are in the replay log before the decision. The decision
  is stored with the taxon it resolved to (`"taxon_id"`): the item is
  decided, and the batch's statements of the name resolve to that taxon
  (`Gallformers.Import.Queue.apply_decision/2`). The Facts already on X
  stay.

  Replaying the decision changes nothing again: a decision carrying its
  `"taxon_id"` is done (the edits, replayed before it, made the change). A
  split whose name, once replayed, resolves on its own needs no item; the
  replay finds its statement resolved to the taxon (`done?/1`).
  """
  alias Gallformers.Audit.Actor
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer

  @doc "Whether `item` is a synonym question."
  @spec synonym?(QueueItem.t()) :: boolean()
  def synonym?(%QueueItem{kind: :taxonomy_disagreement, statement_ref: "t" <> _}), do: true
  def synonym?(_item), do: false

  @doc "Whether `decision` changes the tree's synonymy (a split or a move)."
  @spec changes_tree?(map()) :: boolean()
  def changes_tree?(decision),
    do: decision["split"] == true or Map.has_key?(decision, "synonym_of")

  # -- validating --------------------------------------------------------------

  @doc """
  Checks the choice of a synonym decision (without its note): `:ok`,
  `{:error, message}`, or `:other` when it is neither a split nor a move
  (the queue checks those).
  """
  @spec check(QueueItem.t(), map()) :: :ok | {:error, String.t()} | :other
  def check(item, %{"split" => true} = choice) when map_size(choice) == 1 do
    with {:ok, held} <- held(item), {:ok, _genus} <- genus(item, held), do: :ok
  end

  def check(item, %{"split" => true, "taxon_id" => id} = choice) when map_size(choice) == 2 do
    taxon = is_integer(id) && Taxa.get_taxon(id)

    cond do
      not is_struct(taxon) -> {:error, "taxon_id must be a taxon"}
      names?(taxon, name(item)) -> :ok
      true -> {:error, "taxon_id must be the taxon the name was made"}
    end
  end

  def check(item, %{"synonym_of" => id} = choice) when map_size(choice) == 1 do
    with :ok <- taxon(id), {:ok, held} <- held(item) do
      if Enum.any?(held, &(&1.id == id)),
        do: {:error, "synonym_of must be another taxon than the one holding the name"},
        else: :ok
    end
  end

  def check(_item, %{"synonym_of" => id, "taxon_id" => id} = choice)
      when map_size(choice) == 2,
      do: taxon(id)

  def check(_item, choice) do
    if Map.has_key?(choice, "split") or Map.has_key?(choice, "synonym_of"),
      do: {:error, "split is true, or synonym_of a taxon, alone"},
      else: :other
  end

  defp taxon(id) do
    if is_integer(id) and Taxa.get_taxon(id) != nil,
      do: :ok,
      else: {:error, "synonym_of must be a taxon"}
  end

  # The taxa holding the Source's name as a synonym (no sensu), of its rank.
  defp held(item) do
    name = name(item)

    found =
      case Taxa.resolve_name(name, rank: rank(item)) do
        {:ok, taxon} -> [taxon]
        {:ambiguous, taxa} -> taxa
        :none -> []
      end

    case Enum.filter(found, &(&1.matched_name.status == :synonym)) do
      [] -> {:error, "Gallformers doesn't hold “#{name}” as a synonym"}
      held -> {:ok, held}
    end
  end

  # The genus a split species goes under: the first word of the tree's
  # spelling, held under its accepted name.
  defp genus(item, [held | _]) do
    if rank(item) != :species do
      {:error, "only a species name can be made a species of its own"}
    else
      [genus | _] = String.split(held.matched_name.name)

      case Taxa.resolve_name(genus, rank: :genus, kingdom: held.kingdom) do
        {:ok, %{matched_name: %{status: :accepted}} = taxon} ->
          {:ok, taxon}

        _ ->
          {:error, "the tree doesn't hold the genus #{genus}: add it first, then split the name"}
      end
    end
  end

  defp name(%QueueItem{subject: subject}),
    do: subject["name_reading"] || subject["name_as_written"] || ""

  defp rank(%QueueItem{subject: subject}) do
    case subject["rank"] do
      rank when is_binary(rank) -> String.to_existing_atom(rank)
      _ -> :species
    end
  end

  defp names?(taxon, name) do
    normalized = NameNormalizer.normalize(name)
    Enum.any?(taxon.names, &(&1.normalized_name == normalized and is_nil(&1.sensu)))
  end

  # -- carrying out ------------------------------------------------------------

  @doc """
  Makes the tree edits a valid split or move on `item` needs, inside the
  caller's transaction, each in the replay log. Returns the decision to
  store, with the taxon it resolved to (`"taxon_id"`); a decision that
  carries one is done already.
  """
  @spec carry_out(Actor.t(), QueueItem.t(), map()) :: {:ok, map()} | {:error, term()}
  def carry_out(_actor, _item, %{"taxon_id" => _} = decision), do: {:ok, decision}

  def carry_out(actor, item, %{"split" => true} = decision) do
    with {:ok, [first | _] = held} <- held(item),
         {:ok, genus} <- genus(item, held),
         :ok <- remove(actor, held),
         {:ok, taxon} <-
           Import.record_taxonomy_edit(
             actor,
             {:create_taxon,
              %{
                name: first.matched_name.name,
                rank: :species,
                parent_id: genus.id,
                kingdom: first.kingdom,
                origin: :curated
              }}
           ) do
      {:ok, Map.put(decision, "taxon_id", taxon.id)}
    end
  end

  def carry_out(actor, item, %{"synonym_of" => id} = decision) do
    with {:ok, [first | _] = held} <- held(item),
         :ok <- remove(actor, held),
         {:ok, _name} <- Import.record_synonym_added(actor, id, first.matched_name.name) do
      {:ok, Map.put(decision, "taxon_id", id)}
    end
  end

  def carry_out(_actor, _item, decision), do: {:ok, decision}

  defp remove(actor, held) do
    Enum.reduce_while(held, :ok, fn taxon, :ok ->
      case Import.record_taxonomy_edit(actor, {:remove_synonym, taxon.matched_name}) do
        {:ok, _} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end
end
