defmodule Gallformers.Import.SourceStep do
  @moduledoc """
  The package's Source (`9449` §5, Task 13): which Source its batches are
  about, the document stored for it, and the Source a retraction notice
  retracts.

  ## Matching (when the package is resolved)

    * A Gallformers batch (`source.gallformers`) is the Gallformers Source.
    * `gallformers_source_id`, when given, names the Source.
    * Otherwise `Gallformers.Sources.match_source/1`'s conservative rule:
      the DOI, else the citation, else the title — one clear match is the
      Source; anything ambiguous (several Sources; a citation match whose
      stored DOI differs; a title held by a Source with another citation)
      is an `:ambiguous_match` queue item (`statement_ref` `"source"`) for
      an admin to pick the Source or decide it is new; no match is a new
      Source.

  A match sets `import_packages.source_id` at once (no data changes).

  ## Applying (inside the first batch's transaction)

  A new Source is created from the Source block, today's NOT NULL columns
  filled (`author` is the authors joined with "; ", `pubyear` the authored
  year, `link` the URL or DOI link or empty, `license` the license value
  with its canonical link). A title already taken (only when an admin
  decided a Source is new despite the title) gets the authored year, then a
  counter, appended. The package's `document.json` is stored for it
  (`Gallformers.Sources.store_document/3`).

  A retraction notice (`source.retracts`) marks the retracted Source —
  matched by `gallformers_source_id` or citation, or an admin's decision
  (`statement_ref` `"retracts"`) — as retracted by the notice on the
  notice's authored date, and recomputes its Facts: all of its stances
  are cancelled.
  """

  alias Gallformers.Facts
  alias Gallformers.Import.Package
  alias Gallformers.Licenses
  alias Gallformers.Sources
  alias Gallformers.Sources.Source

  @doc "The package's Source block: the first batch's `source`."
  @spec source_block([map()]) :: map() | nil
  def source_block(contents), do: Enum.find_value(contents, & &1["source"])

  @doc """
  Matches the Source block when the package is resolved: the matched
  Source's ID (or nil) and the package-level queue items.
  """
  @spec resolve(map() | nil) :: %{source_id: integer() | nil, queue: [map()]}
  def resolve(nil), do: %{source_id: nil, queue: []}

  def resolve(block) do
    {source_id, queue} =
      case match(block) do
        {:match, %Source{id: id}} -> {id, []}
        :none -> {nil, []}
        {:ambiguous, sources} -> {nil, [ambiguous_item("source", block, sources)]}
        {:error, reason} -> {nil, [unresolved_item("source", block, reason)]}
      end

    %{source_id: source_id, queue: queue ++ retracts_items(block["retracts"])}
  end

  defp match(%{"gallformers" => true}) do
    case Sources.get_gallformers_source() do
      %Source{} = source -> {:match, source}
      nil -> {:error, "there is no Gallformers Source"}
    end
  end

  defp match(%{"gallformers_source_id" => id}) when is_integer(id) do
    case Sources.get_source(id) do
      %Source{} = source -> {:match, source}
      nil -> {:error, "no Source has gallformers_source_id #{id}"}
    end
  end

  defp match(block) do
    Sources.match_source(%{
      doi: get_in(block, ["identifiers", "doi"]),
      citation: block["citation"],
      title: block["title"]
    })
  end

  defp retracts_items(nil), do: []

  defp retracts_items(retracts) do
    case match_retracted(retracts) do
      {:match, _source} -> []
      {:ambiguous, sources} -> [ambiguous_item("retracts", retracts, sources)]
      :none -> [unresolved_item("retracts", retracts, "no Source has this citation")]
      {:error, reason} -> [unresolved_item("retracts", retracts, reason)]
    end
  end

  defp match_retracted(%{"gallformers_source_id" => id}) when is_integer(id) do
    case Sources.get_source(id) do
      %Source{} = source -> {:match, source}
      nil -> {:error, "no Source has gallformers_source_id #{id}"}
    end
  end

  defp match_retracted(retracts),
    do: Sources.match_source(%{citation: retracts["citation_as_written"]})

  defp ambiguous_item(ref, block, sources) do
    %{
      kind: :ambiguous_match,
      statement_ref: ref,
      subject: subject(block),
      proposal: %{"candidate_ids" => Enum.map(sources, & &1.id)},
      reason: "#{length(sources)} Source(s) may be this one (DOI, citation or title)"
    }
  end

  defp unresolved_item(ref, block, reason) do
    %{
      kind: :unresolved_name,
      statement_ref: ref,
      subject: subject(block),
      proposal: %{},
      reason: reason
    }
  end

  defp subject(block),
    do:
      Map.take(block, ["title", "citation", "citation_as_written", "identifiers", "gallformers"])

  # -- applying ----------------------------------------------------------------

  @doc """
  The package's Source, inside the batch's transaction: the matched one,
  the admin's decision, or a new one; with its document stored and any
  retraction applied. `decisions` are the package-level decided items'
  decisions by ref (`"source"`, `"retracts"`).
  """
  @spec ensure(Gallformers.Audit.Actor.t(), Package.t(), map(), map(), %{String.t() => map()}) ::
          {:ok, Source.t(), %{String.t() => integer()}} | {:error, term()}
  def ensure(actor, %Package{} = package, block, files, decisions) do
    with {:ok, source} <- source(package, block, decisions),
         {:ok, items} <- store_document(actor, source, files["document.json"]),
         :ok <- retract(actor, source, block["retracts"], decisions["retracts"]) do
      {:ok, source, items}
    end
  end

  defp source(%Package{source_id: id}, _block, _decisions) when is_integer(id),
    do: {:ok, Sources.get_source!(id)}

  defp source(_package, block, decisions) do
    case {decisions["source"], match(block)} do
      {%{"source_id" => id}, _} -> {:ok, Sources.get_source!(id)}
      {%{"new" => true}, _} -> create(block)
      {_, {:match, source}} -> {:ok, source}
      {_, :none} -> create(block)
      {_, other} -> {:error, {:source_not_resolved, other}}
    end
  end

  defp create(block) do
    {:ok, {date, _precision}} = Sources.PartialDate.parse(block["authored"]["date"])
    year = Integer.to_string(date.year)
    doi = get_in(block, ["identifiers", "doi"])
    url = get_in(block, ["identifiers", "url"])
    license = block["license"]["value"]

    Sources.create_imported_source(%{
      title: unique_title(block["title"], year),
      author: Enum.join(block["authors"], "; "),
      pubyear: year,
      link: url || (doi && "https://doi.org/#{doi}") || "",
      citation: block["citation"],
      license: license,
      licenselink: Licenses.url(license) || "",
      kind: block["kind"],
      authors: block["authors"],
      authored: block["authored"]["date"],
      authored_as_written: block["authored"]["as_written"],
      doi: doi,
      url: url,
      isbn: get_in(block, ["identifiers", "isbn"]),
      license_value: license,
      license_as_written: block["license"]["as_written"]
    })
  end

  defp unique_title(title, year) do
    title = String.trim(title)

    [title, "#{title} (#{year})"]
    |> Stream.concat(Stream.map(Stream.iterate(2, &(&1 + 1)), &"#{title} (#{year}, #{&1})"))
    |> Enum.find(&(not Sources.title_taken?(&1)))
  end

  defp store_document(_actor, _source, nil), do: {:ok, %{}}
  defp store_document(_actor, %Source{kind: :gallformers}, _bytes), do: {:ok, %{}}

  defp store_document(actor, source, bytes) do
    with {:ok, document} <- Sources.store_document(actor, source, bytes) do
      {:ok, Map.new(Sources.list_document_items(document), &{&1.ref, &1.id})}
    end
  end

  defp retract(_actor, _notice, nil, _decision), do: :ok
  defp retract(_actor, _notice, _retracts, %{"skip" => true}), do: :ok

  defp retract(actor, notice, retracts, decision) do
    retracted =
      case {decision, match_retracted(retracts)} do
        {%{"source_id" => id}, _} -> {:ok, Sources.get_source!(id)}
        {_, {:match, source}} -> {:ok, source}
        {_, other} -> {:error, {:retracted_source_not_resolved, other}}
      end

    with {:ok, source} <- retracted do
      if source.retracted_by_id == notice.id do
        :ok
      else
        with {:ok, _source} <- Sources.retract_source(source, notice, notice.authored_date),
             {:ok, _conflicts} <- Facts.recompute_for_source(actor, source.id) do
          :ok
        end
      end
    end
  end
end
