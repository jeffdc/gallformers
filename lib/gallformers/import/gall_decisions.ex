defmodule Gallformers.Import.GallDecisions do
  @moduledoc """
  What a Gall decision may carry besides its choice (matter `d213`, Task 8:
  "a Source wrong on some statements"). A Gall question (`gall?/1`: an
  undescribed-Gall candidate, an ambiguous match or an unresolved name, on
  a Gall ref) is decided `%{"gall_id" => id}`, `%{"new" => true}` or
  `%{"skip" => true}`, with, optionally:

    * `"drop" => [fact refs]` — statements of this batch about this Gall
      that the Source gets wrong: they never become Facts (`drops/1`; the
      batch statement says why). The quote stays in the Source's text.
    * `"host_reading" => %{"name" => as_written, "taxon_id" => plant}` —
      the Source means another plant by a Host name (Osten Sacken's
      "Q. nigra, the black-jack oak" is Quercus marilandica). Every taxon
      the package declares by that name (`same_name?/2`: "Q. nigra" is
      "Quercus nigra") resolves to the plant (`read/2`), whatever it
      resolved to, when the package is resolved again. The tree records
      the name as the plant's synonym in the Source's sense
      (`taxon_names.sensu`, the Source's short name, "Osten Sacken 1862"),
      through `Gallformers.Import.record_synonym_added/4`, so it is in the
      replay log before the decision; the decision is stored with that
      `"sensu"`. Replaying the decision adds nothing again.

      That is for a misapplied species name, the Source's throughout. A
      Host above species rank (a genus, a section: Ashmead's "an unknown
      oak" Galls, each stated on Quercus) is the Source's name for many
      Galls, and is not read so (`check_reading/3`): reading it would move
      every one.
    * `"host_taxon_id" => plant` — with a Gall chosen or new: this Gall's
      Host statements (its `host_of` Facts, `host_facts/2`, and the Host
      it is identified by, for a Gall created) go in on the plant, of any
      rank (`chosen_hosts/2`); nothing else of the Source changes — no
      synonym, no reading. Not with `"host_reading"`. It replays by a
      stable reference (`Gallformers.Import.StableRef`).

    * `"generation" => value` — with `"new"` only: the generation the new
      Gall is created with (a generation value,
      `Gallformers.Catalog.get_generation_value/1`), in place of the
      Source's. Refused when Gallformers already holds a Gall of that
      generation for the Gall's Inducer (as the batch resolved it): that
      Gall is the one to choose. It is kept on the statement
      (`Gallformers.Import.Queue.apply_decision/2`) for
      `Gallformers.Import.ApplyGall`, and replays as it is.

  The reading is the package's: other Sources' uses of the name keep its
  usual sense (a misapplied name resolves only when asked for its sensu,
  `Gallformers.Taxa.resolve_name/2`).
  """
  import Ecto.Query, only: [from: 2]

  alias Gallformers.Audit.Actor
  alias Gallformers.Catalog
  alias Gallformers.Import
  alias Gallformers.Import.Batch
  alias Gallformers.Import.BatchStatement
  alias Gallformers.Import.QueueItem
  alias Gallformers.Repo
  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer
  alias Gallformers.Taxa.Rank

  @plantae "Plantae"
  @extras ["drop", "host_reading", "host_taxon_id", "generation"]
  @kinds [:undescribed_gall, :ambiguous_match, :unresolved_name]

  @typedoc "A Host read in a Source's sense, as stored on a decision."
  @type reading :: %{name: String.t(), taxon_id: integer(), sensu: String.t() | nil}

  @doc "Whether `item` is a Gall question, whose decision may drop statements or read a Host."
  @spec gall?(QueueItem.t()) :: boolean()
  def gall?(%QueueItem{kind: kind, statement_ref: "g" <> _}) when kind in @kinds, do: true
  def gall?(_item), do: false

  @doc """
  Splits a Gall decision's choice into `{extras, choice}`: `drop`,
  `host_reading`, `host_taxon_id` and `generation`, and the rest.
  """
  @spec split(map()) :: {map(), map()}
  def split(choice), do: Map.split(choice, @extras)

  # -- validating --------------------------------------------------------------

  @doc """
  Checks a Gall decision's extras (`split/1`) beside its `choice`: `:ok` or
  `{:error, message}`.
  """
  @spec check(QueueItem.t(), map(), map()) :: :ok | {:error, String.t()}
  def check(_item, extras, _choice) when map_size(extras) == 0, do: :ok

  def check(%QueueItem{} = item, extras, choice) do
    content = content(item)

    with :ok <- check_drop(item, content, Map.get(extras, "drop")),
         :ok <- check_host(item, content, extras, choice),
         do: check_generation(item, content, Map.get(extras, "generation"), choice)
  end

  # A Host read in the Source's sense, or a plant chosen for this Gall's
  # Host statements: one or the other.
  defp check_host(item, content, extras, choice) do
    case extras do
      %{"host_reading" => _, "host_taxon_id" => _} ->
        {:error, "host_reading and host_taxon_id don't go together"}

      %{"host_taxon_id" => id} ->
        check_host_taxon(item, content, id, choice)

      _ ->
        check_reading(content, Map.get(extras, "host_reading"), item.batch_id)
    end
  end

  defp check_host_taxon(%QueueItem{statement_ref: gall}, content, id, choice) do
    cond do
      not (Map.has_key?(choice, "gall_id") or choice == %{"new" => true}) ->
        {:error, "host_taxon_id goes only with a Gall chosen or new"}

      not plant?(id) ->
        {:error, "host_taxon_id must be a plant"}

      host_facts(content, gall) == [] ->
        {:error, "host_taxon_id needs a Host statement about this Gall"}

      true ->
        :ok
    end
  end

  defp check_drop(_item, _content, nil), do: :ok

  defp check_drop(%QueueItem{statement_ref: gall}, content, refs) when is_list(refs) do
    about = about_gall(content, gall)

    if Enum.all?(refs, &MapSet.member?(about, &1)),
      do: :ok,
      else: {:error, "drop must list this batch's statements about this Gall"}
  end

  defp check_drop(_item, _content, _refs),
    do: {:error, "drop must list this batch's statements about this Gall"}

  # The refs of the batch's Facts about Gall `gall`, and of the qualifiers on them.
  defp about_gall(content, gall) do
    facts = List.wrap(content["facts"])

    direct =
      for f <- facts,
          gall in [f["gall"], f["subject"], f["object"], f["gall_context"]],
          into: MapSet.new(),
          do: f["id"]

    for f <- facts,
        f["kind"] == "qualifier",
        MapSet.member?(direct, f["of"]),
        into: direct,
        do: f["id"]
  end

  @doc """
  Checks a Host reading (`%{"name" => as_written, "taxon_id" => plant}`,
  optionally with its `"sensu"`) against the batch `content` (decoded): a
  plant, and a name the batch declares at species rank or below — the
  taxon its statement resolved to in batch `batch_id` (nil: none), else
  the rank the batch declares. A Host above species rank is the Source's
  name for many Galls: reading it would move every one, so a plant is
  chosen for the Gall instead (`"host_taxon_id"`). Nil (no reading) is
  `:ok`. `:ok` or `{:error, message}`.
  """
  @spec check_reading(map(), term(), integer() | nil) :: :ok | {:error, String.t()}
  def check_reading(content, reading, batch_id \\ nil)

  def check_reading(_content, nil, _batch_id), do: :ok

  def check_reading(content, %{"name" => name, "taxon_id" => id} = reading, batch_id)
      when is_binary(name) do
    cond do
      Map.keys(reading) -- ["name", "taxon_id", "sensu"] != [] ->
        {:error, "host_reading takes name, taxon_id and sensu"}

      not plant?(id) ->
        {:error, "host_reading's taxon_id must be a plant"}

      not is_nil(reading["sensu"]) and not is_binary(reading["sensu"]) ->
        {:error, "host_reading's sensu must be text"}

      not Enum.any?(declared_names(content), &same_name?(&1, name)) ->
        {:error, "host_reading must name a taxon the batch declares"}

      rank = above_species_rank(batch_id, content, named(content, name)) ->
        {:error, "this Host is a #{rank}: choose a plant for this Gall instead"}

      true ->
        :ok
    end
  end

  def check_reading(_content, _reading, _batch_id),
    do: {:error, "host_reading must be a name and the plant it means"}

  @doc """
  The rank of the first of the taxa `refs` of batch `batch_id` (decoded
  `content`) above species rank, or nil: the taxon its statement resolved
  to, else the rank the batch declares.
  """
  @spec above_species_rank(integer() | nil, map(), [String.t()]) :: Rank.t() | nil
  def above_species_rank(batch_id, content, refs) do
    taxa = Map.new(List.wrap(content["taxa"]), &{&1["ref"], &1})

    refs
    |> Enum.map(&(resolved_rank(batch_id, &1) || declared_rank(taxa[&1])))
    |> Enum.find(&(is_atom(&1) and &1 != nil and &1 not in Rank.species_and_below()))
  end

  defp resolved_rank(batch_id, ref) when is_integer(batch_id) do
    query =
      from(s in BatchStatement,
        where: s.batch_id == ^batch_id and s.kind == :taxon and s.ref == ^ref,
        select: s.taxon_id
      )

    case Repo.one(query) do
      id when is_integer(id) -> Taxa.get_taxon!(id).rank
      _ -> nil
    end
  end

  defp resolved_rank(_batch_id, _ref), do: nil

  defp declared_rank(%{"rank" => rank}) when is_binary(rank),
    do: Enum.find(Rank.all(), &(to_string(&1) == rank))

  defp declared_rank(_taxon), do: nil

  # The refs of the taxa the batch declares by `name`.
  defp named(content, name) do
    for %{"ref" => ref} = t <- List.wrap(content["taxa"]),
        Enum.any?([t["name_as_written"], t["name_reading"]], &same_name?(&1, name)),
        do: ref
  end

  @doc """
  The refs of the Host statements of the batch `content` (decoded) about
  Gall `gall`: its `host_of` Facts, confirmed.
  """
  @spec host_facts(map(), String.t()) :: [String.t()]
  def host_facts(content, gall) do
    for %{"kind" => "relationship", "type" => "host_of", "object" => ^gall} = f <-
          List.wrap(content["facts"]),
        Map.get(f, "stance", "confirm") == "confirm",
        do: f["id"]
  end

  defp check_generation(_item, _content, nil, _choice), do: :ok

  defp check_generation(_item, _content, _value, choice) when choice != %{"new" => true},
    do: {:error, "generation goes only with new"}

  defp check_generation(item, content, value, _choice) do
    cond do
      not is_binary(value) or Catalog.get_generation_value(value) == nil ->
        {:error, "generation must be a generation value"}

      value in inducer_generations(item, content) ->
        {:error, "Gallformers already holds a Gall of its Inducer of the #{value} generation"}

      true ->
        :ok
    end
  end

  # The generations of the Galls Gallformers holds for the Gall's Inducer,
  # as the batch resolved it (none while it is unresolved).
  defp inducer_generations(%QueueItem{batch_id: batch_id, statement_ref: ref}, content)
       when is_integer(batch_id) do
    g = Enum.find(List.wrap(content["galls"]), &(&1["ref"] == ref)) || %{}

    with inducer when is_binary(inducer) <- get_in(g, ["identified_by", "inducer"]),
         taxon_id when is_integer(taxon_id) <- resolved_taxon(batch_id, inducer) do
      for %{generation: generation} <- Catalog.list_gall_summaries_by_inducer([taxon_id]),
          generation != nil,
          do: generation
    else
      _ -> []
    end
  end

  defp inducer_generations(_item, _content), do: []

  defp resolved_taxon(batch_id, ref) do
    Repo.one(
      from(s in BatchStatement,
        where:
          s.batch_id == ^batch_id and s.kind == :taxon and s.ref == ^ref and
            s.resolution in [:resolved, :new],
        select: s.taxon_id
      )
    )
  end

  defp plant?(id), do: is_integer(id) and match?(%{kingdom: @plantae}, Taxa.get_taxon(id))

  defp declared_names(content) do
    for t <- List.wrap(content["taxa"]),
        name <- [t["name_as_written"], t["name_reading"]],
        is_binary(name),
        do: name
  end

  defp content(%QueueItem{batch_id: batch_id}) when is_integer(batch_id),
    do: Repo.get!(Batch, batch_id).content || %{}

  defp content(_item), do: %{}

  # -- carrying out ------------------------------------------------------------

  @doc """
  Adds what a valid Gall `decision` on `item` needs, inside the caller's
  transaction: a Host reading's synonym, in the Source's sense. Returns
  the decision to store (a reading with its `"sensu"`).
  """
  @spec carry_out(Actor.t(), QueueItem.t(), map()) :: {:ok, map()} | {:error, term()}
  def carry_out(actor, item, %{"host_reading" => %{"name" => name, "taxon_id" => id} = r} = d) do
    content = content(item)
    sensu = r["sensu"] || sensu(content["source"])
    spelling = written_out(name, content)

    with :ok <- ensure_synonym(actor, id, spelling, sensu) do
      {:ok, Map.put(d, "host_reading", Map.put(r, "sensu", sensu))}
    end
  end

  def carry_out(_actor, _item, decision), do: {:ok, decision}

  defp ensure_synonym(actor, plant_id, name, sensu) do
    normalized = NameNormalizer.normalize(name)

    held? =
      Enum.any?(
        Taxa.get_taxon!(plant_id).names,
        &(&1.normalized_name == normalized and &1.sensu == sensu)
      )

    if held? do
      :ok
    else
      with {:ok, _name} <- Import.record_synonym_added(actor, plant_id, name, sensu: sensu),
           do: :ok
    end
  end

  # An abbreviated genus ("Q. nigra") written out with the one genus of
  # that initial the batch writes in full; else as written.
  defp written_out(name, content) do
    name = name |> String.split() |> Enum.join(" ")

    case Regex.run(~r/\A([A-Z])\.\s*(.+)\z/, name) do
      [_, initial, rest] ->
        genera =
          for n <- declared_names(content),
              [genus | _] = String.split(n),
              not String.ends_with?(genus, "."),
              String.starts_with?(genus, initial),
              uniq: true,
              do: String.capitalize(genus)

        case genera do
          [genus] -> "#{genus} #{rest}"
          _ -> name
        end

      nil ->
        name
    end
  end

  @doc """
  The Source's short name for a sensu, from its block in a batch: its
  authors' surnames ("Ashmead"; "Nastasi and Davis"; "Weld et al.") and
  year, "Ashmead 1897"; its citation or title when it names no author.
  """
  @spec sensu(map() | nil) :: String.t() | nil
  def sensu(%{} = block) do
    case {who(block), year(block)} do
      {nil, _} -> block["citation"] || block["title"]
      {who, nil} -> who
      {who, year} -> "#{who} #{year}"
    end
  end

  def sensu(_block), do: nil

  defp who(block) do
    case block |> Map.get("authors") |> List.wrap() |> Enum.filter(&is_binary/1) do
      [] -> nil
      [one] -> surname(one)
      [a, b] -> "#{surname(a)} and #{surname(b)}"
      [a | _] -> "#{surname(a)} et al."
    end
  end

  defp year(block) do
    case Regex.run(~r/\d{4}/, to_string(get_in(block, ["authored", "date"]))) do
      [y] -> y
      _ -> nil
    end
  end

  defp surname(author) do
    case String.split(author, ",", parts: 2) do
      [surname, _rest] -> String.trim(surname)
      [name] -> name |> String.split() |> List.last() || name
    end
  end

  # -- honouring ---------------------------------------------------------------

  @doc "The statements the decided Gall items of `decided` drop, ref to why."
  @spec drops([QueueItem.t()]) :: %{String.t() => String.t()}
  def drops(decided) do
    for %QueueItem{decision: %{"drop" => refs}} = item <- decided,
        gall?(item),
        ref <- List.wrap(refs),
        into: %{},
        do: {ref, "left out by #{item.decided_by_name} choosing the Gall #{item.statement_ref}"}
  end

  @doc """
  The Hosts chosen for the statements of `decided` (decided items of the
  batch `content`, decoded): a Gall decision's `"host_taxon_id"`, for each
  of its Gall's Host statements (`host_facts/2`), ref to the plant.
  """
  @spec chosen_hosts([QueueItem.t()], map()) :: %{String.t() => integer()}
  def chosen_hosts(decided, content) do
    for %QueueItem{decision: %{"host_taxon_id" => id}} = item <- decided,
        gall?(item),
        is_integer(id),
        ref <- host_facts(content, item.statement_ref),
        into: %{},
        do: {ref, id}
  end

  @doc """
  The Host readings of `decided` (decided items of a package's batches):
  a Gall decision's, and a Host dispute's kept with the Host read as
  another plant (`Gallformers.Import.Disputes`).
  """
  @spec readings([QueueItem.t()]) :: [reading()]
  def readings(decided) do
    for %QueueItem{decision: %{"host_reading" => %{"name" => name, "taxon_id" => id} = r}} =
          item <- decided,
        gall?(item) or item.kind == :dispute,
        do: %{name: name, taxon_id: id, sensu: r["sensu"]}
  end

  @doc """
  Taxon statements (as the resolver gives them) with `readings` applied:
  one whose name (as written, or its reading) is a reading's name resolves
  to its plant, method `"sensu"`.
  """
  @spec read([map()], [reading()]) :: [map()]
  def read(statements, []), do: statements

  def read(statements, readings), do: Enum.map(statements, &read_one(&1, readings))

  defp read_one(s, readings) do
    names = [s.detail["name_as_written"], s.detail["name_reading"]]

    case Enum.find(readings, fn r -> Enum.any?(names, &same_name?(&1, r.name)) end) do
      nil -> s
      r -> read_as(s, r)
    end
  end

  defp read_as(%{kind: :taxon} = s, r) do
    %{
      s
      | resolution: :resolved,
        taxon_id: r.taxon_id,
        method: "sensu",
        candidate_ids: [],
        flags: s.flags -- ["synonym_held_valid"],
        detail: s.detail |> Map.delete("reason") |> Map.put("read_sensu", r.sensu)
    }
  end

  defp read_as(s, _r), do: s

  @doc """
  Whether two names a Source writes are the same name: equal normalized
  (`Gallformers.Taxa.NameNormalizer`), or one the other with its genus
  abbreviated ("Q. nigra", "Quercus nigra").
  """
  @spec same_name?(String.t() | nil, String.t() | nil) :: boolean()
  def same_name?(a, b) when is_binary(a) and is_binary(b) do
    na = NameNormalizer.normalize(a)
    nb = NameNormalizer.normalize(b)
    na == nb or abbreviates?(na, nb) or abbreviates?(nb, na)
  end

  def same_name?(_a, _b), do: false

  defp abbreviates?(short, long) do
    case {String.split(short, " ", parts: 2), String.split(long, " ", parts: 2)} do
      {[<<initial::binary-size(1), ".">>, rest], [genus, rest]} ->
        String.starts_with?(genus, initial) and String.length(genus) > 1

      _ ->
        false
    end
  end
end
