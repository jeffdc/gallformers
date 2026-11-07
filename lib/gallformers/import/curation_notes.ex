defmodule Gallformers.Import.CurationNotes do
  @moduledoc """
  Curators' notes that are data (matter `ec2c`), each written and recorded
  in the replay log in one audited transaction, so a note made on preview
  is made again after the cutover data migration
  (`Gallformers.Import.Replay`):

    * a note on a Fact (`Gallformers.Catalog.add_fact_note/4`) — kind
      `:fact_note`, keyed by the Gall's stable reference and the Fact's
      stable key (`fact_key/1`), payload the text and its author's name;
    * a "based on" note on a plant's edit (`Gallformers.Taxa.add_taxon_note/5`)
      — kind `:taxon_note`, keyed by the taxon's stable reference and what
      the edit changed (`"about"`), payload the same.

  Replaying writes the note as its author wrote it, unless the Fact or
  taxon already has that note (same text and author): a replayed log is
  replayed once.

  The Fact's stable key names it as the Gall page does, with stable
  references: `%{"kind" => "inducer" | "host", "taxon"}`,
  `%{"kind" => "trait", "trait", "value"}`, `%{"kind" => "alias", "name"}`,
  `%{"kind" => "range", "adjustment", "place"}` and
  `%{"kind" => "occurrence", "place"}` (places by code).
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Audit
  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Catalog.FactNote
  alias Gallformers.Import.ReplayLog
  alias Gallformers.Import.StableRef
  alias Gallformers.Places
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.TaxonNote

  @doc """
  Notes the Fact about Gall `gall_id` that `key` names
  (`Gallformers.Catalog.find_gall_fact/2`) and logs it.
  `{:error, :no_fact}` when there is no such Fact.
  """
  @spec record_fact_note(Actor.t(), integer(), Catalog.gall_fact_key(), String.t(), keyword()) ::
          {:ok, FactNote.t()} | {:error, term()}
  def record_fact_note(%Actor{} = actor, gall_id, key, text, opts \\ []) do
    Audit.transaction(actor, "import.record_fact_note", fn ->
      fact_id = fact_id!(gall_id, key)
      note = actor |> Catalog.add_fact_note(fact_id, text, opts) |> unwrap_or_rollback()

      ReplayLog.append!(
        :fact_note,
        %{"gall" => StableRef.gall(gall_id), "fact" => fact_key(key)},
        %{"text" => note.text, "author" => note.author_name}
      )

      note
    end)
  end

  @doc "Notes taxon `taxon_id`'s edit of `about` and logs it."
  @spec record_taxon_note(Actor.t(), integer(), String.t(), String.t(), keyword()) ::
          {:ok, TaxonNote.t()} | {:error, term()}
  def record_taxon_note(%Actor{} = actor, taxon_id, about, text, opts \\ []) do
    Audit.transaction(actor, "import.record_taxon_note", fn ->
      key = %{"taxon" => StableRef.taxon(taxon_id), "about" => about}
      note = actor |> Taxa.add_taxon_note(taxon_id, about, text, opts) |> unwrap_or_rollback()
      ReplayLog.append!(:taxon_note, key, %{"text" => note.text, "author" => note.author_name})
      note
    end)
  end

  @doc "Replays a logged note (`:fact_note` or `:taxon_note`)."
  @spec replay(Actor.t(), :fact_note | :taxon_note, map(), map()) :: :ok | {:error, term()}
  def replay(actor, :fact_note, %{"gall" => gall, "fact" => fact}, payload) do
    with {:ok, gall_id} <- StableRef.resolve_gall(gall),
         {:ok, key} <- decode_fact_key(fact),
         {:ok, fact_id} when is_integer(fact_id) <- Catalog.find_gall_fact(gall_id, key) do
      if Repo.exists?(
           from(n in FactNote,
             where:
               n.fact_id == ^fact_id and n.text == ^payload["text"] and
                 n.author_name == ^payload["author"]
           )
         ),
         do: :ok,
         else: ok(record_fact_note(actor, gall_id, key, payload["text"], author(payload)))
    else
      {:ok, nil} -> {:error, {:no_fact, fact}}
      {:error, reason} -> {:error, reason}
    end
  end

  def replay(actor, :taxon_note, %{"taxon" => taxon, "about" => about}, payload) do
    with {:ok, taxon_id} <- StableRef.resolve_current_taxon(taxon) do
      if Repo.exists?(
           from(n in TaxonNote,
             where:
               n.taxon_id == ^taxon_id and n.about == ^about and n.text == ^payload["text"] and
                 n.author_name == ^payload["author"]
           )
         ),
         do: :ok,
         else: ok(record_taxon_note(actor, taxon_id, about, payload["text"], author(payload)))
    end
  end

  defp author(%{"author" => name}) when is_binary(name), do: [author_name: name]
  defp author(_payload), do: []

  defp fact_id!(gall_id, key) do
    case Catalog.find_gall_fact(gall_id, key) do
      {:ok, fact_id} when is_integer(fact_id) -> fact_id
      {:ok, nil} -> Repo.rollback(:no_fact)
      {:error, reason} -> Repo.rollback(reason)
    end
  end

  @doc "The stable key of the Fact a Gall page key names."
  @spec fact_key(Catalog.gall_fact_key()) :: map()
  def fact_key({role, taxon_id}) when role in [:inducer, :host],
    do: %{"kind" => Atom.to_string(role), "taxon" => StableRef.taxon(taxon_id)}

  def fact_key({:trait, trait, value}),
    do: %{"kind" => "trait", "trait" => trait, "value" => value}

  def fact_key({:alias, name}), do: %{"kind" => "alias", "name" => name}

  def fact_key({:range, adjustment, place_id}),
    do: %{
      "kind" => "range",
      "adjustment" => Atom.to_string(adjustment),
      "place" => Places.get_place!(place_id).code
    }

  def fact_key({:occurrence, place_id}),
    do: %{"kind" => "occurrence", "place" => Places.get_place!(place_id).code}

  @doc "The Gall page key a stable key (`fact_key/1`) names, its taxon and place found again."
  @spec decode_fact_key(map()) :: {:ok, Catalog.gall_fact_key()} | {:error, term()}
  def decode_fact_key(%{"kind" => role, "taxon" => taxon}) when role in ["inducer", "host"] do
    with {:ok, id} <- StableRef.resolve_current_taxon(taxon),
         do: {:ok, {String.to_existing_atom(role), id}}
  end

  def decode_fact_key(%{"kind" => "trait", "trait" => trait, "value" => value}),
    do: {:ok, {:trait, trait, value}}

  def decode_fact_key(%{"kind" => "alias", "name" => name}), do: {:ok, {:alias, name}}

  def decode_fact_key(%{"kind" => "range", "adjustment" => adjustment, "place" => code})
      when adjustment in ["exclude", "only"] do
    with {:ok, place_id} <- place_id(code),
         do: {:ok, {:range, String.to_existing_atom(adjustment), place_id}}
  end

  def decode_fact_key(%{"kind" => "occurrence", "place" => code}) do
    with {:ok, place_id} <- place_id(code), do: {:ok, {:occurrence, place_id}}
  end

  def decode_fact_key(key), do: {:error, {:unknown_fact_key, key}}

  defp place_id(code) do
    case Places.get_place_by_code(code) do
      %{id: id} -> {:ok, id}
      nil -> {:error, {:no_place, code}}
    end
  end

  defp ok({:ok, _value}), do: :ok
  defp ok({:error, reason}), do: {:error, reason}

  defp unwrap_or_rollback({:ok, value}), do: value
  defp unwrap_or_rollback({:error, reason}), do: Repo.rollback(reason)
end
