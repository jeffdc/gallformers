defmodule Gallformers.Import.NotePackage do
  @moduledoc """
  A Gall's Gallformers note as a producer package (`20e5`;
  `priv/import/GALLFORMERS_STATEMENTS.md`, "Reading a Gall's note").

    * `document.json` — the Gall's newest note as a DoclingDocument with one
      body text item, `#/texts/0`, holding the whole text exactly as stored,
      so the importer finds it again (`Gallformers.Sources.store_note/5`).
    * `note.json` — what the producer is told: the Gall's ID and name,
      whether it is undescribed, its Inducer, generation and Hosts, and
      `stated_on`, the date the note's statements take.

  The producer (`services/import-producer`, `produce note`) adds
  `document.txt` and the empty taxonomy batch; phases 3 to 6 run as for any
  Source.
  """

  alias Gallformers.Catalog
  alias Gallformers.Sources

  @species_ranks [:species, :subspecies, :variety, :form]

  @doc """
  The package files for Gall `gall_id`'s newest note, its statements dated
  `stated_on`, or `{:error, :no_note}`.
  """
  @spec files(integer(), Date.t()) :: {:ok, %{String.t() => binary()}} | {:error, :no_note}
  def files(gall_id, %Date{} = stated_on) when is_integer(gall_id) do
    case Sources.list_gall_notes(gall_id) do
      [] ->
        {:error, :no_note}

      [newest | _] ->
        text = newest |> Sources.list_document_items() |> Enum.map_join("\n\n", & &1.text)

        {:ok,
         %{
           "document.json" => Jason.encode!(document(text, "gallformers-note-#{gall_id}")),
           "note.json" => Jason.encode!(note(gall_id, stated_on), pretty: true)
         }}
    end
  end

  @doc """
  The IDs of the Galls with a Gallformers note, in order: `:undescribed`
  ones (no species-rank Inducer), `:described` ones, or `:all`.
  """
  @spec gall_ids(:undescribed | :described | :all) :: [integer()]
  def gall_ids(which) when which in [:undescribed, :described, :all] do
    ids =
      case Sources.get_gallformers_source() do
        nil -> []
        source -> Sources.list_noted_gall_ids(source.id)
      end

    case which do
      :all -> ids
      :undescribed -> Enum.filter(ids, &undescribed?(Catalog.gall_summary(&1)))
      :described -> Enum.reject(ids, &undescribed?(Catalog.gall_summary(&1)))
    end
  end

  defp undescribed?(summary), do: not Enum.any?(summary.inducers, &(&1.rank in @species_ranks))

  defp note(gall_id, stated_on) do
    summary = Catalog.gall_summary(gall_id)

    inducer =
      case summary.inducers do
        [first | _] -> %{"name" => first.name, "rank" => Atom.to_string(first.rank)}
        [] -> nil
      end

    %{
      "gallformers_gall_id" => gall_id,
      "name" => summary.name,
      "undescribed" => undescribed?(summary),
      "inducer" => inducer,
      "generation" => summary.generation,
      "hosts" => Enum.map(summary.hosts, & &1.name),
      "stated_on" => Date.to_iso8601(stated_on)
    }
  end

  # The same shape as the producer's (`producer.note.document`).
  defp document(text, name) do
    %{
      "schema_name" => "DoclingDocument",
      "version" => "1.7.0",
      "name" => name,
      "furniture" => %{
        "self_ref" => "#/furniture",
        "children" => [],
        "content_layer" => "furniture"
      },
      "body" => %{
        "self_ref" => "#/body",
        "children" => [%{"$ref" => "#/texts/0"}],
        "content_layer" => "body"
      },
      "groups" => [],
      "texts" => [
        %{
          "self_ref" => "#/texts/0",
          "parent" => %{"$ref" => "#/body"},
          "children" => [],
          "content_layer" => "body",
          "label" => "text",
          "prov" => [],
          "orig" => text,
          "text" => text
        }
      ],
      "pictures" => [],
      "tables" => [],
      "pages" => %{}
    }
  end
end
