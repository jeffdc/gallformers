defmodule Gallformers.Import.Attributions do
  @moduledoc """
  A batch statement's attribution, from the contract's shape to what
  `Gallformers.Facts.attribute/2` takes (`9449` §2, Task 13).

    * **Quote evidence** becomes one evidence row per entry: the item's
      stored `document_item_id` (from the Source's stored `document.json`),
      (a reading fix's quotes give it, `gallformers_document_item_id`),
      the quote or `whole_item`, the printed `page`, the `url`, and `cites`
      as `cites_as_written`. Gallformers locates and stores each quote's
      span.
    * **Observations** arrive per evidence entry but are stored per
      attribution: they are flattened, once per provider and ID.
    * **Gallformers statements** (`statement` evidence) carry no evidence
      rows: the attribution takes the statement's text and date
      (`statement_text`, `stated`). With several statements on one Fact,
      the newest decides the date and their texts are joined, newest first.
      A statement's `cites` (the Source a curator follows) becomes
      `cites_as_written` and `cited_source_id` — the newest citing
      statement's, its Source ID kept only when Gallformers holds that
      Source.
    * **Gallformers statements quoting a Gall's note** keep their quote
      evidence and take the note's date, with what they quote as their
      statement text (`with_note/2`).
    * Other Sources' attributions take the Source's authored date (no
      `stated`).
  """

  alias Gallformers.Sources

  @type items :: %{String.t() => integer()}

  @doc """
  The attribution attrs for a statement (an act or Fact of the batch, as
  decoded) by `source_kind`'s Source, with the batch's database `batch_id`,
  the stored document's item IDs by ref, and `extra` attrs (names,
  `value_as_written`, ...).
  """
  @spec build(map(), atom(), integer(), items(), map()) :: map()
  def build(statement, source_kind, batch_id, items, extra \\ %{}) do
    evidence = List.wrap(statement["evidence"])

    %{
      stance: statement["stance"],
      batch_id: batch_id,
      evidence: quote_evidence(evidence, items),
      observations: observations(evidence)
    }
    |> Map.merge(statement_attrs(evidence, source_kind))
    |> put_present(:status_as_written, statement["status_as_written"])
    |> Map.merge(extra)
  end

  defp quote_evidence(evidence, items) do
    for %{} = e <- evidence, not Map.has_key?(e, "statement") do
      %{
        document_item_id: document_item_id(e, items),
        quote: e["quote"],
        whole_item: e["whole_item"] == true,
        page: e["page"],
        url: e["url"],
        cites_as_written: get_in(e, ["cites", "as_written"])
      }
    end
  end

  # A reading fix's quotes name the stored Source's item by its ID.
  defp document_item_id(%{"gallformers_document_item_id" => id}, _items) when is_integer(id),
    do: id

  defp document_item_id(e, items), do: e["item"] && Map.get(items, e["item"])

  defp observations(evidence) do
    for %{} = e <- evidence,
        %{} = o <- List.wrap(e["observations"]),
        uniq: true,
        do: %{
          provider: o["provider"],
          external_id: o["id"],
          url: o["url"],
          quality_grade: o["quality_grade"],
          thumbnail_url: o["thumbnail_url"]
        }
  end

  defp statement_attrs(evidence, :gallformers) do
    case for(%{"statement" => %{} = s} <- evidence, do: s) do
      [] ->
        %{}

      statements ->
        newest_first = Enum.sort_by(statements, & &1["stated_on"], :desc)

        %{
          statement_text: Enum.map_join(newest_first, "\n\n", & &1["text"]),
          stated: hd(newest_first)["stated_on"]
        }
        |> Map.merge(cites(evidence))
    end
  end

  defp statement_attrs(_evidence, _source_kind), do: %{}

  # The newest citing statement's `cites`, with its Source when Gallformers
  # holds it.
  defp cites(evidence) do
    cited =
      for(%{"statement" => %{} = s, "cites" => %{"as_written" => _} = c} <- evidence, do: {s, c})
      |> Enum.sort_by(fn {s, _c} -> s["stated_on"] end, :desc)

    case cited do
      [] ->
        # A newer statement states its whole content: no cite clears one.
        %{cites_as_written: nil, cited_source_id: nil}

      [{_s, c} | _] ->
        source_id = c["source_id"]
        held = is_integer(source_id) and Sources.get_source(source_id) != nil
        %{cites_as_written: c["as_written"], cited_source_id: if(held, do: source_id)}
    end
  end

  @doc """
  `attrs` for a statement of a batch quoting a Gall's Gallformers note
  (`Gallformers.Import.SourceStep.note/2`), or unchanged when there is no
  note: the attribution takes the note's date, and its statement text is
  what it quotes (the whole note for a `whole_item`), joined by " … ".
  """
  @spec with_note(map(), map() | nil) :: map()
  def with_note(attrs, nil), do: attrs

  def with_note(attrs, %{stated_on: stated_on, text: text}) do
    quoted = Enum.map_join(attrs.evidence, " … ", &if(&1.whole_item, do: text, else: &1.quote))
    Map.merge(attrs, %{stated: stated_on, statement_text: quoted})
  end

  @doc """
  An attribution name for a declared taxon (`taxa[]`) in `role`, or nil when
  the taxon did not resolve.
  """
  @spec name(map() | nil, integer() | nil, String.t()) :: map() | nil
  def name(_declared, nil, _role), do: nil
  def name(nil, _taxon_id, _role), do: nil

  def name(declared, taxon_id, role) do
    %{
      taxon_id: taxon_id,
      name_as_written: declared["name_as_written"],
      name_reading: declared["name_reading"],
      role: role
    }
  end

  @doc "The names among `names` that resolved."
  @spec names([map() | nil]) :: [map()]
  def names(names), do: Enum.reject(names, &is_nil/1)

  defp put_present(map, _key, nil), do: map
  defp put_present(map, key, value), do: Map.put(map, key, value)
end
