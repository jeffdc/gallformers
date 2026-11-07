defmodule Gallformers.Import.HostDecisions do
  @moduledoc """
  Decisions on a Host name (`6611` Task 3; the Host-name step, `d585`): an
  `:unresolved_host` item, or an `:ambiguous_match` whose name the batch
  uses as a Host. Besides a plant (`%{"taxon_id" => id}`) or leaving the
  Host out (`%{"skip" => true}`):

    * `%{"taxon_id" => id, "add_synonym" => true}` — the plant `id`, with
      the Source's spelling added as its synonym, so the next Source that
      spells it so resolves on its own.
    * `%{"wcvp_id" => id}` — the plant of WCVP record `id`: its accepted
      record (the record itself when accepted). The plant the tree links to
      that record, or holds by its name at the record's rank, when there is
      one; else it is added as the taxonomy admin adds one
      (`Gallformers.Import.record_plant_added_from_wcvp/3`: at the record's
      rank, a genus under its WCVP family, a species or below under its
      WCVP genus and family, its native range, its WCVP link). A record at
      a rank Gallformers has none for (WCVP's Subvariety) is refused.
      The Source's spelling is added as its synonym when it differs. The
      decision is stored with the plant it resolved to, `"taxon_id"`.

  A Host the Source names only by a common name (`subject["common_name"]`,
  "the black oak") takes no synonym: a common name is not a scientific
  name. `add_synonym` is refused for it, and a WCVP plant is added without
  one; a plain `%{"taxon_id" => id}` resolves it: a plant, its genus, or
  one of the genus's sections (an unnamed oak is usually a section's).

  The Source's spelling is `name_reading`, else `name_as_written`; an
  abbreviated genus ("Q. obtusiloba") is written out with the plant's
  genus, which must have that initial. A spelling the plant already holds
  is not added again.

  The synonym and the plant go through `Gallformers.Import.record_synonym_added/4`
  and `record_plant_added_from_wcvp/3`, so they are in the replay log before
  the decision. Replaying them first may resolve the Host before its
  decision replays; the decision is then done (`Gallformers.Import.Replay`).
  Replaying the decision itself adds nothing again: the synonym is held,
  and a WCVP decision names its plant.
  """
  alias Gallformers.Import
  alias Gallformers.Import.QueueItem
  alias Gallformers.Import.TaxonomyAdmin
  alias Gallformers.Ranges.Wcvp, as: WcvpLinks
  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer

  @plantae "Plantae"
  @abbreviation ~r/\A([A-Z])\.\s*(.+)\z/

  @doc "Whether `item` is about a Host name."
  @spec host?(QueueItem.t()) :: boolean()
  def host?(%QueueItem{kind: :unresolved_host}), do: true

  def host?(%QueueItem{kind: :ambiguous_match, statement_ref: "t" <> _, subject: subject}),
    do: subject["host"] == true

  def host?(_item), do: false

  @doc "Whether `decision` (its note left out) is a Host decision that adds a synonym or a plant."
  @spec adds?(map()) :: boolean()
  def adds?(decision), do: decision["add_synonym"] == true or is_binary(decision["wcvp_id"])

  # -- validating --------------------------------------------------------------

  @doc """
  Checks the choice of a Host decision (the decision without its note):
  `:ok`, `{:error, message}`, or `:other` when it is none of the shapes
  this module adds (the queue checks those).
  """
  @spec check(QueueItem.t(), map()) :: :ok | {:error, String.t()} | :other
  def check(item, %{"taxon_id" => id, "add_synonym" => add} = choice)
      when map_size(choice) == 2 do
    cond do
      add != true -> {:error, "add_synonym must be true"}
      common_name?(item) -> {:error, "a common name is not added as a synonym"}
      not plant?(id) -> {:error, "taxon_id must be a plant"}
      match?({:error, _}, spelling(item, id)) -> {:error, elem(spelling(item, id), 1)}
      true -> :ok
    end
  end

  def check(_item, %{"wcvp_id" => id} = choice) when map_size(choice) == 1 do
    case accepted_record(id) do
      nil ->
        {:error, "wcvp_id must be a WCVP record with an accepted name"}

      record ->
        if TaxonomyAdmin.wcvp_rank(record),
          do: :ok,
          else: {:error, "WCVP's rank #{record.taxon_rank} has no rank in Gallformers"}
    end
  end

  def check(_item, %{"wcvp_id" => id, "taxon_id" => taxon_id} = choice)
      when map_size(choice) == 2 do
    if is_binary(id) and plant?(taxon_id),
      do: :ok,
      else: {:error, "wcvp_id must come with the plant it resolved to"}
  end

  def check(_item, choice) do
    if Map.has_key?(choice, "add_synonym") or Map.has_key?(choice, "wcvp_id"),
      do: {:error, "add_synonym goes with taxon_id; wcvp_id alone"},
      else: :other
  end

  defp common_name?(%QueueItem{subject: subject}),
    do: is_map(subject) and subject["common_name"] == true

  defp plant?(id), do: is_integer(id) and match?(%{kingdom: @plantae}, Taxa.get_taxon(id))

  # -- carrying out ------------------------------------------------------------

  @doc """
  Adds what a valid Host `decision` on `item` needs, inside the caller's
  transaction: the synonym, the plant. Returns the decision to store
  (a WCVP decision with its plant).
  """
  @spec carry_out(Gallformers.Audit.Actor.t(), QueueItem.t(), map()) ::
          {:ok, map()} | {:error, term()}
  def carry_out(actor, item, %{"add_synonym" => true, "taxon_id" => id} = decision) do
    with :ok <- ensure_synonym(actor, item, id), do: {:ok, decision}
  end

  def carry_out(actor, item, %{"wcvp_id" => wcvp_id} = decision) do
    with {:ok, plant_id} <- wcvp_plant(actor, wcvp_id, decision["taxon_id"]),
         :ok <- ensure_synonym(actor, item, plant_id) do
      {:ok, Map.put(decision, "taxon_id", plant_id)}
    end
  end

  def carry_out(_actor, _item, decision), do: {:ok, decision}

  # A common name ("the black oak") is not a scientific synonym.
  defp ensure_synonym(actor, item, plant_id) do
    if common_name?(item), do: :ok, else: add_spelling(actor, item, plant_id)
  end

  defp add_spelling(actor, item, plant_id) do
    with {:ok, name} <- spelling(item, plant_id) do
      if holds?(plant_id, name) do
        :ok
      else
        with {:ok, _name} <- Import.record_synonym_added(actor, plant_id, name), do: :ok
      end
    end
  end

  defp holds?(plant_id, name) do
    normalized = NameNormalizer.normalize(name)

    Enum.any?(
      Taxa.get_taxon!(plant_id).names,
      &(&1.normalized_name == normalized and is_nil(&1.sensu))
    )
  end

  # The Source's spelling, its abbreviated genus written out with the plant's.
  defp spelling(%QueueItem{subject: subject}, plant_id) do
    name =
      (subject["name_reading"] || subject["name_as_written"] || "")
      |> String.split()
      |> Enum.join(" ")

    case {name, Regex.run(@abbreviation, name)} do
      {"", _} ->
        {:error, "the Source gives no name"}

      {_name, [_, initial, rest]} ->
        genus = plant_id |> Taxa.accepted_name() |> String.split() |> hd()

        if String.starts_with?(genus, initial),
          do: {:ok, "#{genus} #{rest}"},
          else: {:error, "the Source's abbreviated genus is not the plant's"}

      {_name, nil} ->
        {:ok, name}
    end
  end

  defp wcvp_plant(_actor, _wcvp_id, plant_id) when is_integer(plant_id), do: {:ok, plant_id}

  defp wcvp_plant(actor, wcvp_id, nil) do
    case accepted_record(wcvp_id) do
      nil -> {:error, {:no_accepted_wcvp_record, wcvp_id}}
      record -> held_plant(record) |> plant_or_add(actor, record)
    end
  end

  defp plant_or_add(id, _actor, _record) when is_integer(id), do: {:ok, id}

  defp plant_or_add(nil, actor, record) do
    {entries, _native, _introduced} = WcvpLinks.range_entries(record)
    native = Enum.filter(entries, &(elem(&1, 2) == "native"))

    with {:ok, plant} <- Import.record_plant_added_from_wcvp(actor, record, native),
         do: {:ok, plant.id}
  end

  # The tree's plant for an accepted WCVP record: linked to it, else by name.
  defp held_plant(record) do
    case WcvpLinks.linked_taxon_ids(record.plant_name_id) do
      [id | _] -> id
      [] -> named_plant(record)
    end
  end

  # The plant holding the record's name as its accepted name, at the
  # record's rank: a genus record is the genus, not a species of its name.
  defp named_plant(record) do
    case Taxa.resolve_name(record.taxon_name,
           rank: TaxonomyAdmin.wcvp_rank(record),
           kingdom: @plantae
         ) do
      {:ok, %{matched_name: %{status: :accepted}} = taxon} -> taxon.id
      _ -> nil
    end
  end

  @doc """
  The tree's plants for WCVP record `wcvp_id`'s accepted record: those
  linked to it, and the one holding its name at its rank. None when WCVP
  has no accepted record for it (or cannot be read).
  """
  @spec plant_ids(String.t()) :: [integer()]
  def plant_ids(wcvp_id) do
    case accepted_record(wcvp_id) do
      nil -> []
      record -> Enum.uniq(WcvpLinks.linked_taxon_ids(record.plant_name_id) ++ named_ids(record))
    end
  end

  defp named_ids(record), do: record |> named_plant() |> List.wrap()

  # WCVP records are read as maps (Import's boundary does not reach
  # Gallformers.Wcvp's structs).
  # The record itself when accepted (an artificial hybrid is accepted in
  # itself), else the accepted record it names, read whole for its range.
  # None for a record WCVP leaves unplaced, or a synonym of one.
  defp accepted_record(wcvp_id) when is_binary(wcvp_id) do
    wcvp = lookup()

    case wcvp.get(wcvp_id) do
      nil ->
        nil

      record ->
        if accepted?(record) do
          record
        else
          with %{plant_name_id: id} <- wcvp.get_accepted_name(wcvp_id),
               %{} = accepted <- wcvp.get(id),
               true <- accepted?(accepted),
               do: accepted,
               else: (_ -> nil)
        end
    end
  end

  defp accepted_record(_id), do: nil

  defp accepted?(%{taxon_status: "Accepted"}), do: true
  defp accepted?(%{plant_name_id: id, accepted_plant_name_id: id}), do: true
  defp accepted?(_record), do: false

  defp lookup, do: Application.get_env(:gallformers, :wcvp_lookup, Gallformers.Wcvp.Lookup)
end
