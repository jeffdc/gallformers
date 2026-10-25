defmodule Gallformers.Import.Resolver do
  @moduledoc """
  Resolves a batch's taxon names to taxa (`9449` Task 12; producer guide
  background, *What Gallformers does on import* steps 1–3).

  Each declared taxon (`taxa[]`: `ref`, `name_as_written`, `rank`, maybe
  `name_reading`, `sensu`, `new`) is looked up with
  `Gallformers.Taxa.resolve_name/2` — accepted names and synonyms, through
  the normalized name — filtered by its rank, and by kingdom Plantae when the
  batch uses it as a Host. The names tried, in order, stopping at the first
  that matches anything:

    1. `name_as_written` (method `"exact"`, or `"synonym"` when it matched a
       synonym);
    2. a genus abbreviation expanded ("Q. lobata" → "Quercus lobata",
       method `"abbreviation"`) with every genus of that initial the batch,
       the package's taxonomy batch or the document names — genera printed
       in capitals ("QUERCUS PRINOS") included — that the tree holds;
    3. `name_reading`, the evident printed name where the text is damaged
       (method `"name_reading"`), and its abbreviation expanded;
    4. a 19th-century oak-gall name ("Cynips q. spongifica", "C.
       quercus-spongifica", "C.Q. INANIS") as the fused epithet
       *quercusspongifica* in any genus (method `"fused_epithet"`).

  No fuzzy matching: it joined different species.

  Outcomes (`Gallformers.Import.BatchStatement`): `:resolved` (one taxon),
  `:ambiguous` (several, in `candidate_ids`), `:new` (no match, and the
  Source — the taxon itself or the package's taxonomy batch — presents it as
  new), `:unresolved`.

  ## No silent merges

  A name the tree holds as a synonym while this Source treats it as valid —
  the taxonomy batch gives it a `name`, `placement` or `common_name` act,
  makes it the accepted name of a synonymy, a parent, or a split's taxon or
  daughter — is not resolved to the accepted taxon: it is `:unresolved`,
  flagged `"synonym_held_valid"`, with that taxon as its candidate, in both
  batches (`9449` §3: gall names never resolve through a disagreement
  silently).

  `queue_items/1` turns the statements that need an admin into queue items:
  unresolved Hosts (`d585`; they hold the gall batch), other unresolved
  names, ambiguous matches, and held-valid synonyms.
  """

  alias Gallformers.Taxa
  alias Gallformers.Taxa.NameNormalizer
  alias Gallformers.Taxa.Taxon

  @typedoc "What resolution needs besides the batch."
  @type context :: %{
          genera: [String.t()],
          new_names: %{String.t() => String.t()},
          held_valid: MapSet.t(String.t()),
          host_refs: MapSet.t(String.t())
        }

  @typedoc "A statement's resolution, as `Gallformers.Import.BatchStatement` takes it."
  @type statement :: %{
          kind: :taxon,
          ref: String.t(),
          resolution: :resolved | :ambiguous | :unresolved | :new,
          method: String.t() | nil,
          taxon_id: integer() | nil,
          candidate_ids: [integer()],
          flags: [String.t()],
          detail: map()
        }

  @abbreviation ~r/\A([A-Z])\.\s*(.+)\z/
  # "Cynips q. spongifica", "C. quercus-spongifica", "C.Q. INANIS"
  @fused ~r/\A(?:\S+\s+(?:q\.|quercus[-\s]?)|[A-Z]\.\s*Q\.)\s*([a-z][a-z-]+)\z/i
  @capitalized ~r/\b[A-Z][A-Za-z]+\b/u
  @abbreviated ~r/\A[A-Z]\./
  @plantae "Plantae"

  # The taxon refs a taxonomy act uses as names the Source treats as valid.
  @valid_roles %{
    "name" => ["taxon"],
    "placement" => ["taxon", "parent"],
    "synonymy" => ["accepted"],
    "split" => ["taxon", "into"],
    "common_name" => ["taxon"]
  }

  @doc """
  The context for resolving `batch` (decoded): `:taxonomy` is the package's
  taxonomy batch (decoded, or nil), `:document_texts` the document's item
  texts (for the genera it names).
  """
  @spec context(map(), keyword()) :: context()
  def context(batch, opts \\ []) do
    taxonomy = opts[:taxonomy]
    texts = Keyword.get(opts, :document_texts, [])
    declared = taxa(batch) ++ taxa(taxonomy)

    %{
      genera: genera(declared, texts),
      new_names: new_names(taxonomy, batch),
      held_valid: held_valid(taxonomy),
      host_refs: host_refs(batch)
    }
  end

  defp taxa(%{"taxa" => taxa}) when is_list(taxa), do: taxa
  defp taxa(_batch), do: []

  # Genera written in full in the batches or the document, that the tree holds.
  defp genera(declared, texts) do
    from_batches =
      for t <- declared,
          name = t["name_reading"] || t["name_as_written"],
          is_binary(name),
          not Regex.match?(@abbreviated, name),
          [first | _] <- [String.split(name)],
          do: first

    from_document = for text <- texts, [word] <- Regex.scan(@capitalized, text), do: word

    (from_batches ++ from_document)
    |> Enum.map(&String.capitalize/1)
    |> Enum.uniq()
    |> Taxa.genus_names()
    |> Enum.sort()
  end

  # Normalized names the Source presents as new, with the status as written.
  defp new_names(taxonomy, batch) do
    for t <- taxa(taxonomy) ++ taxa(batch),
        %{"status" => status} <- [t["new"]],
        into: %{},
        do: {normalize(t), status}
  end

  defp held_valid(nil), do: MapSet.new()

  defp held_valid(taxonomy) do
    names = Map.new(taxa(taxonomy), &{&1["ref"], normalize(&1)})

    for %{"kind" => kind, "stance" => "confirm"} = act <- List.wrap(taxonomy["acts"]),
        role <- Map.get(@valid_roles, kind, []),
        ref <- List.wrap(act[role]),
        name = names[ref],
        into: MapSet.new(),
        do: name
  end

  # Refs used as Hosts: identified_by.host and host_of subjects.
  defp host_refs(batch) do
    from_galls = for %{"identified_by" => %{"host" => ref}} <- List.wrap(batch["galls"]), do: ref

    from_facts =
      for %{"kind" => "relationship", "type" => "host_of", "subject" => ref} <-
            List.wrap(batch["facts"]),
          do: ref

    MapSet.new(from_galls ++ from_facts)
  end

  # -- resolving ---------------------------------------------------------------

  @doc "Resolves every declared taxon of `batch` (decoded), in the batch's order."
  @spec resolve_taxa(map(), context()) :: [statement()]
  def resolve_taxa(batch, context) do
    Enum.map(taxa(batch), &resolve_taxon(&1, context))
  end

  defp resolve_taxon(t, context) do
    host? = MapSet.member?(context.host_refs, t["ref"])
    opts = [rank: t["rank"], kingdom: if(host?, do: @plantae), sensu: t["sensu"]]

    detail =
      %{
        "name_as_written" => t["name_as_written"],
        "name_reading" => t["name_reading"],
        "rank" => t["rank"],
        "sensu" => t["sensu"],
        "host" => host?
      }
      |> Map.reject(fn {_k, v} -> is_nil(v) end)

    statement = %{
      kind: :taxon,
      ref: t["ref"],
      resolution: :unresolved,
      method: nil,
      taxon_id: nil,
      candidate_ids: [],
      flags: [],
      detail: detail
    }

    t
    |> attempts(context)
    |> first_match(opts)
    |> outcome(statement, t, context)
  end

  # The names to try, in order, as {method, name, how}: how is :name or
  # :epithet.
  defp attempts(t, context) do
    written = t["name_as_written"]
    reading = t["name_reading"]

    [{"exact", written, :name}] ++
      expansions(written, context) ++
      if(reading,
        do: [{"name_reading", reading, :name}] ++ expansions(reading, context, "name_reading"),
        else: []
      ) ++
      fused(reading) ++ fused(written)
  end

  defp expansions(name, context, method \\ "abbreviation") do
    case Regex.run(@abbreviation, String.trim(name)) do
      [_, initial, rest] ->
        expanded = for g <- context.genera, String.starts_with?(g, initial), do: "#{g} #{rest}"
        if expanded == [], do: [], else: [{method, expanded, :names}]

      nil ->
        []
    end
  end

  defp fused(nil), do: []

  defp fused(name) do
    case Regex.run(@fused, name |> String.split() |> Enum.join(" ")) do
      [_, epithet] -> [{"fused_epithet", "quercus" <> String.replace(epithet, "-", ""), :epithet}]
      nil -> []
    end
  end

  # The first attempt that matches anything: {method, tried name, result}.
  defp first_match(attempts, opts) do
    Enum.find_value(attempts, :none, fn attempt ->
      case try_attempt(attempt, opts) do
        {_tried, :none} -> nil
        {tried, result} -> {elem(attempt, 0), tried, result}
      end
    end)
  end

  defp try_attempt({_method, name, :name}, opts), do: {name, Taxa.resolve_name(name, opts)}

  defp try_attempt({_method, name, :epithet}, opts),
    do: {name, Taxa.resolve_epithet(name, Keyword.delete(opts, :rank))}

  # Several expansions: one taxon across them all, or ambiguous.
  defp try_attempt({_method, names, :names}, opts) do
    hits =
      for name <- names, result = Taxa.resolve_name(name, opts), result != :none do
        {name, result}
      end

    taxa =
      hits
      |> Enum.flat_map(fn
        {_name, {:ok, taxon}} -> [taxon]
        {_name, {:ambiguous, taxa}} -> taxa
      end)
      |> Enum.uniq_by(& &1.id)

    case {hits, taxa} do
      {[], _} -> {nil, :none}
      {[{name, _}], [taxon]} -> {name, {:ok, taxon}}
      {[{name, _} | _], [taxon]} -> {name, {:ok, taxon}}
      {_hits, taxa} -> {Enum.map_join(hits, ", ", &elem(&1, 0)), {:ambiguous, taxa}}
    end
  end

  defp outcome(:none, statement, t, context) do
    case new_status(t, context) do
      nil ->
        put_in(statement.detail["reason"], "no taxon has this name or synonym")

      status ->
        %{statement | resolution: :new, detail: Map.put(statement.detail, "new_status", status)}
    end
  end

  defp outcome({method, tried, {:ok, %Taxon{} = taxon}}, statement, _t, context) do
    matched = taxon.matched_name
    detail = Map.merge(statement.detail, %{"tried" => tried, "matched" => matched.name})

    if matched.status == :synonym and
         MapSet.member?(context.held_valid, NameNormalizer.normalize(tried)) do
      %{
        statement
        | resolution: :unresolved,
          method: method(method, matched),
          candidate_ids: [taxon.id],
          flags: ["synonym_held_valid"],
          detail:
            Map.put(
              detail,
              "reason",
              "the tree holds #{matched.name} as a synonym of #{Taxa.accepted_name(taxon)}, " <>
                "but this Source treats it as valid"
            )
      }
    else
      %{
        statement
        | resolution: :resolved,
          method: method(method, matched),
          taxon_id: taxon.id,
          detail: detail
      }
    end
  end

  defp outcome({method, tried, {:ambiguous, taxa}}, statement, _t, _context) do
    %{
      statement
      | resolution: :ambiguous,
        method: method,
        candidate_ids: Enum.map(taxa, & &1.id),
        detail:
          Map.merge(statement.detail, %{
            "tried" => tried,
            "reason" => "#{length(taxa)} taxa have this name"
          })
    }
  end

  defp method("exact", %{status: :synonym}), do: "synonym"
  defp method(method, _matched), do: method

  defp new_status(t, context) do
    case t["new"] do
      %{"status" => status} -> status
      _ -> Map.get(context.new_names, normalize(t))
    end
  end

  defp normalize(t), do: NameNormalizer.normalize(t["name_reading"] || t["name_as_written"] || "")

  # -- the admin queue ---------------------------------------------------------

  @doc """
  The queue items the statements call for, as
  `%{kind, statement_ref, subject, proposal, reason}`: an unresolved Host
  is `:unresolved_host` (it holds the gall batch, `d585`), another
  unresolved name `:unresolved_name`, an ambiguous match `:ambiguous_match`
  (with its candidates), a held-valid synonym `:taxonomy_disagreement`.
  Resolved and new statements need nothing.
  """
  @spec queue_items([statement()]) :: [map()]
  def queue_items(statements) do
    for %{kind: :taxon, resolution: resolution} = s <- statements,
        resolution in [:unresolved, :ambiguous] do
      %{
        kind: queue_kind(s),
        statement_ref: s.ref,
        subject: Map.take(s.detail, ["name_as_written", "name_reading", "rank", "sensu", "host"]),
        proposal: %{"candidate_ids" => s.candidate_ids},
        reason: s.detail["reason"]
      }
    end
  end

  defp queue_kind(%{flags: flags} = s) do
    cond do
      "synonym_held_valid" in flags -> :taxonomy_disagreement
      s.resolution == :ambiguous -> :ambiguous_match
      s.detail["host"] -> :unresolved_host
      true -> :unresolved_name
    end
  end

  @doc """
  Whether the statements hold the gall batch: a Host name that is not
  resolved (or new) stops it until an admin resolves it (`d585`).
  """
  @spec holds_gall_batch?([statement()]) :: boolean()
  def holds_gall_batch?(statements) do
    Enum.any?(statements, fn s ->
      s.kind == :taxon and s.detail["host"] == true and s.resolution in [:unresolved, :ambiguous]
    end)
  end
end
